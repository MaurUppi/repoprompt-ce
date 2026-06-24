import Foundation

actor WorkspaceRootReusableSnapshotCoordinator {
    typealias CurrentnessValidator = @Sendable () async -> Bool

    enum ObservationResult: Equatable {
        case admitted(WorkspaceRootReusableSnapshotIdentity)
        case nonGit
        case unsupportedRoot
        case authorityUnavailable(GitWorkspaceAuthorityUnavailableReason)
        case catalogMismatch
        case failed
    }

    static let shared = WorkspaceRootReusableSnapshotCoordinator()

    private let gitService: GitService
    private let authority: GitWorkspaceStateAuthority
    #if DEBUG
        private var preparedAdmissionHandlerForTesting: (@Sendable () async -> Void)?
    #endif

    init(
        gitService: GitService = GitService(),
        authority: GitWorkspaceStateAuthority = .shared
    ) {
        self.gitService = gitService
        self.authority = authority
    }

    func observeAuthoritativeFullLoad(
        rootURL: URL,
        authoritativeRelativeFilePaths: Set<String>,
        currentnessValidator: @escaping CurrentnessValidator = { true }
    ) async -> ObservationResult {
        guard await currentnessValidator(), !Task.isCancelled else { return .failed }
        guard let layout = Self.gitLayoutContaining(rootURL) else { return .nonGit }
        guard let prefix = try? Self.rootPrefix(rootURL: rootURL, layout: layout) else {
            return .unsupportedRoot
        }

        var discoveryObservation: GitWorkspaceMetadataMonitor.RetainToken?
        var replacementObservation: GitWorkspaceMetadataMonitor.RetainToken?
        do {
            // The base observation stays live until replacement coverage has been
            // installed. A policy-path change during either collection advances
            // the shared watermark and prevents conditional admission.
            let discoveryToken = try await authority.retainMetadataObservation(for: layout)
            discoveryObservation = discoveryToken
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(discoveryToken)
                return .failed
            }
            let discovery = try await gitService.workspaceAuthoritySnapshot(in: layout, prefix: prefix)
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(discoveryToken)
                return .failed
            }
            let discoveredExternalPaths = Self.canonicalPathSet(
                discovery.metadata.resolvedExternalAuthorityPaths
            )

            let observation = try await authority.retainMetadataObservation(
                for: layout,
                additionalAuthorityPaths: discovery.metadata.resolvedExternalAuthorityPaths
            )
            replacementObservation = observation
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(observation)
                await authority.releaseMetadataObservation(discoveryToken)
                return .failed
            }
            await authority.releaseMetadataObservation(discoveryToken)
            discoveryObservation = nil
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(observation)
                return .failed
            }

            let scope = GitWorkspaceAuthorityScopeKey(
                repositoryKey: GitWorkspaceAuthorityRepositoryKey(layout: layout),
                repositoryRelativeRootPrefix: prefix
            )
            let captureToken: GitWorkspaceAuthorityCaptureToken
            switch await authority.beginCollection(scopeKey: scope) {
            case let .success(token):
                captureToken = token
            case let .failure(reason):
                await authority.releaseMetadataObservation(observation)
                return .authorityUnavailable(reason)
            }
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(observation)
                return .failed
            }

            let captured = try await gitService.workspaceAuthoritySnapshot(in: layout, prefix: prefix)
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(observation)
                return .failed
            }
            guard Self.canonicalPathSet(captured.metadata.resolvedExternalAuthorityPaths) == discoveredExternalPaths else {
                await authority.releaseMetadataObservation(observation)
                return .authorityUnavailable(.invalidatedDuringCollection)
            }
            let observationIsCurrent = await authority.metadataObservationIsCurrent(
                observation,
                for: layout,
                additionalAuthorityPaths: captured.metadata.resolvedExternalAuthorityPaths,
                expectedAcceptedWatermark: captureToken.acceptedMetadataWatermark
            )
            guard observationIsCurrent,
                  await currentnessValidator(),
                  !Task.isCancelled
            else {
                await authority.releaseMetadataObservation(observation)
                return .authorityUnavailable(.invalidatedDuringCollection)
            }
            let tree = try await gitService.listTree(
                captured.snapshot.treeOID,
                in: layout,
                prefix: prefix
            )
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(observation)
                return .failed
            }
            let lease: GitWorkspaceAuthorityLease
            switch await authority.install(captured.snapshot, capturedUsing: captureToken) {
            case let .success(installed):
                lease = installed
            case let .failure(reason):
                await authority.releaseMetadataObservation(observation)
                return .authorityUnavailable(reason)
            }
            guard await currentnessValidator(), !Task.isCancelled else {
                await authority.releaseMetadataObservation(observation)
                return .failed
            }
            guard let snapshot = WorkspaceRootReusableSnapshot.make(
                authority: captured.snapshot,
                tree: tree,
                authoritativeRelativeFilePaths: authoritativeRelativeFilePaths
            ) else {
                await authority.releaseMetadataObservation(observation)
                return .catalogMismatch
            }
            guard let prepared = await authority.prepareReusableSnapshotAdmission(
                snapshot,
                capturedUsing: lease,
                observationToken: observation
            ) else {
                replacementObservation = nil
                return .failed
            }
            replacementObservation = nil
            #if DEBUG
                if let preparedAdmissionHandlerForTesting {
                    await preparedAdmissionHandlerForTesting()
                }
            #endif
            guard await currentnessValidator(),
                  !Task.isCancelled,
                  await authority.preparedReusableSnapshotAdmissionIsCurrent(prepared),
                  await currentnessValidator(),
                  !Task.isCancelled
            else {
                await authority.cancelPreparedReusableSnapshotAdmission(prepared)
                return .failed
            }
            guard let receipt = await authority.admitPreparedReusableSnapshot(prepared) else {
                return .failed
            }
            guard await currentnessValidator(),
                  !Task.isCancelled,
                  await authority.reusableSnapshotAdmissionIsCurrent(receipt),
                  await currentnessValidator(),
                  !Task.isCancelled
            else {
                await authority.revokeReusableSnapshotAdmission(receipt)
                return .failed
            }
            return .admitted(receipt.snapshotIdentity)
        } catch {
            if let discoveryObservation {
                await authority.releaseMetadataObservation(discoveryObservation)
            }
            if let replacementObservation {
                await authority.releaseMetadataObservation(replacementObservation)
            }
            return .failed
        }
    }

    #if DEBUG
        func setPreparedAdmissionHandlerForTesting(
            _ handler: (@Sendable () async -> Void)?
        ) {
            preparedAdmissionHandlerForTesting = handler
        }
    #endif

    private nonisolated static func canonicalPathSet(_ paths: [URL]) -> Set<String> {
        Set(paths.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    }

    private nonisolated static func gitLayoutContaining(_ rootURL: URL) -> GitRepositoryLayout? {
        var candidate = rootURL.standardizedFileURL
        while true {
            if let layout = GitRepositoryLayoutResolver.resolve(atWorkTreeRoot: candidate) {
                return layout
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }

    private nonisolated static func rootPrefix(
        rootURL: URL,
        layout: GitRepositoryLayout
    ) throws -> GitRepositoryRelativeRootPrefix {
        let rootPath = rootURL.standardizedFileURL.path
        let worktreePath = layout.workTreeRoot.standardizedFileURL.path
        guard rootPath == worktreePath || rootPath.hasPrefix(worktreePath + "/") else {
            throw GitWorktreeInitializationError.invalidRootPrefix
        }
        let relative = rootPath == worktreePath
            ? ""
            : String(rootPath.dropFirst(worktreePath.count + 1))
        return try GitRepositoryRelativeRootPrefix(relative)
    }
}
