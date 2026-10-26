import Foundation

public enum RecordLimits {
    public static let maximumTextBytes = 256 * 1_024
    public static let maximumNameCharacters = 120
    public static let maximumCategoryCharacters = 60
    public static let maximumPayloadBytes = 128 * 1_024 * 1_024
}

/// Deliberately carries no user content in error descriptions.
public enum RecordValidationError: Error, Equatable, Sendable {
    case emptyText
    case textTooLarge
    case invalidName
    case invalidCategory
    case invalidTimestamp
    case invalidRepeatCount
    case invalidSettings
    case unsupportedRecordVersion
    case invalidVerification
}

enum Validation {
    static func text(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordValidationError.emptyText
        }
        guard value.utf8.count <= RecordLimits.maximumTextBytes else {
            throw RecordValidationError.textTooLarge
        }
    }

    static func name(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= RecordLimits.maximumNameCharacters else {
            throw RecordValidationError.invalidName
        }
        return result
    }

    static func category(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.count <= RecordLimits.maximumCategoryCharacters else {
            throw RecordValidationError.invalidCategory
        }
        return result.isEmpty ? nil : result
    }

    static func dates(_ values: Date?...) throws {
        guard values.compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
            throw RecordValidationError.invalidTimestamp
        }
    }
}
