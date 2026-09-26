using System.Buffers.Binary;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32.SafeHandles;

namespace CodexBar.App;

internal sealed record AppSettings([property: JsonRequired] bool HidePersonalInfo,
    [property: JsonRequired] bool ShowOptionalCreditsAndExtraUsage,
    [property: JsonRequired] bool UsageBarsShowUsed, [property: JsonRequired] bool ResetTimesShowAbsolute);
public sealed record ProviderCard([property: JsonRequired] string Id,
    [property: JsonRequired] string Title, [property: JsonRequired] string[] Rows)
{
    public string Body => string.Join(Environment.NewLine, Rows);
}
internal sealed record AppSnapshot([property: JsonRequired] ProviderCard[] Providers,
    [property: JsonRequired] string[] Notices, [property: JsonRequired] string SpendSummary,
    [property: JsonRequired] bool Refreshing, [property: JsonRequired] bool Truncated,
    [property: JsonRequired] AppSettings Settings, [property: JsonRequired] string SettingsRevision);
internal sealed record SettingMutation(string Key, bool Value, string ExpectedSettingsRevision);
internal sealed record AppResponse([property: JsonRequired] int ProtocolVersion,
    [property: JsonRequired] Guid RequestID, [property: JsonRequired] Guid Generation,
    [property: JsonRequired] string Status, AppSnapshot? Snapshot, [property: JsonRequired] ulong Activation,
    SpendPage? Spend);
internal sealed record AppRequest(int ProtocolVersion, Guid RequestID, Guid? Generation, string Method,
    SettingMutation? Mutation, SpendQuery? SpendQuery);

/// This process listens; the existing Swift runtime connects. The direction does not confer authority:
/// both sides check the native peer PID, and this server admits only the current Windows user.
internal sealed class BackendChannel : IDisposable
{
    private const int MaximumRequestBytes = 4096;
    private const int MaximumResponseBytes = 1024 * 1024;
    private readonly NamedPipeServerStream pipe;
    private readonly Process backend;
    private readonly SemaphoreSlim serial = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    private readonly JsonSerializerOptions json = new(JsonSerializerDefaults.Web) { MaxDepth = 32 };
    private Guid? generation;
    private bool disposed;

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint processId);

    private BackendChannel(string name, Process backend)
    {
        this.backend = backend;
        // Acquire the process handle now so a later PID reuse cannot replace the monitored backend.
        _ = backend.SafeHandle;
        pipe = NativePipe.Create(name);
    }

    public static BackendChannel FromArguments(string[] arguments)
    {
        if (arguments.Length != 4 || arguments[0] != "--pipe" || arguments[2] != "--backend-pid"
            || !arguments[1].StartsWith("CodexBar.UI.", StringComparison.Ordinal)
            || !Guid.TryParseExact(arguments[1]["CodexBar.UI.".Length..], "D", out _)
            || !int.TryParse(arguments[3], out var pid) || pid <= 0)
            throw new ArgumentException("Invalid app launch.");
        var process = Process.GetProcessById(pid);
        try
        {
            var expected = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "CodexBarWindows.exe"));
            if (process.HasExited || process.SessionId != Process.GetCurrentProcess().SessionId
                || !string.Equals(process.MainModule?.FileName, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Invalid backend.");
            return new BackendChannel(arguments[1], process);
        }
        catch { process.Dispose(); throw; }
    }

    public bool BackendExited
    {
        get
        {
            try { return backend.HasExited; }
            catch (InvalidOperationException) { return true; }
            catch (System.ComponentModel.Win32Exception) { return true; }
        }
    }

    public async Task<AppResponse> SendAsync(string method, SettingMutation? mutation, CancellationToken cancellation,
        SpendQuery? spendQuery = null)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation, lifetime.Token);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        var token = timeout.Token;
        await serial.WaitAsync(token);
        try
        {
            if (backend.HasExited) throw new IOException("Backend stopped.");
            if (generation is null)
            {
                if (!pipe.IsConnected) await pipe.WaitForConnectionAsync(token);
                if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle, out var peer)
                    || peer != backend.Id || backend.HasExited)
                    throw new IOException("Invalid backend peer.");
                var hello = await ExchangeAsync("hello", null, token, null);
                if (hello.Status != "ok" || hello.Generation == Guid.Empty)
                    throw new IOException("Handshake rejected.");
                generation = hello.Generation;
                if (method == "snapshot") return hello;
            }
            return await ExchangeAsync(method, mutation, token, spendQuery);
        }
        catch
        {
            generation = null;
            // Never automatically replay a setting mutation after an uncertain write/response.
            try { if (pipe.IsConnected) pipe.Disconnect(); }
            catch (ObjectDisposedException) { }
            throw;
        }
        finally { serial.Release(); }
    }

    private async Task<AppResponse> ExchangeAsync(string method, SettingMutation? mutation, CancellationToken token,
        SpendQuery? spendQuery)
    {
        var id = Guid.NewGuid();
        var payload = JsonSerializer.SerializeToUtf8Bytes(new AppRequest(1, id, generation, method, mutation, spendQuery), json);
        if (payload.Length is 0 or > MaximumRequestBytes) throw new IOException("Request too large.");
        var header = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(header, payload.Length);
        await pipe.WriteAsync(header, token);
        await pipe.WriteAsync(payload, token);
        await pipe.FlushAsync(token);
        await pipe.ReadExactlyAsync(header, token);
        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length is <= 0 or > MaximumResponseBytes) throw new IOException("Invalid response length.");
        var responseBytes = new byte[length];
        await pipe.ReadExactlyAsync(responseBytes, token);
        var response = JsonSerializer.Deserialize<AppResponse>(responseBytes, json)
            ?? throw new IOException("Missing response.");
        if (response.ProtocolVersion != 1 || response.RequestID != id || response.Generation == Guid.Empty
            || string.IsNullOrEmpty(response.Status)
            || (generation is not null && response.Generation != generation))
            throw new IOException("Response does not match the request.");
        if (response.Status == "ok" && (method == "spend" ? response.Spend is null : response.Snapshot is null))
            throw new IOException("Missing snapshot.");
        if (response.Spend is { } spend && !spend.IsValid) throw new IOException("Invalid spend page.");
        if (response.Snapshot is { } snapshot && (snapshot.Providers is null || snapshot.Providers.Length > 256
            || snapshot.Notices is null || snapshot.Notices.Length > 1024 || snapshot.Notices.Any(row => row is null)
            || snapshot.SpendSummary is null || snapshot.Settings is null
            || snapshot.SettingsRevision is null || snapshot.SettingsRevision.Length != 64
            || !snapshot.SettingsRevision.All(Uri.IsHexDigit)
            || snapshot.Providers.Any(card => card is null || card.Id is null || card.Title is null
                || card.Rows is null || card.Rows.Length > 64 || card.Rows.Any(row => row is null))))
            throw new IOException("Invalid snapshot.");
        return response;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        lifetime.Cancel();
        pipe.Dispose();
        // A pending request owns the semaphore until it unwinds; do not dispose it underneath that request.
        backend.Dispose();
    }
}
