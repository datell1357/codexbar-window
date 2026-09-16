#if os(Windows)
import Foundation
import WinSDK

@main
struct CodexBarWindowsMain {
    static func main() {
        if let result = WindowsConfigurationBackupCommand.run(arguments: Array(CommandLine.arguments.dropFirst())) {
            ExitProcess(result)
        }
        do {
            let instance = try WindowsApplicationInstance.acquire()
            withExtendedLifetime(instance) {
                self.runApplication()
                // Keep the startup lease even if session-ending cleanup exhausted its budget.
                // The kernel releases it at process exit, after the other process threads stop.
                ExitProcess(0)
            }
        } catch let failure as WindowsApplicationInstance.Failure {
            let message: String
            switch failure {
            case .occupied:
                message = "CodexBar: the startup lock is in use; no additional runtime was started.\n"
            case .windows, .invalidStorage:
                message = "CodexBar: startup ownership could not be established; no runtime was started.\n"
            }
            FileHandle.standardError.write(Data(message.utf8))
            ExitProcess(failure.exitCode)
        } catch {
            FileHandle.standardError.write(Data("CodexBar: startup ownership failed; no runtime was started.\n".utf8))
            ExitProcess(UINT(ERROR_GEN_FAILURE))
        }
    }

    private static func runApplication() {
        let application = WindowsTrayApplication()
        application.run()
    }
}

private final class WindowsTrayApplication: @unchecked Sendable {
    private let cursorBrowserImports = WindowsCursorBrowserImportTask()
    private let augmentBrowserImports = WindowsCursorBrowserImportTask()
    private let windsurfBrowserImports = WindowsCursorBrowserImportTask()
    private let zedEditorImports = WindowsCursorBrowserImportTask()
    private let runtime: WindowsUsageRuntime
    private let sessions: WindowsAgentSessionsRuntime
    private let remoteSessions: WindowsRemoteSessionsRuntime
    private let shutdownSignal = DispatchSemaphore(value: 0)
    private lazy var host: WindowsTrayHost = WindowsTrayHost(
        onRefresh: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.refreshIncludingPluginDiscovery() }
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
        onTokenActivityRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.tokenActivityResult()
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onSpendHoursRequested: { [weak self] requestID, generation, day, currency in
            guard let self else { return }
            Task {
                let result = await self.runtime.spendHourlyResult(day: day, currency: currency, generation: generation)
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onSpendHistoryRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.spendHistoryResult()
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onPlanHistoryRequested: { [weak self] requestID, providerID, contextToken in
            guard let self else { return }
            Task {
                let result = await self.runtime.planUtilizationHistorySnapshot(
                    providerID: providerID, contextToken: contextToken)
                self.host.postPlanHistory(requestID: requestID, result: result)
            }
        },
        onCursorBrowserImportRequested: { [weak self] requestID in
            guard let self else { return }
            self.cursorBrowserImports.start(id: requestID) { [weak self] in
                guard let self else { return }
                let result = await self.runtime.discoverCursorBrowserAccounts(requestID: requestID)
                guard !Task.isCancelled else { return }
                self.host.postCursorBrowserImport(requestID: requestID, result: result)
            }
        },
        onCursorBrowserImportSave: { [weak self] hostID, ticket, candidate, label in
            guard let self else { return }
            Task {
                let result = await self.runtime.importCursorBrowserAccount(requestID: ticket, candidateID: candidate, label: label)
                await self.runtime.cancelCursorBrowserImport(requestID: ticket)
                self.host.postCursorBrowserImportSave(requestID: hostID, result: result)
            }
        },
        onCursorBrowserImportCancel: { [weak self] ticket in
            guard let self else { return }
            self.cursorBrowserImports.cancel(id: ticket)
            Task { await self.runtime.cancelCursorBrowserImport(requestID: ticket) }
        },
        onAugmentBrowserImportRequested: { [weak self] requestID in
            guard let self else { return }
            self.augmentBrowserImports.start(id: requestID) { [weak self] in
                guard let self else { return }
                let result = await self.runtime.discoverAugmentBrowserAccounts(requestID: requestID)
                guard !Task.isCancelled else { return }
                self.host.postAugmentBrowserImport(requestID: requestID, result: result)
            }
        },
        onAugmentBrowserImportSave: { [weak self] hostID, ticket, candidate, label in
            guard let self else { return }
            Task {
                let result = await self.runtime.importAugmentBrowserAccount(requestID: ticket, candidateID: candidate, label: label)
                await self.runtime.cancelAugmentBrowserImport(requestID: ticket)
                self.host.postAugmentBrowserImportSave(requestID: hostID, result: result)
            }
        },
        onAugmentBrowserImportCancel: { [weak self] ticket in
            guard let self else { return }
            self.augmentBrowserImports.cancel(id: ticket)
            Task { await self.runtime.cancelAugmentBrowserImport(requestID: ticket) }
        },
        onWindsurfBrowserImportRequested: { [weak self] requestID, browser, profileDirectory in
            guard let self else { return }
            self.windsurfBrowserImports.start(id: requestID) { [weak self] in
                guard let self else { return }
                let result = await self.runtime.discoverWindsurfBrowserAccounts(requestID: requestID, browser: browser, profileDirectory: profileDirectory)
                guard !Task.isCancelled else { return }
                self.host.postWindsurfBrowserImport(requestID: requestID, result: result)
            }
        },
        onWindsurfBrowserImportSave: { [weak self] hostID, ticket, candidate, label in
            guard let self else { return }
            Task {
                let result = await self.runtime.importWindsurfBrowserAccount(requestID: ticket, candidateID: candidate, label: label)
                await self.runtime.cancelWindsurfBrowserImport(requestID: ticket)
                self.host.postWindsurfBrowserImportSave(requestID: hostID, result: result)
            }
        },
        onWindsurfBrowserImportCancel: { [weak self] ticket in
            guard let self else { return }
            self.windsurfBrowserImports.cancel(id: ticket)
            Task { await self.runtime.cancelWindsurfBrowserImport(requestID: ticket) }
        },
        onZedEditorServerRequested: { [weak self] requestID in
            guard let self else { return }
            self.zedEditorImports.start(id: requestID) { [weak self] in
                guard let self else { return }
                let privacy = WindowsUsagePresentationSettings.load().hidePersonalInfo
                let task = Task.detached(priority: .utility) {
                    try WindowsZedEditorSettings.suggestedConfiguration()
                }
                let configuration: WindowsZedEditorSettings.Configuration?
                do {
                    configuration = try await withTaskCancellationHandler {
                        try await task.value
                    } onCancel: { task.cancel() }
                } catch { configuration = nil }
                guard !Task.isCancelled else { return }
                self.host.postZedEditorImport(requestID: requestID,
                    result: .serverSuggestion(configuration: configuration, privacy: privacy))
            }
        },
        onZedEditorImportRequested: { [weak self] requestID, configuration in
            guard let self else { return }
            self.zedEditorImports.start(id: requestID) { [weak self] in
                guard let self else { return }
                let result = await self.runtime.discoverZedEditorAccount(requestID: requestID, serviceURL: configuration.serverURL,
                    credentialServiceURL: configuration.credentialServiceURL)
                guard !Task.isCancelled else { return }
                self.host.postZedEditorImport(requestID: requestID, result: result)
            }
        },
        onZedEditorImportSave: { [weak self] hostID, ticket, label in
            guard let self else { return }
            Task {
                let result = await self.runtime.importZedEditorAccount(requestID: ticket, label: label)
                await self.runtime.cancelZedEditorImport(requestID: ticket)
                self.host.postZedEditorImportSave(requestID: hostID, result: result)
            }
        },
        onZedEditorImportCancel: { [weak self] ticket in
            guard let self else { return }
            self.zedEditorImports.cancel(id: ticket)
            Task { await self.runtime.cancelZedEditorImport(requestID: ticket) }
        },
        onSpendJSONRequested: { [weak self] requestID, copy in
            guard let self else { return }
            Task {
                let result = await self.runtime.spendJSONResult(copy: copy)
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onShareStatsPreviewRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.shareStatsImageResult(preview: true)
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
        },
        onShareStatsImageCopyRequested: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.shareStatsImageResult(copyToClipboard: true)
                self.host.postShareStatsCopy(requestID: requestID, result: result)
            }
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
                let result = await self.runtime.spendSummaryResult()
                self.host.postSpendSummary(requestID: requestID, result: result)
            }
        },
        onSpendSettingsChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.spendSettingsDidChange() }
        },
        onStatusChecksChanged: { [weak self] in
            guard let self else { return }
            Task { await self.runtime.statusChecksDidChange() }
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
        onPluginBackupRestoreLoad: { [weak self] requestID, source in
            guard let self else { return }
            Task {
                do {
                    let review = try await self.runtime.reviewPluginBackupRestoration(source: source)
                    self.host.postPluginApproval(requestID: requestID, reply: .replacement(review))
                } catch {
                    self.host.postPluginApproval(requestID: requestID, reply: .replacementFailed(.classify(error)))
                }
            }
        },
        onFailedPluginFileRemovalLoad: { [weak self] requestID, source in
            guard let self else { return }
            Task {
                do {
                    let review = try await self.runtime.reviewFailedPluginFileRemoval(source: source)
                    self.host.postPluginApproval(requestID: requestID, reply: .removal(review))
                } catch {
                    self.host.postPluginApproval(requestID: requestID, reply: .removalFailed(.classify(error)))
                }
            }
        },
        onPluginRemovalLoad: { [weak self] requestID, instanceID in
            guard let self else { return }
            Task {
                do {
                    let review = try await self.runtime.reviewPluginRemoval(instanceID: instanceID)
                    self.host.postPluginApproval(requestID: requestID, reply: .removal(review))
                } catch {
                    self.host.postPluginApproval(requestID: requestID, reply: .removalFailed(.classify(error)))
                }
            }
        },
        onPluginRemovalSave: { [weak self] requestID, token in
            guard let self else { return }
            Task {
                do {
                    let outcome = try await self.runtime.removeReviewedPlugin(token: token)
                    switch outcome {
                    case .providerRemoved: self.host.postPluginApproval(requestID: requestID, reply: .removed)
                    case .failedFileRemoved: self.host.postPluginApproval(requestID: requestID, reply: .failedFileRemoved)
                    }
                } catch {
                    await self.runtime.cancelPluginRemoval(token: token)
                    self.host.postPluginApproval(requestID: requestID, reply: .removalFailed(.classify(error)))
                }
            }
        },
        onPluginRemovalCancel: { [weak self] token in
            guard let self else { return }
            Task { await self.runtime.cancelPluginRemoval(token: token) }
        },
        onPluginReplacementLoad: { [weak self] requestID, instanceID, source in
            guard let self else { return }
            Task {
                do {
                    let review = try await self.runtime.reviewPluginReplacement(instanceID: instanceID, source: source)
                    self.host.postPluginApproval(requestID: requestID, reply: .replacement(review))
                } catch {
                    self.host.postPluginApproval(requestID: requestID, reply: .replacementFailed(.classify(error)))
                }
            }
        },
        onPluginReplacementSave: { [weak self] requestID, token in
            guard let self else { return }
            Task {
                do {
                    let outcome = try await self.runtime.replaceReviewedPlugin(token: token)
                    switch outcome {
                    case .replaced: self.host.postPluginApproval(requestID: requestID, reply: .replaced)
                    case .reinstalled: self.host.postPluginApproval(requestID: requestID, reply: .reinstalled)
                    case .restoredBackup: self.host.postPluginApproval(requestID: requestID, reply: .restoredBackup)
                    }
                } catch {
                    await self.runtime.cancelPluginReplacement(token: token)
                    self.host.postPluginApproval(requestID: requestID, reply: .replacementFailed(.classify(error)))
                }
            }
        },
        onPluginReplacementCancel: { [weak self] token in
            guard let self else { return }
            Task { await self.runtime.cancelPluginReplacement(token: token) }
        },
        onPluginInstall: { [weak self] requestID, source in
            guard let self else { return }
            Task {
                do {
                    _ = try await self.runtime.installPlugin(source: source)
                    self.host.postPluginApproval(requestID: requestID, reply: .installed)
                } catch let failure as WindowsPluginInstallFailure {
                    self.host.postPluginApproval(requestID: requestID, reply: .installFailed(failure))
                } catch {
                    self.host.postPluginApproval(requestID: requestID, reply: .installFailed(.storageUnavailable))
                }
            }
        },
        onPluginSettingsLoad: { [weak self] requestID, instanceID in
            guard let self else { return }
            Task {
                do {
                    let snapshot = try await self.runtime.reviewPluginSettings(instanceID: instanceID)
                    self.host.postPluginApproval(requestID: requestID, reply: .settings(snapshot))
                } catch { self.host.postPluginApproval(requestID: requestID, reply: .failed) }
            }
        },
        onPluginSettingsSave: { [weak self] requestID, token, changes in
            guard let self else { return }
            Task {
                do {
                    try await self.runtime.saveReviewedPluginSettings(token: token, changes: changes)
                    self.host.postPluginApproval(requestID: requestID, reply: .saved)
                } catch {
                    await self.runtime.cancelPluginSettingsReview(token: token)
                    self.host.postPluginApproval(requestID: requestID, reply: .failed)
                }
            }
        },
        onPluginSettingsCancel: { [weak self] token in
            guard let self else { return }
            Task { await self.runtime.cancelPluginSettingsReview(token: token) }
        },
        onPluginApprovalLoad: { [weak self] requestID, instanceID in
            guard let self else { return }
            Task {
                do {
                    let review = try await self.runtime.reviewPluginApproval(instanceID: instanceID)
                    self.host.postPluginApproval(requestID: requestID, reply: .review(review))
                } catch { self.host.postPluginApproval(requestID: requestID, reply: .failed) }
            }
        },
        onPluginEnabledSave: { [weak self] requestID, token, enabled in
            guard let self else { return }
            Task {
                do {
                    try await self.runtime.setReviewedPluginEnabled(token: token, enabled: enabled)
                    self.host.postPluginApproval(requestID: requestID, reply: .saved)
                } catch { self.host.postPluginApproval(requestID: requestID, reply: .failed) }
            }
        },
        onPluginApprovalRevoke: { [weak self] requestID, token in
            guard let self else { return }
            Task {
                do {
                    try await self.runtime.revokeReviewedPlugin(token: token)
                    self.host.postPluginApproval(requestID: requestID, reply: .saved)
                } catch { self.host.postPluginApproval(requestID: requestID, reply: .failed) }
            }
        },
        onPluginApprovalSave: { [weak self] requestID, token, origins in
            guard let self else { return }
            Task {
                do {
                    try await self.runtime.approveReviewedPlugin(token: token, typedOrigins: origins)
                    self.host.postPluginApproval(requestID: requestID, reply: .saved)
                } catch { self.host.postPluginApproval(requestID: requestID, reply: .failed) }
            }
        },
        onHookSettingsLoad: { [weak self] requestID in
            guard let self else { return }
            Task {
                let result = await self.runtime.loadHookSettings()
                self.host.postHookSettingsLoad(requestID: requestID, result: result)
            }
        },
        onHookSettingsSave: { [weak self] requestID, snapshot, mutation in
            guard let self else { return }
            Task {
                let result = await self.runtime.saveHookSettings(expected: snapshot, mutation: mutation)
                self.host.postHookSettingsSave(requestID: requestID, result: result)
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
            await runtime.prepareWidgetActivation()
            await remoteSessions.setPublisher { [weak host] snapshot in
                host?.postRemoteSessions(snapshot)
            }
            await remoteSessions.start()
            await sessions.setPublisher { [weak host] snapshot in
                host?.postAgentSessions(snapshot)
            }
            await sessions.start()
            await runtime.setConfiguredPluginPublisher { [weak host] ids in
                host?.postConfiguredPluginIDs(ids)
            }
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
            if await self.runtime.widgetBackendCleanupFailed {
                FileHandle.standardError.write(Data(
                    "CodexBar: widget backend cleanup is incomplete; the widget host may still need to exit.\n".utf8))
            }
            if await self.runtime.widgetHostShutdownWasForced {
                FileHandle.standardError.write(Data(
                    "CodexBar: a widget host required forced termination; OS widget withdrawal was not confirmed.\n".utf8))
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
