import CryptoKit
import Darwin
import Foundation

struct WorkspaceRootNamespaceManifestResourcePolicy: Equatable {
    static let `default` = WorkspaceRootNamespaceManifestResourcePolicy()

    let maximumBufferedRecordBytes: Int
    let maximumRecordsPerBatch: Int
    let maximumRecordByteCount: Int
    let maximumOpenRuns: Int
    let minimumFreeDiskBytes: UInt64

    init(
        maximumBufferedRecordBytes: Int = 16 * 1024 * 1024,
        maximumRecordsPerBatch: Int = 32768,
        maximumRecordByteCount: Int = 1024 * 1024,
        maximumOpenRuns: Int = 32,
        minimumFreeDiskBytes: UInt64 = 256 * 1024 * 1024
    ) {
        self.maximumBufferedRecordBytes = maximumBufferedRecordBytes
        self.maximumRecordsPerBatch = maximumRecordsPerBatch
        self.maximumRecordByteCount = maximumRecordByteCount
        self.maximumOpenRuns = maximumOpenRuns
        self.minimumFreeDiskBytes = minimumFreeDiskBytes
    }

    var isValid: Bool {
        maximumBufferedRecordBytes > 0 && maximumRecordsPerBatch > 0 &&
            maximumRecordByteCount > 0 &&
            maximumRecordByteCount <= WorkspaceRootNamespaceManifestCodec.maximumPathByteCount &&
            maximumOpenRuns >= 2
    }
}

final class WorkspaceRootNamespaceManifestStore: @unchecked Sendable {
    let directoryURL: URL

    private struct Artifact {
        let url: URL
        var leaseCount: Int
    }

    private let lock = NSLock()
    private var artifacts: [UUID: Artifact] = [:]
    private var activeWorkspaces: Set<String> = []
    #if DEBUG
        private var cleanupWillEnumerateHandlerForTesting: (@Sendable () -> Void)?
    #endif

    init(directoryURL: URL? = nil) throws {
        let chosen = directoryURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("repoprompt-namespace-manifests-\(UUID().uuidString.lowercased())", isDirectory: true)
        self.directoryURL = chosen
        try Self.ensureSecureDirectory(chosen)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func makeWriter(
        identity: WorkspaceRootNamespaceManifestIdentity,
        resourcePolicy: WorkspaceRootNamespaceManifestResourcePolicy = .default
    ) throws -> WorkspaceRootNamespaceManifestWriter {
        guard resourcePolicy.isValid else {
            throw WorkspaceRootNamespaceManifestError.invalidConfiguration
        }
        let policy = identity.catalogPolicy
        guard !identity.root.canonicalPathBytes.isEmpty,
              identity.root.canonicalPathBytes.count <= 512 * 1024,
              policy.schemaVersion >= 0,
              policy.schemaVersion <= Int(UInt32.max),
              policy.mandatoryIgnorePolicyIdentity.utf8.count +
              policy.globalIgnoreDefaultsDigest.utf8.count <= 256 * 1024
        else { throw WorkspaceRootNamespaceManifestError.invalidConfiguration }
        try admit(resourcePolicy)
        let workspaceName = ".work.\(UUID().uuidString.lowercased())"
        let workspaceURL = directoryURL.appendingPathComponent(workspaceName, isDirectory: true)
        try lock.withLock {
            guard mkdir(workspaceURL.path, 0o700) == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "workspace-mkdir", code: errno)
            }
            activeWorkspaces.insert(workspaceName)
        }
        return WorkspaceRootNamespaceManifestWriter(
            store: self,
            identity: identity,
            policy: resourcePolicy,
            workspaceName: workspaceName,
            workspaceURL: workspaceURL
        )
    }

    var activeArtifactURLs: [URL] {
        lock.withLock { artifacts.values.map(\.url).sorted { $0.path < $1.path } }
    }

    func cleanup() throws {
        try lock.withLock {
            let retainedNames = Set(artifacts.values.map(\.url.lastPathComponent)).union(activeWorkspaces)
            #if DEBUG
                cleanupWillEnumerateHandlerForTesting?()
            #endif
            let children = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )
            for child in children where !retainedNames.contains(child.lastPathComponent) {
                try FileManager.default.removeItem(at: child)
            }
        }
    }

    #if DEBUG
        func setCleanupWillEnumerateHandlerForTesting(_ handler: (@Sendable () -> Void)?) {
            lock.withLock { cleanupWillEnumerateHandlerForTesting = handler }
        }
    #endif

    fileprivate func admit(_ policy: WorkspaceRootNamespaceManifestResourcePolicy) throws {
        var information = statfs()
        guard statfs(directoryURL.path, &information) == 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "statfs", code: errno)
        }
        let available = UInt64(information.f_bavail) * UInt64(information.f_bsize)
        guard available >= policy.minimumFreeDiskBytes else {
            throw WorkspaceRootNamespaceManifestError.resourceAdmission
        }
    }

    fileprivate func publish(
        temporaryURL: URL,
        workspaceName: String,
        header: WorkspaceRootNamespaceManifestHeader,
        footer: WorkspaceRootNamespaceManifestFooter,
        statistics: WorkspaceRootNamespaceManifestStatistics,
        peakResidentScheduledRunCount: Int
    ) throws -> WorkspaceRootNamespaceManifestLease {
        let token = UUID()
        let finalURL = directoryURL.appendingPathComponent("\(token.uuidString.lowercased()).manifest")
        try lock.withLock {
            guard rename(temporaryURL.path, finalURL.path) == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "manifest-rename", code: errno)
            }
            do {
                try synchronizeDirectory()
            } catch {
                try? FileManager.default.removeItem(at: finalURL)
                throw error
            }
            artifacts[token] = Artifact(url: finalURL, leaseCount: 1)
            activeWorkspaces.remove(workspaceName)
            try? FileManager.default.removeItem(
                at: directoryURL.appendingPathComponent(workspaceName, isDirectory: true)
            )
        }
        return WorkspaceRootNamespaceManifestLease(
            store: self,
            token: token,
            fileURL: finalURL,
            header: header,
            footer: footer,
            statistics: statistics,
            peakResidentScheduledRunCount: peakResidentScheduledRunCount
        )
    }

    fileprivate func discardWorkspace(name: String) {
        lock.withLock {
            activeWorkspaces.remove(name)
            try? FileManager.default.removeItem(
                at: directoryURL.appendingPathComponent(name, isDirectory: true)
            )
        }
    }

    fileprivate func release(token: UUID) {
        lock.withLock {
            guard var artifact = artifacts[token] else { return }
            artifact.leaseCount -= 1
            if artifact.leaseCount > 0 {
                artifacts[token] = artifact
                return
            }
            artifacts.removeValue(forKey: token)
            try? FileManager.default.removeItem(at: artifact.url)
            try? synchronizeDirectory()
        }
    }

    fileprivate func openReader(at url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "manifest-open", code: errno)
        }
        do {
            try Self.validateSecureRegularFile(descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    fileprivate static func createSecureFile(at url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "file-create", code: errno)
        }
        return descriptor
    }

    fileprivate static func openRun(at url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "run-open", code: errno)
        }
        do {
            try validateSecureRegularFile(descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func ensureSecureDirectory(_ url: URL) throws {
        if mkdir(url.path, 0o700) != 0, errno != EEXIST {
            throw WorkspaceRootNamespaceManifestError.io(operation: "store-mkdir", code: errno)
        }
        var status = stat()
        guard lstat(url.path, &status) == 0,
              status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              status.st_uid == getuid(),
              status.st_mode & 0o7777 == 0o700
        else { throw WorkspaceRootNamespaceManifestError.resourceAdmission }
    }

    private static func validateSecureRegularFile(_ descriptor: Int32) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "file-fstat", code: errno)
        }
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              status.st_uid == getuid(),
              status.st_mode & 0o7777 == 0o600
        else { throw WorkspaceRootNamespaceManifestError.resourceAdmission }
    }

    private func synchronizeDirectory() throws {
        let descriptor = open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "directory-open", code: errno)
        }
        defer { Darwin.close(descriptor) }
        while fsync(descriptor) != 0 {
            guard errno == EINTR else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "directory-fsync", code: errno)
            }
        }
    }
}

final class WorkspaceRootNamespaceManifestLease: @unchecked Sendable {
    let fileURL: URL
    let header: WorkspaceRootNamespaceManifestHeader
    let footer: WorkspaceRootNamespaceManifestFooter
    let statistics: WorkspaceRootNamespaceManifestStatistics
    let peakResidentScheduledRunCount: Int

    var digest: Data {
        footer.digest
    }

    private let store: WorkspaceRootNamespaceManifestStore
    private let token: UUID

    fileprivate init(
        store: WorkspaceRootNamespaceManifestStore,
        token: UUID,
        fileURL: URL,
        header: WorkspaceRootNamespaceManifestHeader,
        footer: WorkspaceRootNamespaceManifestFooter,
        statistics: WorkspaceRootNamespaceManifestStatistics,
        peakResidentScheduledRunCount: Int
    ) {
        self.store = store
        self.token = token
        self.fileURL = fileURL
        self.header = header
        self.footer = footer
        self.statistics = statistics
        self.peakResidentScheduledRunCount = peakResidentScheduledRunCount
    }

    deinit {
        store.release(token: token)
    }

    func makeReader() throws -> WorkspaceRootNamespaceManifestReader {
        let validationReader = try openReader()
        while try validationReader.next() != nil {}
        return try openReader()
    }

    private func openReader() throws -> WorkspaceRootNamespaceManifestReader {
        let descriptor = try store.openReader(at: fileURL)
        do { return try WorkspaceRootNamespaceManifestReader(descriptor: descriptor, lease: self) }
        catch {
            Darwin.close(descriptor)
            throw error
        }
    }
}

actor WorkspaceRootNamespaceManifestWriter {
    private let store: WorkspaceRootNamespaceManifestStore
    private let header: WorkspaceRootNamespaceManifestHeader
    private let policy: WorkspaceRootNamespaceManifestResourcePolicy
    private let workspaceName: String
    private let workspaceURL: URL

    private var bufferedRecords: [WorkspaceRootNamespaceRecord] = []
    private var bufferedRecordBytes = 0
    private var peakBufferedRecordBytes = 0
    private var initialRunCatalogWriter: RunCatalogWriter?
    private var nextRunNumber: UInt64 = 0
    private var nextCatalogNumber: UInt64 = 0
    private var initialRunCount = 0
    private var mergePassCount = 0
    private var peakResidentScheduledRunCount = 0
    private var isClosed = false

    fileprivate init(
        store: WorkspaceRootNamespaceManifestStore,
        identity: WorkspaceRootNamespaceManifestIdentity,
        policy: WorkspaceRootNamespaceManifestResourcePolicy,
        workspaceName: String,
        workspaceURL: URL
    ) {
        self.store = store
        header = WorkspaceRootNamespaceManifestHeader(identity: identity)
        self.policy = policy
        self.workspaceName = workspaceName
        self.workspaceURL = workspaceURL
    }

    deinit {
        store.discardWorkspace(name: workspaceName)
    }

    func append(_ record: WorkspaceRootNamespaceRecord) async throws {
        try await append(contentsOf: [record])
    }

    func append(contentsOf records: [WorkspaceRootNamespaceRecord]) async throws {
        guard !isClosed else { throw WorkspaceRootNamespaceManifestError.closed }
        do {
            for record in records {
                try Task.checkCancellation()
                try WorkspaceRootNamespaceManifestCodec.validate(
                    record,
                    maximumByteCount: policy.maximumRecordByteCount
                )
                let bytes = try WorkspaceRootNamespaceManifestCodec.encodeRecord(record).count
                if !bufferedRecords.isEmpty,
                   bufferedRecordBytes + bytes > policy.maximumBufferedRecordBytes ||
                   bufferedRecords.count >= policy.maximumRecordsPerBatch
                {
                    try flushRun()
                }
                bufferedRecords.append(record)
                bufferedRecordBytes += bytes
                peakBufferedRecordBytes = max(peakBufferedRecordBytes, bufferedRecordBytes)
                if bufferedRecordBytes >= policy.maximumBufferedRecordBytes ||
                    bufferedRecords.count >= policy.maximumRecordsPerBatch
                {
                    try flushRun()
                }
            }
        } catch {
            abort()
            throw error
        }
    }

    func finish() async throws -> WorkspaceRootNamespaceManifestLease {
        guard !isClosed else { throw WorkspaceRootNamespaceManifestError.closed }
        do {
            try Task.checkCancellation()
            try flushRun()
            var catalog = try finishInitialRunCatalog()
            initialRunCount = Int(clamping: catalog.count)
            try store.admit(policy)

            while catalog.count > UInt64(policy.maximumOpenRuns) {
                try Task.checkCancellation()
                catalog = try mergePass(catalog)
                mergePassCount += 1
            }

            let finalRuns = try readRunGroup(
                from: catalog,
                maximumCount: policy.maximumOpenRuns
            )
            peakResidentScheduledRunCount = max(
                peakResidentScheduledRunCount,
                finalRuns.count
            )
            if finalRuns.count > 1 { mergePassCount += 1 }
            let result = try writeFinalManifest(from: finalRuns)
            remove(finalRuns)
            try? FileManager.default.removeItem(at: catalog.url)
            let statistics = WorkspaceRootNamespaceManifestStatistics(
                initialRunCount: initialRunCount,
                mergePassCount: mergePassCount,
                peakBufferedRecordBytes: peakBufferedRecordBytes,
                recordCount: result.footer.recordCount,
                finalByteCount: result.byteCount
            )
            let lease = try store.publish(
                temporaryURL: result.url,
                workspaceName: workspaceName,
                header: header,
                footer: result.footer,
                statistics: statistics,
                peakResidentScheduledRunCount: peakResidentScheduledRunCount
            )
            isClosed = true
            return lease
        } catch {
            abort()
            throw error
        }
    }

    func cancel() {
        abort()
    }

    private func flushRun() throws {
        guard !bufferedRecords.isEmpty else { return }
        try store.admit(policy)
        bufferedRecords.sort {
            WorkspaceRootNamespaceManifestCodec.lexicallyPrecedes(
                $0.relativePathBytes,
                $1.relativePathBytes
            )
        }
        for index in bufferedRecords.indices.dropFirst() where
            bufferedRecords[index - 1].relativePathBytes == bufferedRecords[index].relativePathBytes
        {
            throw WorkspaceRootNamespaceManifestError.duplicatePath
        }
        let run = makeRunReference()
        let descriptor = try WorkspaceRootNamespaceManifestStore.createSecureFile(at: run.url)
        var descriptorIsOpen = true
        var digest = SHA256()
        var recordCount: UInt64 = 0
        do {
            for record in bufferedRecords {
                let payload = try WorkspaceRootNamespaceManifestCodec.encodeRecord(record)
                var length = Data()
                WorkspaceRootNamespaceManifestCodec.append(UInt32(payload.count), to: &length)
                try WorkspaceRootNamespaceManifestCodec.writeAll(length, to: descriptor)
                try WorkspaceRootNamespaceManifestCodec.writeAll(payload, to: descriptor)
                digest.update(data: length)
                digest.update(data: payload)
                recordCount &+= 1
            }
            try writeRunFooter(recordCount: recordCount, digest: Data(digest.finalize()), to: descriptor)
            try synchronize(descriptor)
            let closeResult = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeResult == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "file-close", code: errno)
            }
        } catch {
            if descriptorIsOpen { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: run.url)
            throw error
        }
        do {
            try initialCatalogWriter().append(run.id)
        } catch {
            try? FileManager.default.removeItem(at: run.url)
            throw error
        }
        bufferedRecords.removeAll(keepingCapacity: true)
        bufferedRecordBytes = 0
    }

    private func mergeRunsToRun(_ input: [URL]) throws -> RunReference {
        try store.admit(policy)
        let output = makeRunReference()
        let descriptor = try WorkspaceRootNamespaceManifestStore.createSecureFile(at: output.url)
        var descriptorIsOpen = true
        var digest = SHA256()
        var recordCount: UInt64 = 0
        do {
            try merge(input) { record in
                try Task.checkCancellation()
                let payload = try WorkspaceRootNamespaceManifestCodec.encodeRecord(record)
                var length = Data()
                WorkspaceRootNamespaceManifestCodec.append(UInt32(payload.count), to: &length)
                try WorkspaceRootNamespaceManifestCodec.writeAll(length, to: descriptor)
                try WorkspaceRootNamespaceManifestCodec.writeAll(payload, to: descriptor)
                digest.update(data: length)
                digest.update(data: payload)
                recordCount &+= 1
            }
            try writeRunFooter(recordCount: recordCount, digest: Data(digest.finalize()), to: descriptor)
            try synchronize(descriptor)
            let closeResult = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeResult == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "file-close", code: errno)
            }
            return output
        } catch {
            if descriptorIsOpen { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: output.url)
            throw error
        }
    }

    private func writeFinalManifest(from input: [URL]) throws -> (
        url: URL,
        footer: WorkspaceRootNamespaceManifestFooter,
        byteCount: UInt64
    ) {
        let url = workspaceURL.appendingPathComponent("manifest.incomplete")
        let descriptor = try WorkspaceRootNamespaceManifestStore.createSecureFile(at: url)
        var descriptorIsOpen = true
        var digest = SHA256()
        var records: UInt64 = 0
        var files: UInt64 = 0
        var directories: UInt64 = 0
        var payloadBytes: UInt64 = 0
        do {
            let headerFrame = WorkspaceRootNamespaceManifestCodec.encodeHeader(header)
            try WorkspaceRootNamespaceManifestCodec.writeAll(headerFrame, to: descriptor)
            digest.update(data: headerFrame)
            try merge(input) { record in
                try Task.checkCancellation()
                let payload = try WorkspaceRootNamespaceManifestCodec.encodeRecord(record)
                let frame = try WorkspaceRootNamespaceManifestCodec.recordFrame(record)
                try WorkspaceRootNamespaceManifestCodec.writeAll(frame, to: descriptor)
                digest.update(data: frame)
                records &+= 1
                payloadBytes &+= UInt64(payload.count)
                switch record.kind {
                case .file: files &+= 1
                case .directory: directories &+= 1
                }
            }
            let footer = WorkspaceRootNamespaceManifestFooter(
                recordCount: records,
                fileCount: files,
                directoryCount: directories,
                recordPayloadByteCount: payloadBytes,
                digest: Data(digest.finalize())
            )
            try WorkspaceRootNamespaceManifestCodec.writeAll(
                WorkspaceRootNamespaceManifestCodec.encodeFooter(footer),
                to: descriptor
            )
            try synchronize(descriptor)
            let closeResult = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeResult == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "file-close", code: errno)
            }
            var status = stat()
            guard lstat(url.path, &status) == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "manifest-lstat", code: errno)
            }
            return (url, footer, UInt64(status.st_size))
        } catch {
            if descriptorIsOpen { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func merge(
        _ urls: [URL],
        consume: (WorkspaceRootNamespaceRecord) throws -> Void
    ) throws {
        let cursors = try urls.map { try RunCursor(url: $0, maximumRecordByteCount: policy.maximumRecordByteCount) }
        var previous: Data?
        while true {
            try Task.checkCancellation()
            var selected: Int?
            for index in cursors.indices where cursors[index].record != nil {
                guard let current = cursors[index].record else { continue }
                if let selectedIndex = selected,
                   let selectedRecord = cursors[selectedIndex].record,
                   !WorkspaceRootNamespaceManifestCodec.lexicallyPrecedes(
                       current.relativePathBytes,
                       selectedRecord.relativePathBytes
                   )
                {
                    continue
                }
                selected = index
            }
            guard let selected, let record = cursors[selected].record else { return }
            if previous == record.relativePathBytes {
                throw WorkspaceRootNamespaceManifestError.duplicatePath
            }
            if let previous,
               !WorkspaceRootNamespaceManifestCodec.lexicallyPrecedes(previous, record.relativePathBytes)
            {
                throw WorkspaceRootNamespaceManifestError.outOfOrder
            }
            try consume(record)
            previous = record.relativePathBytes
            try cursors[selected].advance()
        }
    }

    private func makeRunReference() -> RunReference {
        defer { nextRunNumber &+= 1 }
        return RunReference(
            id: nextRunNumber,
            url: workspaceURL.appendingPathComponent("run.\(nextRunNumber)")
        )
    }

    private func runReference(id: UInt64) -> RunReference {
        RunReference(
            id: id,
            url: workspaceURL.appendingPathComponent("run.\(id)")
        )
    }

    private func makeCatalogWriter() throws -> RunCatalogWriter {
        defer { nextCatalogNumber &+= 1 }
        let stem = "catalog.\(nextCatalogNumber)"
        return try RunCatalogWriter(
            incompleteURL: workspaceURL.appendingPathComponent("\(stem).incomplete"),
            finalURL: workspaceURL.appendingPathComponent(stem)
        )
    }

    private func initialCatalogWriter() throws -> RunCatalogWriter {
        if let initialRunCatalogWriter { return initialRunCatalogWriter }
        let writer = try makeCatalogWriter()
        initialRunCatalogWriter = writer
        return writer
    }

    private func finishInitialRunCatalog() throws -> RunCatalog {
        let writer = try initialCatalogWriter()
        let catalog = try writer.finish()
        initialRunCatalogWriter = nil
        return catalog
    }

    private func mergePass(_ inputCatalog: RunCatalog) throws -> RunCatalog {
        let outputWriter = try makeCatalogWriter()
        do {
            let cursor = try RunCatalogCursor(url: inputCatalog.url)
            while true {
                try Task.checkCancellation()
                var group: [URL] = []
                group.reserveCapacity(policy.maximumOpenRuns)
                while group.count < policy.maximumOpenRuns, let id = try cursor.next() {
                    group.append(runReference(id: id).url)
                }
                guard !group.isEmpty else { break }
                peakResidentScheduledRunCount = max(
                    peakResidentScheduledRunCount,
                    group.count
                )
                let output = try mergeRunsToRun(group)
                try outputWriter.append(output.id)
                remove(group)
            }
            guard cursor.recordCount == inputCatalog.count else {
                throw WorkspaceRootNamespaceManifestError.corrupt("catalog count mismatch")
            }
            let outputCatalog = try outputWriter.finish()
            try? FileManager.default.removeItem(at: inputCatalog.url)
            return outputCatalog
        } catch {
            outputWriter.cancel()
            throw error
        }
    }

    private func readRunGroup(
        from catalog: RunCatalog,
        maximumCount: Int
    ) throws -> [URL] {
        let cursor = try RunCatalogCursor(url: catalog.url)
        var result: [URL] = []
        result.reserveCapacity(min(maximumCount, Int(clamping: catalog.count)))
        while let id = try cursor.next() {
            guard result.count < maximumCount else {
                throw WorkspaceRootNamespaceManifestError.corrupt("catalog exceeds merge fan-in")
            }
            result.append(runReference(id: id).url)
        }
        guard UInt64(result.count) == catalog.count else {
            throw WorkspaceRootNamespaceManifestError.corrupt("catalog count mismatch")
        }
        return result
    }

    private func remove(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func writeRunFooter(recordCount: UInt64, digest: Data, to descriptor: Int32) throws {
        var footer = Data()
        WorkspaceRootNamespaceManifestCodec.append(UInt32.max, to: &footer)
        WorkspaceRootNamespaceManifestCodec.append(recordCount, to: &footer)
        footer.append(digest)
        try WorkspaceRootNamespaceManifestCodec.writeAll(footer, to: descriptor)
    }

    private func synchronize(_ descriptor: Int32) throws {
        while fsync(descriptor) != 0 {
            guard errno == EINTR else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "file-fsync", code: errno)
            }
        }
    }

    private func abort() {
        guard !isClosed else { return }
        isClosed = true
        bufferedRecords.removeAll()
        bufferedRecordBytes = 0
        initialRunCatalogWriter?.cancel()
        initialRunCatalogWriter = nil
        store.discardWorkspace(name: workspaceName)
    }
}

private struct RunReference {
    let id: UInt64
    let url: URL
}

private struct RunCatalog {
    let url: URL
    let count: UInt64
}

private final class RunCatalogWriter {
    private static let magic = Data("RPRUNCAT".utf8)

    private let incompleteURL: URL
    private let finalURL: URL
    private var descriptor: Int32
    private var digest = SHA256()
    private var count: UInt64 = 0
    private var isClosed = false

    init(incompleteURL: URL, finalURL: URL) throws {
        self.incompleteURL = incompleteURL
        self.finalURL = finalURL
        descriptor = try WorkspaceRootNamespaceManifestStore.createSecureFile(at: incompleteURL)
        do {
            try WorkspaceRootNamespaceManifestCodec.writeAll(Self.magic, to: descriptor)
        } catch {
            Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: incompleteURL)
            throw error
        }
    }

    deinit {
        cancel()
    }

    func append(_ runID: UInt64) throws {
        guard !isClosed, runID != UInt64.max, count != UInt64.max else {
            throw WorkspaceRootNamespaceManifestError.corrupt("invalid run catalog record")
        }
        var frame = Data()
        WorkspaceRootNamespaceManifestCodec.append(runID, to: &frame)
        try WorkspaceRootNamespaceManifestCodec.writeAll(frame, to: descriptor)
        digest.update(data: frame)
        count &+= 1
    }

    func finish() throws -> RunCatalog {
        guard !isClosed else { throw WorkspaceRootNamespaceManifestError.closed }
        do {
            var footer = Data()
            WorkspaceRootNamespaceManifestCodec.append(UInt64.max, to: &footer)
            WorkspaceRootNamespaceManifestCodec.append(count, to: &footer)
            footer.append(Data(digest.finalize()))
            try WorkspaceRootNamespaceManifestCodec.writeAll(footer, to: descriptor)
            try synchronizeFile(descriptor)
            let closeResult = Darwin.close(descriptor)
            descriptor = -1
            guard closeResult == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "catalog-close", code: errno)
            }
            guard rename(incompleteURL.path, finalURL.path) == 0 else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "catalog-rename", code: errno)
            }
            do {
                try synchronizeDirectory(finalURL.deletingLastPathComponent())
            } catch {
                try? FileManager.default.removeItem(at: finalURL)
                throw error
            }
            isClosed = true
            return RunCatalog(url: finalURL, count: count)
        } catch {
            cancel()
            throw error
        }
    }

    func cancel() {
        guard !isClosed else { return }
        isClosed = true
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        try? FileManager.default.removeItem(at: incompleteURL)
        try? FileManager.default.removeItem(at: finalURL)
    }

    private func synchronizeFile(_ descriptor: Int32) throws {
        while fsync(descriptor) != 0 {
            guard errno == EINTR else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "catalog-fsync", code: errno)
            }
        }
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let directoryDescriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryDescriptor >= 0 else {
            throw WorkspaceRootNamespaceManifestError.io(operation: "catalog-directory-open", code: errno)
        }
        defer { Darwin.close(directoryDescriptor) }
        while fsync(directoryDescriptor) != 0 {
            guard errno == EINTR else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "catalog-directory-fsync", code: errno)
            }
        }
    }
}

private final class RunCatalogCursor {
    private static let magic = Data("RPRUNCAT".utf8)

    private let descriptor: Int32
    private var digest = SHA256()
    private var previousRunID: UInt64?
    private var reachedFooter = false
    private(set) var recordCount: UInt64 = 0

    init(url: URL) throws {
        descriptor = try WorkspaceRootNamespaceManifestStore.openRun(at: url)
        do {
            let magic = try WorkspaceRootNamespaceManifestCodec.readExact(
                descriptor,
                count: Self.magic.count
            )
            guard magic == Self.magic else {
                throw WorkspaceRootNamespaceManifestError.corrupt("invalid run catalog header")
            }
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(descriptor)
    }

    func next() throws -> UInt64? {
        if reachedFooter { return nil }
        let frame = try WorkspaceRootNamespaceManifestCodec.readExact(descriptor, count: 8)
        var cursor = WorkspaceRootNamespaceManifestCodec.ByteCursor(frame)
        let value = try cursor.readUInt64()
        if value == UInt64.max {
            let footer = try WorkspaceRootNamespaceManifestCodec.readExact(
                descriptor,
                count: 8 + SHA256.byteCount
            )
            var footerCursor = WorkspaceRootNamespaceManifestCodec.ByteCursor(footer)
            let expectedCount = try footerCursor.readUInt64()
            let expectedDigest = try footerCursor.readData(count: SHA256.byteCount)
            guard expectedCount == recordCount,
                  expectedDigest == Data(digest.finalize())
            else { throw WorkspaceRootNamespaceManifestError.corrupt("run catalog footer mismatch") }
            try requireEndOfFile()
            reachedFooter = true
            return nil
        }
        if let previousRunID, value <= previousRunID {
            throw WorkspaceRootNamespaceManifestError.corrupt("unordered run catalog")
        }
        previousRunID = value
        digest.update(data: frame)
        recordCount &+= 1
        return value
    }

    private func requireEndOfFile() throws {
        var byte: UInt8 = 0
        while true {
            let readCount = Darwin.read(descriptor, &byte, 1)
            if readCount == 0 { return }
            if readCount > 0 {
                throw WorkspaceRootNamespaceManifestError.corrupt("run catalog trailing bytes")
            }
            guard errno == EINTR else {
                throw WorkspaceRootNamespaceManifestError.io(operation: "catalog-trailing-read", code: errno)
            }
        }
    }
}

private final class RunCursor {
    private let descriptor: Int32
    private let maximumRecordByteCount: Int
    private(set) var record: WorkspaceRootNamespaceRecord?
    private var digest = SHA256()
    private var recordCount: UInt64 = 0
    private var reachedFooter = false

    init(url: URL, maximumRecordByteCount: Int) throws {
        descriptor = try WorkspaceRootNamespaceManifestStore.openRun(at: url)
        self.maximumRecordByteCount = maximumRecordByteCount
        do {
            try advance()
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(descriptor)
    }

    func advance() throws {
        guard !reachedFooter else {
            throw WorkspaceRootNamespaceManifestError.corrupt("run read after footer")
        }
        var first: UInt8 = 0
        let readCount = Darwin.read(descriptor, &first, 1)
        if readCount == 0 {
            throw WorkspaceRootNamespaceManifestError.corrupt("run missing footer")
        }
        if readCount < 0 {
            if errno == EINTR { return try advance() }
            throw WorkspaceRootNamespaceManifestError.io(operation: "run-read", code: errno)
        }
        var lengthBytes = Data([first])
        try lengthBytes.append(WorkspaceRootNamespaceManifestCodec.readExact(descriptor, count: 3))
        let length = try WorkspaceRootNamespaceManifestCodec.decodeUInt32(lengthBytes)
        if length == UInt32.max {
            let footer = try WorkspaceRootNamespaceManifestCodec.readExact(
                descriptor,
                count: 8 + SHA256.byteCount
            )
            var cursor = WorkspaceRootNamespaceManifestCodec.ByteCursor(footer)
            let expectedCount = try cursor.readUInt64()
            let expectedDigest = try cursor.readData(count: SHA256.byteCount)
            guard expectedCount == recordCount,
                  expectedDigest == Data(digest.finalize())
            else { throw WorkspaceRootNamespaceManifestError.corrupt("run footer mismatch") }
            var trailing: UInt8 = 0
            let trailingCount = Darwin.read(descriptor, &trailing, 1)
            guard trailingCount == 0 else {
                if trailingCount < 0 {
                    throw WorkspaceRootNamespaceManifestError.io(operation: "run-trailing-read", code: errno)
                }
                throw WorkspaceRootNamespaceManifestError.corrupt("run trailing bytes")
            }
            reachedFooter = true
            record = nil
            return
        }
        guard length > 0, length <= UInt32(maximumRecordByteCount + 8) else {
            throw WorkspaceRootNamespaceManifestError.corrupt("invalid run record length")
        }
        let payload = try WorkspaceRootNamespaceManifestCodec.readExact(descriptor, count: Int(length))
        let decoded = try WorkspaceRootNamespaceManifestCodec.decodeRecord(payload)
        try WorkspaceRootNamespaceManifestCodec.validate(decoded, maximumByteCount: maximumRecordByteCount)
        digest.update(data: lengthBytes)
        digest.update(data: payload)
        recordCount &+= 1
        record = decoded
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
