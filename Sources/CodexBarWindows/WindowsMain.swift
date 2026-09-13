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
            Task { await self.sessions.refreshIgnoringTitleCache() }
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
        onLocalSessionPage: { [weak self] request in
            guard let self else { return }
            Task {
                if await self.sessions.movePage(request) { self.host.showSessionPage() }
            }
        },
        onRemoteSessionPage: { [weak self] request in
            guard let self else { return }
            Task {
                if await self.remoteSessions.movePage(request) { self.host.showSessionPage() }
            }
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
        onShareStatsImageRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.shareStatsImageResult()
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onSpendSourcesRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.loadSpendSourceSelection()
                self.host.postSpendSources(requestID: requestID, result: result)
            }
        },
        onSpendSourcesSave: { [weak self] requestID, generation, mutation in
            guard let self else { return }
            Task {
                let result = await self.runtime.saveSpendSourceSelection(generation: generation, mutation: mutation)
                self.host.postSpendSources(requestID: requestID, result: result)
            }
        },
        onShareStatsCopyRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.shareStatsCopyResult()
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onSpendSummaryRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let text = await self.runtime.spendSummaryText()
                self.host.postSpendSummary(requestID: requestID, text: text)
            }
        },
        onSpendSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.spendSettingsDidChange() }
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
        onTokenAccountAdd: { [weak self] requestID, request in
            guard let self else { return }
            Task {
                let result = await self.runtime.addTokenAccount(request)
                if case .saved = result { Task { await self.runtime.refresh() } }
                self.host.postTokenAccountAdd(requestID: requestID, result: result)
            }
        },
        onAccountRemovalBegin: { [weak self] requestID, providerID, accountID in
            guard let self else { return }
            Task {
                let result = await self.runtime.beginTokenAccountRemoval(providerID: providerID, accountID: accountID)
                self.host.postAccountRemovalLoad(requestID: requestID, result: result)
            }
        },
        onAccountRemovalSave: { [weak self] requestID, ticketID in
            guard let self else { return }
            Task {
                let result = await self.runtime.removeTokenAccount(ticketID: ticketID)
                await self.runtime.cancelTokenAccountRemoval(ticketID: ticketID)
                if case .removed = result { Task { await self.runtime.refresh() } }
                self.host.postAccountRemovalSave(requestID: requestID, result: result)
            }
        },
        onAccountRemovalCancel: { [weak self] ticketID in
            guard let self else { return }
            Task { await self.runtime.cancelTokenAccountRemoval(ticketID: ticketID) }
        },
        onMetadataEditBegin: { [weak self] requestID, providerID, accountID in
            guard let self else { return }
            Task {
                let result = await self.runtime.beginTokenAccountMetadataEdit(providerID: providerID, accountID: accountID)
                self.host.postMetadataEditLoad(requestID: requestID, result: result)
            }
        },
        onMetadataEditSave: { [weak self] requestID, ticketID, patch in
            guard let self else { return }
            Task {
                let result = await self.runtime.updateTokenAccountMetadata(ticketID: ticketID, patch: patch)
                await self.runtime.cancelTokenAccountCredentialEdit(ticketID: ticketID)
                if case .saved = result { Task { await self.runtime.refresh() } }
                self.host.postMetadataEditSave(requestID: requestID, result: result)
            }
        },
        onCredentialEditBegin: { [weak self] requestID, providerID, accountID in
            guard let self else { return }
            Task {
                let result = await self.runtime.beginTokenAccountCredentialEdit(providerID: providerID, accountID: accountID)
                self.host.postCredentialEditLoad(requestID: requestID, result: result)
            }
        },
        onCredentialEditSave: { [weak self] requestID, ticketID, secret in
            guard let self else { return }
            Task {
                let result = await self.runtime.replaceTokenAccountCredential(ticketID: ticketID, replacement: secret)
                await self.runtime.cancelTokenAccountCredentialEdit(ticketID: ticketID)
                if case .saved = result { Task { await self.runtime.refresh() } }
                self.host.postCredentialEditSave(requestID: requestID, result: result)
            }
        },
        onCredentialEditCancel: { [weak self] ticketID in
            guard let self else { return }
            Task { await self.runtime.cancelTokenAccountCredentialEdit(ticketID: ticketID) }
        },
        onTokenAccountRename: { [weak self] requestID, request in
            guard let self else { return }
            Task {
                let result = await self.runtime.renameTokenAccount(request)
                self.host.postTokenAccountRename(requestID: requestID, result: result)
            }
        },
        onTokenAccountSelect: { [weak self] request in
            guard let self else { return }
            Task {
                let result = await self.runtime.selectTokenAccount(providerID: request.providerID,
                    accountID: request.accountID, expectedSelectedID: request.expectedSelectedID)
                if case .saved = result {
                    Task { await self.runtime.refresh() }
                }
                self.host.postTokenAccountSelection(requestID: request.id, result: result)
            }
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
            await runtime.setAccountInvalidationPublisher { [weak host] providerID in
                host?.invalidateQueuedAccountNotifications(providerID: providerID)
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
        if !host.shutdownCLIPathHelper(timeout: host.isSystemSessionEnding ? 0 : 2) {
            FileHandle.standardError.write(Data(
                "CodexBar: PATH helper cleanup is incomplete; inspect user PATH before retrying setup.\n".utf8))
        }
        // WM_CLOSE schedules asynchronous cleanup. Keep the process alive until
        // the runtime has cancelled refresh work and released persistent helpers.
        if host.isSystemSessionEnding {
            // Windows can terminate the process at any time during session end. Attempt the same
            // helper drain, but do not wait indefinitely or claim it finished when time runs out.
            if self.shutdownSignal.wait(timeout: .now() + 2) == .timedOut {
                FileHandle.standardError.write(Data("CodexBar: system-session cleanup did not finish within the shutdown budget.\n".utf8))
            }
        } else {
            self.shutdownSignal.wait()
        }
    }
}
#endif
