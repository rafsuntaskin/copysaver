import Foundation

public enum HistoryFailure: Error, Equatable, Sendable {
    case historyLimitReached, pinnedLimitConflict, snippetLimitReached, storageCapacity, confirmationRequired
}

public struct ClipboardSample: Sendable {
    public let text: String
    public let date: Date
    public let sourceBundleID: String?
    public let sourceName: String?
    public init(text: String, date: Date, sourceBundleID: String? = nil, sourceName: String? = nil) {
        self.text = text; self.date = date; self.sourceBundleID = sourceBundleID; self.sourceName = sourceName
    }
}

public enum HistoryPolicy {
    public static func settings(in records: [VaultRecord]) throws -> VaultSettings {
        let values = records.compactMap { record -> VaultSettings? in
            if case .settings(let value) = record.payload { return value }; return nil
        }
        guard values.count <= 1 else { throw RecordValidationError.invalidSettings }
        return try values.first ?? VaultSettings()
    }

    public static func capture(_ sample: ClipboardSample, in records: [VaultRecord], budget: Int) throws -> [VaultRecord] {
        let settings = try settings(in: records)
        var result = try retain(records, settings: settings, now: sample.date)
        let duplicate = result.first { if case .history(let item) = $0.payload { return item.text.utf8.elementsEqual(sample.text.utf8) }; return false }
        let old: HistoryItem?
        if case .history(let item) = duplicate?.payload { old = item } else { old = nil }
        let item = try HistoryItem(
            id: old?.id ?? UUID(), text: sample.text,
            firstSeenAt: old?.firstSeenAt ?? sample.date, lastSeenAt: max(old?.lastSeenAt ?? sample.date, sample.date),
            lastCopiedAt: old?.lastCopiedAt, repeatCount: min(old?.repeatCount ?? 0, Int.max - 1) + 1,
            sourceBundleID: sample.sourceBundleID, sourceName: sample.sourceName, isPinned: old?.isPinned ?? false
        )
        result.removeAll { $0.id == item.id }
        if old == nil, result.filter({ if case .history(let value) = $0.payload { return value.isPinned }; return false }).count >= settings.historyCountLimit {
            throw HistoryFailure.historyLimitReached
        }
        result.append(try VaultRecord(.history(item)))
        return try fit(result, settings: settings, budget: budget, protecting: item.id)
    }

    public static func retain(_ records: [VaultRecord], settings: VaultSettings, now: Date) throws -> [VaultRecord] {
        try settings.validate()
        let cutoff = now.addingTimeInterval(-Double(settings.retentionDays) * 86_400)
        let result = records.filter { if case .history(let item) = $0.payload { return item.isPinned || item.lastSeenAt >= cutoff }; return true }
        return try fit(result, settings: settings, budget: Int.max)
    }

    public static func fit(_ records: [VaultRecord], settings: VaultSettings, budget: Int, protecting: UUID? = nil) throws -> [VaultRecord] {
        let history = records.compactMap { record -> HistoryItem? in if case .history(let value) = record.payload { return value }; return nil }
        guard history.filter(\.isPinned).count <= settings.historyCountLimit else { throw HistoryFailure.pinnedLimitConflict }
        guard records.filter({ if case .snippet = $0.payload { return true }; return false }).count <= 2_000 else { throw HistoryFailure.snippetLimitReached }
        var count = history.count
        var bytes = try records.reduce(0) { try $0 + RecordCodec.encode($1).count + 28 }
        var removed = Set<UUID>()
        let candidates = history.filter { !$0.isPinned && $0.id != protecting }.sorted {
            $0.lastSeenAt == $1.lastSeenAt ? $0.id.uuidString < $1.id.uuidString : $0.lastSeenAt < $1.lastSeenAt
        }
        for item in candidates where count > settings.historyCountLimit || bytes > budget {
            removed.insert(item.id); count -= 1
            bytes -= try RecordCodec.encode(VaultRecord(.history(item))).count + 28
        }
        guard count <= settings.historyCountLimit else { throw HistoryFailure.historyLimitReached }
        guard bytes <= budget else { throw HistoryFailure.storageCapacity }
        return records.filter { !removed.contains($0.id) }
    }
}

public extension VaultSettings {
    func updating(captureEnabled: Bool? = nil, manuallyPaused: Bool? = nil, historyCountLimit: Int? = nil, retentionDays: Int? = nil, excludedBundleIDs: Set<String>? = nil, idleLockTimeout: IdleLockTimeout? = nil) throws -> VaultSettings {
        try VaultSettings(id: id, captureEnabled: captureEnabled ?? self.captureEnabled, manuallyPaused: manuallyPaused ?? self.manuallyPaused,
                          historyCountLimit: historyCountLimit ?? self.historyCountLimit, retentionDays: retentionDays ?? self.retentionDays,
                          excludedBundleIDs: excludedBundleIDs ?? self.excludedBundleIDs, idleLockTimeout: idleLockTimeout ?? self.idleLockTimeout)
    }
}
