import Foundation

struct SelectedGitArtifactAuthorizationRequest {
    let physicalSelection: StoredSelection
    let capability: SelectedGitArtifactCapability
    let store: WorkspaceFileContextStore
}

struct SelectedGitArtifactAuthorizationResult {
    let entries: [ResolvedPromptFileEntry]
    let consumedSelectionPaths: Set<String>
    let dispositions: [SelectedGitArtifactDisposition]
}

enum SelectedGitArtifactKind: String, Equatable {
    case map
    case patch
}

enum SelectedGitArtifactReadability: Equatable {
    case readable
    case empty
}

enum SelectedGitArtifactRejectionReason: Equatable {
    case invalidAbsolutePath
    case outsideWorkspaceGitData
    case capabilityRootUnavailable
    case notCataloged
    case unsupportedArtifactPath
    case manifestNotCataloged
    case manifestUnreadable
    case manifestInvalid
    case manifestIdentityMismatch
    case tabMismatch
    case legacyTabNotAllowed
    case repositoryProvenanceMissing
    case checkoutProvenanceMismatch
    case unlistedPatch
    case contentUnreadable
}

enum SelectedGitArtifactDisposition: Equatable {
    case authorized(
        path: String,
        kind: SelectedGitArtifactKind,
        readability: SelectedGitArtifactReadability
    )
    case rejected(path: String, reason: SelectedGitArtifactRejectionReason)
}

/// Authorizes only already-selected, already-cataloged artifacts under one frozen Git-data root.
///
/// This service never broadens the caller's workspace scope and never falls back to raw filesystem
/// reads. MAP.txt is returned as an ordinary full-file entry; patch identity remains explicit.
struct SelectedGitDiffArtifactAuthorizationService {
    private enum Candidate {
        case map(snapshotRef: GitDiffSnapshotStore.GitDiffSnapshotRef)
        case patch(snapshotRef: GitDiffSnapshotStore.GitDiffSnapshotRef, relativePath: String)

        var snapshotRef: GitDiffSnapshotStore.GitDiffSnapshotRef {
            switch self {
            case let .map(snapshotRef), let .patch(snapshotRef, _):
                snapshotRef
            }
        }

        var kind: SelectedGitArtifactKind {
            switch self {
            case .map:
                .map
            case .patch:
                .patch
            }
        }
    }

    private enum CheckoutAuthorization: Equatable {
        case bound
        case unbound
    }

    private let vcsService: VCSService
    private let snapshotStore = GitDiffSnapshotStore()

    init(vcsService: VCSService = .shared) {
        self.vcsService = vcsService
    }

    func authorize(
        _ request: SelectedGitArtifactAuthorizationRequest
    ) async -> SelectedGitArtifactAuthorizationResult {
        var entries: [ResolvedPromptFileEntry] = []
        var consumedPaths = Set<String>()
        var dispositions: [SelectedGitArtifactDisposition] = []
        var seenPaths = Set<String>()

        let capability = request.capability
        let expectedGitDataPath = StandardizedPath.join(
            standardizedRoot: capability.workspaceDirectoryPath,
            standardizedRelativePath: "_git_data"
        )
        let currentGitDataRoot = await request.store.exactRootRef(
            path: capability.gitDataRoot.standardizedFullPath,
            kind: .workspaceGitData
        )
        let capabilityRootIsCurrent =
            capability.gitDataRoot.standardizedFullPath == expectedGitDataPath &&
            currentGitDataRoot == capability.gitDataRoot

        for rawPath in selectedArtifactCandidates(from: request.physicalSelection) {
            guard let path = exactAbsolutePath(rawPath) else {
                if rawPath.hasPrefix(capability.gitDataRoot.standardizedFullPath + "/") {
                    consumedPaths.insert(rawPath)
                    dispositions.append(.rejected(path: rawPath, reason: .invalidAbsolutePath))
                }
                continue
            }
            guard seenPaths.insert(path).inserted else { continue }

            guard StandardizedPath.isDescendant(path, of: capability.gitDataRoot.standardizedFullPath) else {
                continue
            }
            consumedPaths.insert(rawPath)

            guard capabilityRootIsCurrent else {
                dispositions.append(.rejected(path: path, reason: .capabilityRootUnavailable))
                continue
            }
            guard let file = await request.store.exactCatalogFile(
                absolutePath: path,
                expectedRoot: capability.gitDataRoot,
                expectedKind: .workspaceGitData
            ) else {
                dispositions.append(.rejected(path: path, reason: .notCataloged))
                continue
            }
            guard let candidate = candidate(
                for: path,
                gitDataRootPath: capability.gitDataRoot.standardizedFullPath
            ) else {
                dispositions.append(.rejected(path: path, reason: .unsupportedArtifactPath))
                continue
            }

            let manifestPath = StandardizedPath.join(
                standardizedRoot: capability.gitDataRoot.standardizedFullPath,
                standardizedRelativePath: candidate.snapshotRef.snapshotDirRel + "/manifest.json"
            )
            guard let manifestFile = await request.store.exactCatalogFile(
                absolutePath: manifestPath,
                expectedRoot: capability.gitDataRoot,
                expectedKind: .workspaceGitData
            ) else {
                dispositions.append(.rejected(path: path, reason: .manifestNotCataloged))
                continue
            }
            guard let manifestContent = await request.store.readExactCatalogFile(
                manifestFile,
                expectedRoot: capability.gitDataRoot
            ) else {
                dispositions.append(.rejected(path: path, reason: .manifestUnreadable))
                continue
            }
            guard let manifest = decodeManifest(manifestContent) else {
                dispositions.append(.rejected(path: path, reason: .manifestInvalid))
                continue
            }
            guard manifestMatches(candidate.snapshotRef, manifest: manifest) else {
                dispositions.append(.rejected(path: path, reason: .manifestIdentityMismatch))
                continue
            }
            guard let checkoutAuthorization = await authorizeCheckout(
                manifest: manifest,
                capability: capability
            ) else {
                let reason: SelectedGitArtifactRejectionReason =
                    manifest.repoRoot == nil ? .repositoryProvenanceMissing : .checkoutProvenanceMismatch
                dispositions.append(.rejected(path: path, reason: reason))
                continue
            }

            if let manifestTabID = manifest.tabID {
                guard manifestTabID == capability.creatorTabID else {
                    dispositions.append(.rejected(path: path, reason: .tabMismatch))
                    continue
                }
            } else if checkoutAuthorization == .bound {
                dispositions.append(.rejected(path: path, reason: .legacyTabNotAllowed))
                continue
            }

            guard isWhitelisted(candidate, manifest: manifest) else {
                let reason: SelectedGitArtifactRejectionReason =
                    candidate.kind == .patch ? .unlistedPatch : .unsupportedArtifactPath
                dispositions.append(.rejected(path: path, reason: reason))
                continue
            }
            guard let content = await request.store.readExactCatalogFile(
                file,
                expectedRoot: capability.gitDataRoot
            ) else {
                dispositions.append(.rejected(path: path, reason: .contentUnreadable))
                continue
            }

            let readability: SelectedGitArtifactReadability =
                candidate.kind == .patch && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .empty
                    : .readable
            entries.append(
                ResolvedPromptFileEntry(
                    file: file,
                    isCodemap: false,
                    mode: .fullFile,
                    loadedContent: content,
                    rootFolderPath: capability.gitDataRoot.standardizedFullPath,
                    role: candidate.kind == .patch ? .authorizedGitDiffArtifact : .ordinary
                )
            )
            dispositions.append(
                .authorized(path: path, kind: candidate.kind, readability: readability)
            )
        }

        return SelectedGitArtifactAuthorizationResult(
            entries: entries,
            consumedSelectionPaths: consumedPaths,
            dispositions: dispositions
        )
    }

    private func selectedArtifactCandidates(from selection: StoredSelection) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func append(_ path: String) {
            guard seen.insert(path).inserted else { return }
            candidates.append(path)
        }

        selection.selectedPaths.forEach(append)
        selection.slices
            .filter { !$0.value.isEmpty }
            .map(\.key)
            .sorted()
            .forEach(append)
        selection.autoCodemapPaths.forEach(append)
        return candidates
    }

    private func candidate(for path: String, gitDataRootPath: String) -> Candidate? {
        guard StandardizedPath.isDescendant(path, of: gitDataRootPath), path != gitDataRootPath else {
            return nil
        }
        let relativePath = String(path.dropFirst(gitDataRootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard isSafeRelativeArtifactPath(relativePath) else { return nil }

        if relativePath.hasSuffix("/MAP.txt") {
            let snapshotPath = String(relativePath.dropLast("/MAP.txt".count))
            guard let ref = snapshotStore.parseSnapshotRef(snapshotPath),
                  ref.repoKey != nil,
                  ref.snapshotDirRel == snapshotPath
            else { return nil }
            return .map(snapshotRef: ref)
        }

        guard let diffRange = relativePath.range(of: "/diff/", options: .backwards) else {
            return nil
        }
        let snapshotPath = String(relativePath[..<diffRange.lowerBound])
        let suffix = String(relativePath[diffRange.upperBound...])
        let artifactRelativePath = "diff/" + suffix
        let lowercased = artifactRelativePath.lowercased()
        guard lowercased.hasSuffix(".patch") || lowercased.hasSuffix(".diff"),
              let ref = snapshotStore.parseSnapshotRef(snapshotPath),
              ref.repoKey != nil,
              ref.snapshotDirRel == snapshotPath
        else { return nil }
        return .patch(snapshotRef: ref, relativePath: artifactRelativePath)
    }

    private func manifestMatches(
        _ ref: GitDiffSnapshotStore.GitDiffSnapshotRef,
        manifest: GitDiffSnapshotManifest
    ) -> Bool {
        guard let refRepoKey = ref.repoKey,
              let manifestRepoKey = manifest.repoKey,
              refRepoKey == manifestRepoKey,
              let normalizedManifestID = GitDiffSnapshotStore.normalizeSnapshotID(manifest.snapshotID),
              normalizedManifestID == manifest.snapshotID,
              normalizedManifestID == ref.snapshotID
        else { return false }
        return true
    }

    private func authorizeCheckout(
        manifest: GitDiffSnapshotManifest,
        capability: SelectedGitArtifactCapability
    ) async -> CheckoutAuthorization? {
        guard let manifestRepoRoot = normalizedRootPath(manifest.repoRoot) else { return nil }
        let boundCheckout = capability.boundCheckouts.first {
            GitRepoRootAuthorization.canonicalPath($0.physicalWorktreeRootPath) == manifestRepoRoot
        }
        let hasWorktreeMetadata =
            manifest.isWorktree == true ||
            manifest.worktreeName != nil ||
            manifest.worktreeRoot != nil ||
            manifest.mainWorktreeRoot != nil ||
            manifest.commonGitDir != nil

        if boundCheckout != nil || hasWorktreeMetadata {
            guard let boundCheckout,
                  manifest.isWorktree == true,
                  let manifestWorktreeRoot = normalizedRootPath(manifest.worktreeRoot),
                  let manifestCommonGitDir = normalizedRootPath(manifest.commonGitDir),
                  manifestWorktreeRoot == manifestRepoRoot,
                  manifestWorktreeRoot == GitRepoRootAuthorization.canonicalPath(
                      boundCheckout.physicalWorktreeRootPath
                  ),
                  let layout = GitRepositoryLayoutResolver.resolve(
                      atWorkTreeRoot: URL(fileURLWithPath: boundCheckout.physicalWorktreeRootPath)
                  ),
                  layout.isLinkedWorktree,
                  GitRepoRootAuthorization.canonicalPath(layout.workTreeRoot.path) == manifestWorktreeRoot,
                  GitRepoRootAuthorization.canonicalPath(layout.commonDir.path) == manifestCommonGitDir
            else { return nil }

            let repositoryIdentity = GitWorktreeIdentity.repositoryIdentity(
                commonGitDir: layout.commonDir,
                mainWorktreeRoot: layout.knownMainWorktreeRoot
            )
            let worktreeID = GitWorktreeIdentity.worktreeID(
                repositoryID: repositoryIdentity.repositoryID,
                gitDir: layout.gitDir,
                isMain: false,
                path: layout.workTreeRoot
            )
            guard repositoryIdentity.repositoryID == boundCheckout.repositoryID,
                  worktreeID == boundCheckout.worktreeID
            else { return nil }
            return .bound
        }

        guard GitRepoRootAuthorization.isPathWithinAuthorizedRoots(
            manifestRepoRoot,
            roots: capability.canonicalWorkspaceRootPaths
        ),
            let resolved = await vcsService.resolveRepo(from: URL(fileURLWithPath: manifestRepoRoot)),
            resolved.backendKind == .git,
            GitRepoRootAuthorization.canonicalPath(resolved.rootURL.path) == manifestRepoRoot,
            let layout = GitRepositoryLayoutResolver.resolve(atWorkTreeRoot: resolved.rootURL),
            !layout.isLinkedWorktree
        else { return nil }
        return .unbound
    }

    private func isWhitelisted(
        _ candidate: Candidate,
        manifest: GitDiffSnapshotManifest
    ) -> Bool {
        switch candidate {
        case .map:
            return true
        case let .patch(_, relativePath):
            if relativePath == "diff/all.patch" {
                return true
            }
            let listedPaths = Set(manifest.files.compactMap { file -> String? in
                guard let patchPath = file.patchPath,
                      let normalized = safeManifestPatchPath(patchPath)
                else { return nil }
                return normalized
            })
            return listedPaths.contains(relativePath)
        }
    }

    private func safeManifestPatchPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("diff/"),
              isSafeRelativeArtifactPath(trimmed),
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~")
        else { return nil }
        let lowercased = trimmed.lowercased()
        guard lowercased.hasSuffix(".patch") || lowercased.hasSuffix(".diff") else { return nil }
        return trimmed
    }

    private func isSafeRelativeArtifactPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !StandardizedPath.containsNUL(path)
        else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty &&
                component != "." &&
                component != ".." &&
                !component.contains(":")
        }
    }

    private func exactAbsolutePath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("/"),
              !StandardizedPath.containsNUL(trimmed)
        else { return nil }
        let standardized = StandardizedPath.absolute(trimmed)
        guard standardized == trimmed else { return nil }
        return standardized
    }

    private func normalizedRootPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else { return nil }
        return GitRepoRootAuthorization.canonicalPath(trimmed)
    }

    private func decodeManifest(_ content: String) -> GitDiffSnapshotManifest? {
        guard let data = content.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GitDiffSnapshotManifest.self, from: data)
    }
}
