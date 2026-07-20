import Foundation

/// Grok Build reasoning effort advertised in session model `_meta.reasoningEfforts`.
enum GrokBuildReasoningEffort: String, CaseIterable, Equatable, Sendable {
    case high
    case medium
    case low

    /// Product default when the user selects bare `grok-4.5`.
    static let defaultEffort: GrokBuildReasoningEffort = .high

    /// Menu / picker order: High → Medium → Low (matches Grok UI).
    static let displayOrder: [GrokBuildReasoningEffort] = [.high, .medium, .low]

    var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var sessionModeID: String { rawValue }

    static func parse(_ raw: String?) -> GrokBuildReasoningEffort? {
        let normalized = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return GrokBuildReasoningEffort(rawValue: normalized)
    }
}

/// Parses and encodes Grok Build model selections.
///
/// - Bare base id (`grok-4.5`) means default effort (high).
/// - Compound form (`grok-4.5:medium`) pins an explicit effort applied via `session/set_mode`.
struct GrokBuildModelSpecifier: Equatable, Sendable {
    let baseModel: String?
    let effort: GrokBuildReasoningEffort?

    init(raw: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            baseModel = nil
            effort = nil
            return
        }

        if trimmed.caseInsensitiveCompare(AgentModel.defaultModel.rawValue) == .orderedSame {
            baseModel = nil
            effort = nil
            return
        }

        if let colonIndex = trimmed.lastIndex(of: ":") {
            let prefix = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(trimmed[trimmed.index(after: colonIndex)...])
            if !prefix.isEmpty, let parsedEffort = GrokBuildReasoningEffort.parse(suffix) {
                baseModel = prefix.caseInsensitiveCompare(AgentModel.defaultModel.rawValue) == .orderedSame
                    ? nil
                    : prefix
                effort = parsedEffort
                return
            }
        }

        baseModel = trimmed
        effort = nil
    }

    init(baseModel: String?, effort: GrokBuildReasoningEffort?) {
        let trimmedBase = baseModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedBase, !trimmedBase.isEmpty,
           trimmedBase.caseInsensitiveCompare(AgentModel.defaultModel.rawValue) != .orderedSame
        {
            self.baseModel = trimmedBase
        } else {
            self.baseModel = nil
        }
        self.effort = effort
    }

    static func encodedRaw(baseModelRaw: String, effort: GrokBuildReasoningEffort) -> String {
        let trimmedBase = baseModelRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedBase.isEmpty ? AgentModel.grokBuildDefault.rawValue : trimmedBase
        return "\(base):\(effort.rawValue)"
    }

    /// Model id for `session/set_model` / launch `-m` (never includes effort).
    var runtimeModelID: String? {
        guard let baseModel = baseModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseModel.isEmpty,
              baseModel.caseInsensitiveCompare(AgentModel.defaultModel.rawValue) != .orderedSame
        else {
            return nil
        }
        return baseModel
    }

    /// Mode id for `session/set_mode`. Bare base selection uses default high.
    var sessionModeIDToApply: String? {
        (effort ?? (baseModel == nil ? nil : GrokBuildReasoningEffort.defaultEffort))?.sessionModeID
    }

    var displaySuffix: String? {
        effort.map(\.displayName)
    }
}
