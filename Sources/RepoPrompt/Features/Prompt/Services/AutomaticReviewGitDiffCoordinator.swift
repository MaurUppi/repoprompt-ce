import Foundation

struct AutomaticReviewGitDiffRequest: Equatable {
    let pathResolution: WorkspaceSelectedGitPathResolution
    let compareIntent: ReviewGitCompareIntent
    let displayContext: ReviewGitDisplayContext
}

struct AutomaticReviewGitDiffResult: Equatable {
    enum Completeness: Equatable {
        case complete
        case partial
        case failed
        case cancelled
    }

    let text: String?
    let completeness: Completeness
    let outcomes: [ReviewGitCheckoutOutcome]
    let pathIssues: [ReviewGitPathIssue]
}

struct ReviewGitCheckout: Equatable {
    let checkoutRootPath: String
    let displayLabel: String
    let selectedPaths: [String]
}

enum ReviewGitCheckoutOutcome: Equatable {
    case diff(checkout: ReviewGitCheckout, text: String)
    case noChanges(checkout: ReviewGitCheckout)
    case baseResolutionFailed(checkout: ReviewGitCheckout, summary: String)
    case commandFailed(checkout: ReviewGitCheckout, summary: String)

    var checkout: ReviewGitCheckout {
        switch self {
        case let .diff(checkout, _),
             let .noChanges(checkout),
             let .baseResolutionFailed(checkout, _),
             let .commandFailed(checkout, _):
            checkout
        }
    }

    var isSuccessful: Bool {
        switch self {
        case .diff, .noChanges:
            true
        case .baseResolutionFailed, .commandFailed:
            false
        }
    }
}

enum ReviewGitPathIssue: Equatable {
    case unresolvedSelection(displayPath: String)
    case noRepository(displayPath: String)
    case unsupportedBackend(displayPath: String, backendKind: VCSBackendKind)
    case invalidGitLayout(displayPath: String)
}

/// Builds selected-file review diffs without consulting mutable Git UI state.
///
/// The coordinator resolves the nearest owning checkout for every frozen physical path, keeps
/// linked worktrees distinct by checkout root, freezes commit boundaries before diff execution,
/// and returns explicit partial-failure state rather than a plausible truncated diff.
struct AutomaticReviewGitDiffCoordinator {
    struct Dependencies {
        var resolveRepo: @Sendable (URL) async -> VCSResolvedRepo?
        var resolveLayout: @Sendable (URL) -> GitRepositoryLayout?
        var resolveHead: @Sendable (URL) async throws -> String
        var resolveRef: @Sendable (String, URL) async throws -> String
        var mergeBase: @Sendable (_ headID: String, _ baseID: String, _ repoURL: URL) async throws -> String
        var buildDiff: @Sendable (_ compare: GitDiffCompareSpec, _ paths: [String], _ repoURL: URL) async throws -> String?

        static func live(
            vcsService: VCSService = .shared,
            gitService: GitService = GitService(),
            diffEngine: GitDiffEngine? = nil
        ) -> Dependencies {
            let engine = diffEngine ?? GitDiffEngine(vcsService: vcsService, gitService: gitService)
            return Dependencies(
                resolveRepo: { url in
                    await vcsService.resolveRepo(from: url)
                },
                resolveLayout: { rootURL in
                    GitRepositoryLayoutResolver.resolve(atWorkTreeRoot: rootURL)
                },
                resolveHead: { rootURL in
                    let backend = await vcsService.backend(for: .git)
                    return try await backend.getHeadID(at: rootURL)
                },
                resolveRef: { ref, rootURL in
                    let backend = await vcsService.backend(for: .git)
                    return try await backend.getRefID(ref: ref, at: rootURL)
                },
                mergeBase: { headID, baseID, rootURL in
                    try await gitService.getMergeBase(sourceHead: headID, targetHead: baseID, at: rootURL)
                },
                buildDiff: { compare, paths, rootURL in
                    let result = try await engine.buildSnapshotInputs(
                        compare: compare,
                        pathspecs: paths,
                        repoURL: rootURL,
                        contextLines: 3,
                        detectRenames: false,
                        generateDiffText: true
                    )
                    return result.diffText
                }
            )
        }
    }

    private struct CheckoutGroup {
        let rootPath: String
        let baseDisplayLabel: String
        var selectedPaths: [String]
    }

    private enum FrozenCheckoutPlan {
        case ready(checkout: ReviewGitCheckout, compare: GitDiffCompareSpec)
        case baseFailure(checkout: ReviewGitCheckout, summary: String)
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies = .live()) {
        self.dependencies = dependencies
    }

    func resolve(_ request: AutomaticReviewGitDiffRequest) async -> AutomaticReviewGitDiffResult {
        do {
            return try await resolveCheckingCancellation(request)
        } catch is CancellationError {
            return AutomaticReviewGitDiffResult(
                text: nil,
                completeness: .cancelled,
                outcomes: [],
                pathIssues: []
            )
        } catch {
            // All operational failures are handled per checkout. This is a defensive fail-closed
            // result for an unexpected cancellation-compatible error path.
            return AutomaticReviewGitDiffResult(
                text: incompleteDiagnostics(
                    outcomes: [],
                    pathIssues: [.unresolvedSelection(displayPath: "Selected files")]
                ),
                completeness: .failed,
                outcomes: [],
                pathIssues: [.unresolvedSelection(displayPath: "Selected files")]
            )
        }
    }

    private func resolveCheckingCancellation(
        _ request: AutomaticReviewGitDiffRequest
    ) async throws -> AutomaticReviewGitDiffResult {
        try Task.checkCancellation()

        var pathIssues = request.pathResolution.unresolvedCandidates.enumerated().map { index, path in
            ReviewGitPathIssue.unresolvedSelection(
                displayPath: request.displayContext.displayPath(for: path, fallbackIndex: index + 1)
            )
        }
        var groupedPaths: [String: CheckoutGroup] = [:]
        var seenPaths = Set<String>()

        for (index, rawPath) in request.pathResolution.paths.enumerated() {
            try Task.checkCancellation()
            let physicalPath = StandardizedPath.absolute((rawPath as NSString).expandingTildeInPath)
            guard seenPaths.insert(physicalPath).inserted else { continue }

            let displayPath = request.displayContext.displayPath(for: physicalPath, fallbackIndex: index + 1)
            let pathURL = URL(fileURLWithPath: physicalPath)
            let resolvedOwner = await dependencies.resolveRepo(pathURL)
            try Task.checkCancellation()
            guard let resolved = resolvedOwner else {
                pathIssues.append(.noRepository(displayPath: displayPath))
                continue
            }
            guard resolved.backendKind == .git else {
                pathIssues.append(.unsupportedBackend(displayPath: displayPath, backendKind: resolved.backendKind))
                continue
            }

            let resolvedRoot = resolved.rootURL.standardizedFileURL
            guard let layout = dependencies.resolveLayout(resolvedRoot) else {
                pathIssues.append(.invalidGitLayout(displayPath: displayPath))
                continue
            }

            let checkoutRoot = layout.workTreeRoot.standardizedFileURL.path
            guard resolvedRoot.path == checkoutRoot,
                  StandardizedPath.isDescendant(physicalPath, of: checkoutRoot),
                  physicalPath != checkoutRoot
            else {
                pathIssues.append(.invalidGitLayout(displayPath: displayPath))
                continue
            }

            if var group = groupedPaths[checkoutRoot] {
                group.selectedPaths.append(physicalPath)
                groupedPaths[checkoutRoot] = group
            } else {
                groupedPaths[checkoutRoot] = CheckoutGroup(
                    rootPath: checkoutRoot,
                    baseDisplayLabel: request.displayContext.checkoutLabel(for: checkoutRoot),
                    selectedPaths: [physicalPath]
                )
            }
        }

        let checkouts = makeDeterministicCheckouts(from: Array(groupedPaths.values))
        var frozenPlans: [FrozenCheckoutPlan] = []
        frozenPlans.reserveCapacity(checkouts.count)

        // Resolve every immutable boundary before executing any working-tree diff.
        for checkout in checkouts {
            try Task.checkCancellation()
            let rootURL = URL(fileURLWithPath: checkout.checkoutRootPath, isDirectory: true)
            do {
                let headID = try await dependencies.resolveHead(rootURL)
                try Task.checkCancellation()
                let compare: GitDiffCompareSpec
                switch request.compareIntent {
                case .uncommittedHEAD:
                    compare = .uncommitted(base: headID)
                case let .uncommittedMergeBase(symbolicBase):
                    let baseID = try await dependencies.resolveRef(symbolicBase, rootURL)
                    try Task.checkCancellation()
                    let mergeBaseID = try await dependencies.mergeBase(headID, baseID, rootURL)
                    try Task.checkCancellation()
                    compare = .uncommitted(base: mergeBaseID)
                }
                frozenPlans.append(.ready(checkout: checkout, compare: compare))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                frozenPlans.append(.baseFailure(
                    checkout: checkout,
                    summary: "Comparison base resolution failed."
                ))
            }
        }

        var outcomes: [ReviewGitCheckoutOutcome] = []
        outcomes.reserveCapacity(frozenPlans.count)

        for plan in frozenPlans {
            try Task.checkCancellation()
            switch plan {
            case let .baseFailure(checkout, summary):
                outcomes.append(.baseResolutionFailed(checkout: checkout, summary: summary))
            case let .ready(checkout, compare):
                let rootURL = URL(fileURLWithPath: checkout.checkoutRootPath, isDirectory: true)
                do {
                    let text = try await dependencies.buildDiff(compare, checkout.selectedPaths, rootURL)
                    try Task.checkCancellation()
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        outcomes.append(.diff(checkout: checkout, text: text))
                    } else {
                        outcomes.append(.noChanges(checkout: checkout))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    outcomes.append(.commandFailed(
                        checkout: checkout,
                        summary: "Git diff generation failed."
                    ))
                }
            }
        }

        try Task.checkCancellation()

        let hasFailures = !pathIssues.isEmpty || outcomes.contains { !$0.isSuccessful }
        let hasSuccessfulCheckout = outcomes.contains { $0.isSuccessful }

        let completeness: AutomaticReviewGitDiffResult.Completeness = if !hasFailures {
            .complete
        } else if hasSuccessfulCheckout {
            .partial
        } else {
            .failed
        }

        return AutomaticReviewGitDiffResult(
            text: renderText(outcomes: outcomes, pathIssues: pathIssues, completeness: completeness),
            completeness: completeness,
            outcomes: outcomes,
            pathIssues: pathIssues
        )
    }

    private func makeDeterministicCheckouts(from groups: [CheckoutGroup]) -> [ReviewGitCheckout] {
        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.baseDisplayLabel != rhs.baseDisplayLabel {
                return lhs.baseDisplayLabel < rhs.baseDisplayLabel
            }
            return lhs.rootPath < rhs.rootPath
        }
        let labelCounts = Dictionary(grouping: sortedGroups, by: \.baseDisplayLabel).mapValues(\.count)
        var labelOrdinals: [String: Int] = [:]

        return sortedGroups.map { group in
            let ordinal = labelOrdinals[group.baseDisplayLabel, default: 0] + 1
            labelOrdinals[group.baseDisplayLabel] = ordinal
            let displayLabel: String = if labelCounts[group.baseDisplayLabel, default: 0] > 1 {
                "\(group.baseDisplayLabel) [\(ordinal)]"
            } else {
                group.baseDisplayLabel
            }
            let paths = Array(Set(group.selectedPaths)).sorted {
                relativePath($0, under: group.rootPath) < relativePath($1, under: group.rootPath)
            }
            return ReviewGitCheckout(
                checkoutRootPath: group.rootPath,
                displayLabel: displayLabel,
                selectedPaths: paths
            )
        }
    }

    private func renderText(
        outcomes: [ReviewGitCheckoutOutcome],
        pathIssues: [ReviewGitPathIssue],
        completeness: AutomaticReviewGitDiffResult.Completeness
    ) -> String? {
        let diffs = outcomes.compactMap { outcome -> (ReviewGitCheckout, String)? in
            guard case let .diff(checkout, text) = outcome else { return nil }
            return (checkout, text)
        }

        if completeness == .complete,
           outcomes.count == 1,
           let onlyDiff = diffs.first
        {
            return onlyDiff.1
        }

        var sections = diffs.map { checkout, text in
            let body = text.trimmingCharacters(in: .newlines)
            return """
            ===== BEGIN REPOPROMPT CHECKOUT DIFF: \(checkout.displayLabel) =====
            \(body)
            ===== END REPOPROMPT CHECKOUT DIFF: \(checkout.displayLabel) =====
            """
        }

        if completeness == .partial || completeness == .failed {
            sections.append(incompleteDiagnostics(outcomes: outcomes, pathIssues: pathIssues))
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func incompleteDiagnostics(
        outcomes: [ReviewGitCheckoutOutcome],
        pathIssues: [ReviewGitPathIssue]
    ) -> String {
        var lines = ["===== REPOPROMPT REVIEW DIFF INCOMPLETE ====="]

        for issue in pathIssues {
            switch issue {
            case let .unresolvedSelection(displayPath):
                lines.append("- Selected path could not be resolved: \(displayPath)")
            case let .noRepository(displayPath):
                lines.append("- No owning repository: \(displayPath)")
            case let .unsupportedBackend(displayPath, backendKind):
                lines.append("- Unsupported repository backend (\(backendKind.rawValue)): \(displayPath)")
            case let .invalidGitLayout(displayPath):
                lines.append("- Invalid Git checkout layout: \(displayPath)")
            }
        }

        for outcome in outcomes {
            switch outcome {
            case let .baseResolutionFailed(checkout, _):
                lines.append("- Comparison base could not be resolved for checkout: \(checkout.displayLabel)")
            case let .commandFailed(checkout, _):
                lines.append("- Git diff command failed for checkout: \(checkout.displayLabel)")
            case .diff, .noChanges:
                break
            }
        }

        lines.append("===== END REPOPROMPT REVIEW DIFF INCOMPLETE =====")
        return lines.joined(separator: "\n")
    }

    private func relativePath(_ path: String, under rootPath: String) -> String {
        guard path != rootPath, path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

private extension ReviewGitDisplayContext {
    func checkoutLabel(for checkoutRootPath: String) -> String {
        guard let root = longestMatchingRoot(for: checkoutRootPath) else {
            return "Checkout"
        }
        let relative = relativePath(checkoutRootPath, under: root.physicalRootPath)
        let base = sanitizedLabel(root.logicalRootName, fallback: "Workspace")
        guard !relative.isEmpty else { return base }
        return "\(base)/\(relative)"
    }

    func displayPath(for path: String, fallbackIndex: Int) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return sanitizedLabel(trimmed, fallback: "Selected path \(fallbackIndex)")
        }
        let standardized = StandardizedPath.absolute(trimmed)
        guard let root = longestMatchingRoot(for: standardized) else {
            return "Selected path \(fallbackIndex)"
        }
        let base = sanitizedLabel(root.logicalRootName, fallback: "Workspace")
        let relative = relativePath(standardized, under: root.physicalRootPath)
        return relative.isEmpty ? base : "\(base)/\(relative)"
    }

    private func longestMatchingRoot(for path: String) -> ReviewGitDisplayRoot? {
        let standardized = StandardizedPath.absolute(path)
        return roots
            .filter { StandardizedPath.isDescendant(standardized, of: $0.physicalRootPath) }
            .max { $0.physicalRootPath.count < $1.physicalRootPath.count }
    }

    private func relativePath(_ path: String, under rootPath: String) -> String {
        guard path != rootPath, path.hasPrefix(rootPath + "/") else { return "" }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func sanitizedLabel(_ label: String, fallback: String) -> String {
        let collapsed = label
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? fallback : collapsed
    }
}
