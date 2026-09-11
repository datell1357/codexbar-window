import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Portable HTTP-only access to the data exposed by the OpenAI dashboard APIs.
///
/// The browser dashboard also contains DOM-rendered credit history and usage
/// charts. Those fields are intentionally empty here; callers that need them
/// must continue to use the macOS WebKit fetcher.
public struct OpenAIDashboardHTTPClient: Sendable {
    public enum FetchError: LocalizedError, Sendable {
        case loginRequired
        case noDashboardData(body: String)

        public var errorDescription: String? {
            switch self {
            case .loginRequired:
                "OpenAI web access requires login."
            case let .noDashboardData(body):
                "OpenAI dashboard data not found. Body sample: \(body.prefix(200))"
            }
        }
    }

    private let cookieHeader: String
    private let deadline: Date
    private let transport: any ProviderHTTPTransport

    public init(
        cookieHeader: String,
        deadline: Date,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared)
    {
        self.cookieHeader = cookieHeader
        self.deadline = deadline
        self.transport = transport
    }

    public init(
        cookieHeader: String,
        timeout: TimeInterval = 4,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared)
    {
        let boundedTimeout = timeout.isFinite && timeout > 0 ? timeout : 1
        self.init(
            cookieHeader: cookieHeader,
            deadline: Date().addingTimeInterval(boundedTimeout),
            transport: transport)
    }

    /// Fetches the API-backed portion of the dashboard after verifying the
    /// signed-in email through `/backend-api/me` or `/api/auth/session`.
    public func fetchSnapshot() async throws -> OpenAIDashboardSnapshot {
        try Task.checkCancellation()
        guard !self.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FetchError.loginRequired
        }

        let usageResponse = try await self.fetchUsageResponse()
        try Task.checkCancellation()
        guard let signedInEmail = try await self.fetchSignedInEmail() else {
            throw FetchError.loginRequired
        }

        try Task.checkCancellation()
        var codexCreditLimit = usageResponse.resolvedIndividualLimit?.codexCreditLimitSnapshot(updatedAt: Date())
        // Spend-controls enrichment is optional, matching the macOS fetcher: an unavailable endpoint
        // does not invalidate the primary usage response.
        if codexCreditLimit == nil,
           CodexSpendControlsMonthlyUsageGate.shouldFetch(response: usageResponse),
           let accountId = usageResponse.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty,
           let spendControlsTimeout = self.remainingTimeout(cappedAt: 4),
           let request = Self.spendControlsRequest(accountId: accountId, cookieHeader: self.cookieHeader,
                                                   timeout: spendControlsTimeout)
        {
            do {
                let (data, response) = try await self.transport.data(for: request)
                if Self.isSuccessful(response),
                   let decoded = try? JSONDecoder().decode(CodexSpendControlsMonthlyUsageResponse.self, from: data)
                {
                    codexCreditLimit = decoded.codexCreditLimitSnapshot(updatedAt: Date()) ?? codexCreditLimit
                }
            } catch {
                try Self.rethrowCancellationOrTimeout(error)
            }
        }

        // Subscription metadata is also best-effort; ordinary endpoint/decoding failures return nil.
        try Task.checkCancellation()
        let subscription = try await self.fetchSubscription()
        try Task.checkCancellation()
        guard self.deadline.timeIntervalSinceNow > 0 else { throw URLError(.timedOut) }
        let primary = Self.rateWindow(from: usageResponse.rateLimit?.primaryWindow)
        let secondary = Self.rateWindow(from: usageResponse.rateLimit?.secondaryWindow)
        return OpenAIDashboardSnapshot(
            signedInEmail: signedInEmail,
            codeReviewRemainingPercent: nil,
            codeReviewLimit: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            primaryLimit: primary,
            secondaryLimit: secondary,
            extraRateWindows: CodexAdditionalRateLimitMapper.extraRateWindows(
                from: usageResponse.additionalRateLimits),
            creditsRemaining: usageResponse.credits?.balance,
            codexCreditLimit: codexCreditLimit,
            accountPlan: usageResponse.planType?.rawValue,
            subscriptionExpiresAt: subscription?.expiresAt,
            subscriptionRenewsAt: subscription?.renewsAt,
            updatedAt: Date())
    }

    private func fetchUsageResponse() async throws -> CodexUsageResponse {
        guard let timeout = self.remainingTimeout(cappedAt: 4) else { throw URLError(.timedOut) }
        do {
            let (data, response) = try await self.transport.data(for: Self.usageRequest(
                cookieHeader: self.cookieHeader,
                timeout: timeout))
            guard Self.isSuccessful(response) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if status == 401 || status == 403 { throw FetchError.loginRequired }
                throw FetchError.noDashboardData(body: "HTTP status \(status)")
            }
            return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch let error as FetchError {
            throw error
        } catch {
            try Self.rethrowCancellationOrTimeout(error)
            throw FetchError.noDashboardData(body: error.localizedDescription)
        }
    }

    private func fetchSignedInEmail() async throws -> String? {
        let endpoints = [
            URL(string: "https://chatgpt.com/backend-api/me")!,
            URL(string: "https://chatgpt.com/api/auth/session")!,
        ]
        for endpoint in endpoints {
            guard let timeout = self.remainingTimeout(cappedAt: 2) else { throw URLError(.timedOut) }
            do {
                let (data, response) = try await self.transport.data(for: Self.request(
                    url: endpoint,
                    cookieHeader: self.cookieHeader,
                    timeout: timeout))
                guard Self.isSuccessful(response) else { continue }
                if let email = Self.firstEmail(in: data) {
                    return email.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                try Self.rethrowCancellationOrTimeout(error)
                continue
            }
        }
        return nil
    }

    private func fetchSubscription() async throws -> OpenAISubscriptionMetadata? {
        guard let timeout = self.remainingTimeout(cappedAt: 2) else { return nil }
        let endpoint = URL(string: "https://chatgpt.com/backend-api/subscriptions")!
        do {
            let (data, response) = try await self.transport.data(for: Self.request(
                url: endpoint, cookieHeader: self.cookieHeader, timeout: timeout))
            guard Self.isSuccessful(response),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let activeUntilValue = json["active_until"] ?? json["activeUntil"],
                  let willRenewValue = json["will_renew"] ?? json["willRenew"]
            else { return nil }
            let activeUntil = activeUntilValue as? String
            let willRenew = willRenewValue as? Bool
            guard activeUntilValue is NSNull || activeUntil != nil,
                  willRenewValue is NSNull || willRenew != nil
            else { return nil }
            return OpenAISubscriptionMetadata.parseResult(
                activeUntil: activeUntil,
                willRenew: willRenew,
                fieldsPresent: true).metadata
        } catch {
            try Self.rethrowCancellationOrTimeout(error)
            return nil
        }
    }

    private func remainingTimeout(cappedAt cap: TimeInterval) -> TimeInterval? {
        let remaining = min(cap, self.deadline.timeIntervalSinceNow)
        return remaining > 0 ? remaining : nil
    }

    private static func isSuccessful(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private static func rethrowCancellationOrTimeout(_ error: Error) throws {
        if error is CancellationError {
            throw error
        }
        if let urlError = error as? URLError,
           urlError.code == .cancelled || urlError.code == .timedOut
        {
            throw error
        }
    }

    private static func request(url: URL, cookieHeader: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("CodexBar", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func usageRequest(cookieHeader: String, timeout: TimeInterval) -> URLRequest {
        request(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, cookieHeader: cookieHeader, timeout: timeout)
    }

    private static func spendControlsRequest(accountId: String, cookieHeader: String, timeout: TimeInterval) -> URLRequest? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.subtract(CharacterSet(charactersIn: "/?#%"))
        guard let encoded = accountId.addingPercentEncoding(withAllowedCharacters: allowed), !encoded.isEmpty else { return nil }
        let url = URL(string: "https://chatgpt.com/backend-api/accounts/\(encoded)/spend-controls/current-user/monthly-usage")!
        return request(url: url, cookieHeader: cookieHeader, timeout: timeout)
    }

    private static func rateWindow(from window: CodexUsageResponse.WindowSnapshot?) -> RateWindow? {
        guard let window else { return nil }
        let resetDate = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        return RateWindow(usedPercent: Double(window.usedPercent), windowMinutes: window.limitWindowSeconds / 60,
                          resetsAt: resetDate, resetDescription: UsageFormatter.resetDescription(from: resetDate))
    }

    private static func firstEmail(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var queue: [Any] = [root]
        var seen = 0
        while !queue.isEmpty, seen < 2_000 {
            let value = queue.removeFirst()
            seen += 1
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if key.lowercased() == "email", let email = child as? String, email.contains("@") { return email }
                    queue.append(child)
                }
            } else if let array = value as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return nil
    }
}
