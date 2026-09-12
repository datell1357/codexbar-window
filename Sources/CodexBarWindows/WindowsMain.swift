#if os(Windows)
import Foundation

@main
struct CodexBarWindowsMain {
    static func main() {
        let application = WindowsTrayApplication()
        application.run()
    }
}

private final class WindowsTrayApplication: @unchecked Sendable {
    private let runtime: WindowsUsageRuntime
    private let sessions: WindowsAgentSessionsRuntime
    private let remoteSessions: WindowsRemoteSessionsRuntime
    private let shutdownSignal = DispatchSemaphore(value: 0)
    private lazy var host: WindowsTrayHost = WindowsTrayHost(
        onRefresh: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.refresh() }
            Task { await self.sessions.refresh() }
            Task { await self.remoteSessions.refresh() }
        },
        onQuit: {},
        onPowerChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.notePowerChanged() }
        },
        onMenuOpen: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.noteMenuOpened() }
            Task { await self.sessions.refresh() }
            Task { await self.remoteSessions.refresh() }
        },
        onAgentSessionsSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.sessions.settingsDidChange() }
        },
        onAgentSessionsRefresh: { [weak self] in
            guard let self else { return }
            Task { await self.sessions.refresh() }
        },
        onAgentSessionFocus: { [weak self] request in
            guard let self else { return }
            Task { await self.sessions.focus(request) }
        },
        onRemoteSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.remoteSessions.settingsDidChange() }
        },
        onRemoteRefresh: { [weak self] in
            guard let self else { return }
            Task { await self.remoteSessions.refresh() }
        },
        onRemoteFocus: { [weak self] request in
            guard let self else { return }
            Task { await self.remoteSessions.focus(request) }
        },
        onPresentationSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.presentationSettingsDidChange() }
            Task { await self.sessions.presentationDidChange() }
            Task { await self.remoteSessions.presentationDidChange() }
        },
        onOptionalUsageSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.optionalUsageSettingsDidChange() }
        },
        onRefreshSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.refreshSettingsDidChange() }
        },
        onSessionQuotaNotificationSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.sessionQuotaNotificationSettingsDidChange() }
        },
        onQuotaWarningSettingsChanged: { [weak self] settings in
            guard let self else { return }
            Task { await self.runtime.quotaWarningSettingsDidChange(settings) }
        },
        onProviderQuotaWarningLoad: { [weak self] requestID, providerID in
            guard let self else { return }
            Task {
                let result = await self.runtime.loadProviderQuotaWarningEditor(providerID: providerID)
                self.host.postProviderQuotaWarningLoad(requestID: requestID, providerID: providerID, result: result)
            }
        },
        onProviderQuotaWarningSave: { [weak self] requestID, providerID, patch in
            guard let self else { return }
            Task {
                let result = await self.runtime.saveProviderQuotaWarnings(providerID: providerID, patch: patch)
                self.host.postProviderQuotaWarningSave(requestID: requestID, providerID: providerID, result: result)
            }
        },
        onCodexWebSettingsLoad: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.loadCodexWebSettings()
                self.host.postCodexWebSettingsLoad(requestID: requestID, result: result)
            }
        },
        onCodexWebSettingsSave: { [weak self] requestID, patch in
            guard let self else { return }
            Task {
                let result = await self.runtime.saveCodexWebSettings(patch: patch)
                self.host.postCodexWebSettingsSave(requestID: requestID, result: result)
                if case .saved = result {
                    await self.runtime.refresh()
                }
            }
        },
        onPredictivePaceWarningSettingsChanged: { [weak self] settings in
            guard let self else { return }
            Task { await self.runtime.predictivePaceWarningSettingsDidChange(settings) }
        })

    init() {
        self.runtime = WindowsUsageRuntime()
        self.sessions = WindowsAgentSessionsRuntime()
        self.remoteSessions = WindowsRemoteSessionsRuntime()
    }

    func run() {
        let host = self.host
        Task { [runtime, sessions, remoteSessions] in
            await remoteSessions.setPublisher { [weak host] snapshot in
                host?.postRemoteSessions(snapshot)
            }
            await remoteSessions.start()
            await sessions.setPublisher { [weak host] snapshot in
                host?.postAgentSessions(snapshot)
            }
            await sessions.start()
            await runtime.setCombinedPublisher { [weak host] rows, entries in
                host?.postRows(rows, menuEntries: entries)
            }
            await runtime.setNotificationPublisher { [weak host] event in
                host?.postSessionQuotaNotification(event)
            }
            await runtime.setQuotaWarningPublisher { [weak host] event in
                host?.postQuotaWarningNotification(event)
            }
            await runtime.setPredictivePaceWarningPublisher { [weak host] event in
                host?.postPredictivePaceWarningNotification(event)
            }
            await runtime.start()
        }
        do {
            try host.run()
        } catch {
            FileHandle.standardError.write(Data("CodexBar tray failed: \(error.localizedDescription)\n".utf8))
        }
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.sessions.shutdown() }
                group.addTask { await self.remoteSessions.shutdown() }
                group.addTask { await self.runtime.shutdown() }
                await group.waitForAll()
            }
            self.shutdownSignal.signal()
        }
        // WM_CLOSE schedules asynchronous cleanup. Keep the process alive until
        // the runtime has cancelled refresh work and released persistent helpers.
        self.shutdownSignal.wait()
    }
}
#endif
