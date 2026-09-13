# Best effort notification only. A registry write and a recipient refresh are distinct outcomes.
function Send-CodexBarEnvironmentChange {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return 'UNAVAILABLE_PLATFORM' }
    try {
        if ($null -eq ('CodexBar.EnvironmentNotificationV1' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CodexBar {
    public static class EnvironmentNotificationV1 {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeoutW(IntPtr window, uint message,
            UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
        public static bool Send() {
            UIntPtr result;
            // Synchronous string marshalling retains the Environment buffer for the call.
            // 100 ms applies to each recipient, NOT to the entire broadcast.
            return SendMessageTimeoutW(new IntPtr(0xffff), 0x001a, UIntPtr.Zero,
                "Environment", 0x0001 | 0x0002, 100, out result) != IntPtr.Zero;
        }
    }
}
'@ -ErrorAction Stop
        }
        if ([CodexBar.EnvironmentNotificationV1]::Send()) { return 'SENT_REFRESH_NOT_GUARANTEED' }
        return 'FAILED_OR_TIMED_OUT'
    } catch {
        # Policy can prohibit Add-Type or native calls. Never reinterpret a completed PATH write as rolled back.
        return 'UNAVAILABLE_OR_FAILED'
    }
}
