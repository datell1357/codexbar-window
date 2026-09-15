import Foundation

/// Platform-independent history schema and hourly reduction from UsageStore+PlanUtilization.
/// Ownership is supplied by the runtime; this model never adopts another account's samples.
public enum PlanUtilizationHistoryCore {
    public static let maximumSamplesPerSeries = 24 * 730
    public enum Failure: Error, Sendable { case unsupportedVersion, invalidData, capacityExceeded }
    public enum IdentityTransition: Sendable {
        case fixed, antigravityGemini
        case genericResolved(session: String, weekly: String)
        case genericIncomplete(weekly: String?)
        case genericAmbiguous(weekly: String?)
    }

    public struct Entry: Codable, Equatable, Hashable, Sendable {
        public let capturedAt: Date
        public let usedPercent: Double
        public let resetsAt: Date?

        public init(capturedAt: Date, usedPercent: Double, resetsAt: Date?) {
            self.capturedAt = capturedAt
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    public struct Series: Codable, Equatable, Sendable {
        public let name: String
        public let windowMinutes: Int
        public var entries: [Entry]

        public init(name: String, windowMinutes: Int, entries: [Entry]) {
            self.name = name
            self.windowMinutes = windowMinutes
            self.entries = entries
        }
    }

    public struct Document: Codable, Equatable, Sendable {
        public var version: Int = 1
        public var preferredAccountKey: String?
        public var unscoped: [Series] = []
        public var accounts: [String: [Series]] = [:]
        public var sessionEquivalentWindowPairIdentities: [String: String] = [:]

        public init() {}

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decode(Int.self, forKey: .version)
            guard self.version == 1 else { throw Failure.unsupportedVersion }
            self.preferredAccountKey = try container.decodeIfPresent(String.self, forKey: .preferredAccountKey)
            self.unscoped = try container.decode([Series].self, forKey: .unscoped)
            self.accounts = try container.decode([String: [Series]].self, forKey: .accounts)
            self.sessionEquivalentWindowPairIdentities = try container.decodeIfPresent(
                [String: String].self, forKey: .sessionEquivalentWindowPairIdentities) ?? [:]
            try self.validate()
        }

        public func histories(accountKey: String?) -> [Series] {
            guard let accountKey else { return self.unscoped }
            return self.accounts[accountKey] ?? []
        }

        public mutating func record(_ samples: [Series], accountKey: String?, updatePreferred: Bool,
                                    identityTransition: IdentityTransition = .fixed) throws {
            try self.validate()
            if let accountKey, !Self.validKey(accountKey) { throw Failure.invalidData }
            var samples = samples.filter { !$0.entries.isEmpty }
            guard !samples.isEmpty else { return }
            var histories = self.histories(accountKey: accountKey)
            var replacement = self
            let identityKey = accountKey ?? "__codexbar_unscoped__"
            let previous = replacement.sessionEquivalentWindowPairIdentities[identityKey]
            let identity = PlanUtilizationHistoryCore.reconcile(identityTransition, previous: previous,
                histories: &histories, samples: &samples)
            replacement.sessionEquivalentWindowPairIdentities[identityKey] = identity
            let updated = try PlanUtilizationHistoryCore.merging(histories, samples: samples)
            if let accountKey {
                if updated.isEmpty { replacement.accounts.removeValue(forKey: accountKey) }
                else { replacement.accounts[accountKey] = updated }
            } else { replacement.unscoped = updated }
            if updatePreferred { replacement.preferredAccountKey = accountKey ?? "__unscoped__" }
            try replacement.validate()
            self = replacement
        }

        public func validate() throws {
            guard self.version == 1 else { throw Failure.unsupportedVersion }
            guard self.accounts.count <= 1024, self.sessionEquivalentWindowPairIdentities.count <= 1025 else {
                throw Failure.capacityExceeded
            }
            if let key = self.preferredAccountKey, !Self.validKey(key) { throw Failure.invalidData }
            for (key, identity) in self.sessionEquivalentWindowPairIdentities {
                guard Self.validKey(key), !identity.isEmpty, identity.utf8.count <= 8192,
                      !identity.contains("\0") else { throw Failure.invalidData }
            }
            try PlanUtilizationHistoryCore.validate(self.unscoped)
            for (key, histories) in self.accounts {
                guard Self.validKey(key) else { throw Failure.invalidData }
                try PlanUtilizationHistoryCore.validate(histories)
            }
        }

        private static func validKey(_ key: String) -> Bool {
            !key.isEmpty && key.utf8.count <= 512 && !key.contains("\0")
        }
    }

    /// Keeps the original five-hour/seven-day tolerance and two peaks across an hourly reset.
    public static func merging(_ existing: [Series], samples: [Series]) throws -> [Series] {
        try self.validate(existing)
        try self.validate(samples)
        struct Key: Hashable { let name: String; let minutes: Int }
        var grouped: [Key: [Entry]] = [:]
        for series in existing {
            let key = Key(name: series.name, minutes: self.canonicalMinutes(series.windowMinutes, name: series.name))
            if let previous = grouped[key] {
                grouped[key] = Array(Set(previous + series.entries)).sorted(by: self.ordered)
            } else {
                grouped[key] = series.entries.sorted(by: self.ordered)
            }
        }
        for series in samples {
            let key = Key(name: series.name, minutes: self.canonicalMinutes(series.windowMinutes, name: series.name))
            var entries = grouped[key] ?? []
            for sample in series.entries.sorted(by: self.ordered) {
                let sample = Entry(capturedAt: sample.capturedAt,
                    usedPercent: max(0, min(100, sample.usedPercent)), resetsAt: sample.resetsAt)
                let insertion = self.upperBound(entries, date: sample.capturedAt)
                let hour = floor(sample.capturedAt.timeIntervalSince1970 / 3600)
                var lower = insertion
                var upper = insertion
                while lower > 0, floor(entries[lower - 1].capturedAt.timeIntervalSince1970 / 3600) == hour { lower -= 1 }
                while upper < entries.count, floor(entries[upper].capturedAt.timeIntervalSince1970 / 3600) == hour { upper += 1 }
                let reduced = self.reduceHour(Array(entries[lower..<upper]) + [sample])
                entries.replaceSubrange(lower..<upper, with: reduced)
                if entries.count > self.maximumSamplesPerSeries {
                    entries.removeFirst(entries.count - self.maximumSamplesPerSeries)
                }
            }
            grouped[key] = entries
        }
        return grouped.map { key, entries in
            Series(name: key.name, windowMinutes: key.minutes, entries: Array(entries.suffix(self.maximumSamplesPerSeries)))
        }.sorted { lhs, rhs in
            lhs.windowMinutes == rhs.windowMinutes ? lhs.name < rhs.name : lhs.windowMinutes < rhs.windowMinutes
        }
    }

    private static func reconcile(_ transition: IdentityTransition, previous: String?,
                                  histories: inout [Series], samples: inout [Series]) -> String? {
        let unresolved = "__unresolved__"
        switch transition {
        case .fixed: return previous
        case .antigravityGemini:
            if samples.contains(where: { $0.name == "session" }), !histories.contains(where: { $0.name == "session" }) {
                histories.removeAll { $0.name == "weekly" }
            }
            return previous
        case let .genericResolved(session, weekly):
            let identity = self.pairIdentity(session: session, weekly: weekly)
            guard previous != identity else { return previous }
            if let components = previous.flatMap(self.pairComponents) {
                histories.removeAll {
                    ($0.name == "session" && components.session != session) ||
                        ($0.name == "weekly" && components.weekly != weekly)
                }
            } else if previous != nil {
                histories.removeAll { $0.name == "session" || $0.name == "weekly" }
            } else {
                histories.removeAll { $0.name == "session" }
            }
            return identity
        case let .genericIncomplete(weekly):
            let previous = previous ?? weekly.map { self.pairIdentity(session: unresolved, weekly: $0) }
            let components = previous.flatMap(self.pairComponents)
            if components?.session == unresolved, components?.weekly == weekly {
                samples.removeAll { $0.name == "session" }
            } else if previous != nil {
                samples.removeAll { $0.name == "session" || $0.name == "weekly" }
            }
            return previous
        case let .genericAmbiguous(weekly):
            let previous = previous ?? weekly.map { self.pairIdentity(session: unresolved, weekly: $0) }
            let previousWeekly = previous.flatMap(self.pairComponents)?.weekly
            samples.removeAll { sample in
                sample.name == "session" || (sample.name == "weekly" && previous != nil &&
                    (previousWeekly == nil || previousWeekly != weekly))
            }
            return previous
        }
    }

    private static func pairIdentity(session: String, weekly: String) -> String {
        "\(session.utf8.count)#\(session)\(weekly.utf8.count)#\(weekly)"
    }

    private static func pairComponents(_ identity: String) -> (session: String, weekly: String)? {
        let bytes = Array(identity.utf8)
        var offset = 0
        func component() -> String? {
            let start = offset
            while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
            guard offset > start, offset < bytes.count, bytes[offset] == 35,
                  let count = Int(String(decoding: bytes[start..<offset], as: UTF8.self)) else { return nil }
            offset += 1
            guard count <= bytes.count - offset else { return nil }
            let end = offset + count
            defer { offset = end }
            return String(bytes: bytes[offset..<end], encoding: .utf8)
        }
        guard let session = component(), let weekly = component(), offset == bytes.count else { return nil }
        return (session, weekly)
    }

    static func validate(_ series: [Series]) throws {
        guard series.count <= 128 else { throw Failure.capacityExceeded }
        for history in series {
            guard !history.name.isEmpty, history.name.utf8.count <= 128, !history.name.contains("\0"),
                  history.windowMinutes > 0 else { throw Failure.invalidData }
            guard history.entries.count <= self.maximumSamplesPerSeries else { throw Failure.capacityExceeded }
            for entry in history.entries {
                guard entry.capturedAt.timeIntervalSince1970.isFinite,
                      entry.usedPercent.isFinite,
                      entry.resetsAt?.timeIntervalSince1970.isFinite ?? true else { throw Failure.invalidData }
            }
        }
    }

    static func canonicalMinutes(_ minutes: Int, name: String) -> Int {
        if name == "session", (295...305).contains(minutes) { return 300 }
        if name == "weekly", (10070...10090).contains(minutes) { return 10080 }
        return minutes
    }

    private static func ordered(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt < rhs.capturedAt }
        if lhs.usedPercent != rhs.usedPercent { return lhs.usedPercent < rhs.usedPercent }
        return (lhs.resetsAt ?? .distantPast) < (rhs.resetsAt ?? .distantPast)
    }

    private static func upperBound(_ entries: [Entry], date: Date) -> Int {
        var lower = 0
        var upper = entries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if entries[middle].capturedAt > date { upper = middle }
            else { lower = middle + 1 }
        }
        return lower
    }

    private static func reduceHour(_ entries: [Entry]) -> [Entry] {
        let observations = entries.sorted(by: self.ordered)
        guard var peak = observations.first else { return [] }
        var beforeReset: Entry?
        for observation in observations.dropFirst() {
            if let previousReset = peak.resetsAt, let reset = observation.resetsAt,
               abs(previousReset.timeIntervalSince(reset)) >= 120 {
                if beforeReset == nil { beforeReset = peak }
                peak = observation
                continue
            }
            if peak.resetsAt == nil, observation.resetsAt != nil { peak = observation; continue }
            let later = observation.capturedAt >= peak.capturedAt
            let replace = observation.usedPercent > peak.usedPercent ||
                (observation.usedPercent == peak.usedPercent && later)
            let value = replace ? observation : peak
            let reset = later ? (observation.resetsAt ?? peak.resetsAt) : (peak.resetsAt ?? observation.resetsAt)
            peak = Entry(capturedAt: value.capturedAt, usedPercent: value.usedPercent, resetsAt: reset)
        }
        return beforeReset.map { [$0, peak] } ?? [peak]
    }
}
