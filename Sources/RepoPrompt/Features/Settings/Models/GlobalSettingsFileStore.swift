import Foundation

protocol GlobalSettingsFileStoring {
    var fileURL: URL { get }
    /// Non-nil when the on-disk file is blocked (unreadable or a newer schema); surfaced to the user.
    var blockReason: GlobalSettingsPersistenceBlockReason? { get }

    func load() throws -> GlobalSettingsDocument
    func loadOrCreateDefault() -> GlobalSettingsDocument
    func save(_ document: GlobalSettingsDocument) throws
    /// User-initiated recovery: backs up the offending file, writes fresh defaults, clears the block.
    @discardableResult
    func performUserInitiatedRecovery() -> Bool
}

/// Why global-settings persistence is currently blocked: the store loads in-memory defaults
/// and refuses to overwrite the on-disk file. Surfaced to the user so they can take a recovery
/// action; RepoPrompt never auto-recovers from a schema it did not write.
enum GlobalSettingsPersistenceBlockReason: Equatable {
    /// On-disk schema is newer than this build supports (`onDiskVersion` > `supportedVersion`).
    case unsupportedFutureSchema(onDiskVersion: Int, supportedVersion: Int)
    /// The on-disk file is unreadable and could not be moved to the Backups folder.
    case corruptUnrecoverable
}

/// File-backed store for the versioned global settings document.
///
/// Primary location:
/// `~/Library/Application Support/RepoPrompt CE/Settings/globalSettings.json`
final class GlobalSettingsFileStore: GlobalSettingsFileStoring {
    static let appSupportDirectoryName = "RepoPrompt CE"
    static let settingsDirectoryName = "Settings"
    static let filename = "globalSettings.json"

    let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private var preservingUnsupportedFutureDocument = false
    private var preservingUnbackedCorruptDocument = false

    /// Non-nil when the on-disk file cannot be safely read or overwritten, so the store falls
    /// back to in-memory defaults and refuses saves. Surfaced to the user (never auto-recovered).
    /// Cleared by `performUserInitiatedRecovery()`.
    private(set) var blockReason: GlobalSettingsPersistenceBlockReason?

    init(
        fileURL: URL = GlobalSettingsFileStore.defaultFileURL(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        settingsDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(filename)
    }

    static func settingsDirectoryURL(fileManager: FileManager = .default) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return supportDirectory
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(settingsDirectoryName, isDirectory: true)
    }

    func load() throws -> GlobalSettingsDocument {
        let data = try Data(contentsOf: fileURL)
        let header = try Self.decoder.decode(GlobalSettingsDocumentHeader.self, from: data)
        guard header.schemaVersion <= GlobalSettingsDocument.currentSchemaVersion else {
            preservingUnsupportedFutureDocument = true
            blockReason = .unsupportedFutureSchema(
                onDiskVersion: header.schemaVersion,
                supportedVersion: GlobalSettingsDocument.currentSchemaVersion
            )
            throw GlobalSettingsFileStoreError.unsupportedFutureSchema(header.schemaVersion)
        }
        preservingUnsupportedFutureDocument = false
        preservingUnbackedCorruptDocument = false
        blockReason = nil
        return try Self.decoder.decode(GlobalSettingsDocument.self, from: data)
    }

    func loadOrCreateDefault() -> GlobalSettingsDocument {
        preservingUnsupportedFutureDocument = false
        preservingUnbackedCorruptDocument = false
        blockReason = nil
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                var document = try load()
                if document.schemaVersion < GlobalSettingsDocument.currentSchemaVersion {
                    document.schemaVersion = GlobalSettingsDocument.currentSchemaVersion
                    writeFallbackDocument(document)
                }
                return document
            } catch let GlobalSettingsFileStoreError.unsupportedFutureSchema(version) {
                preservingUnsupportedFutureDocument = true
                print("⚠️ Global settings JSON schema v\(version) is newer than supported v\(GlobalSettingsDocument.currentSchemaVersion); preserving file and using in-memory defaults for this launch.")
                return defaultDocument()
            } catch {
                let fallback = defaultDocument()
                if backupCorruptFile(error: error) {
                    writeFallbackDocument(fallback)
                } else {
                    preservingUnbackedCorruptDocument = true
                    blockReason = .corruptUnrecoverable
                }
                return fallback
            }
        }

        let document = defaultDocument()
        writeFallbackDocument(document)
        return document
    }

    /// User-initiated recovery from a blocked state (`blockReason != nil`): backs up the
    /// offending on-disk file into `Backups/`, writes fresh current-schema defaults, and
    /// clears the block so saves resume. Never runs automatically — the app surfaces the
    /// block and the user chooses to recover. Returns whether the existing file was backed
    /// up (false only if the backup itself failed; the reset still happens).
    @discardableResult
    func performUserInitiatedRecovery() -> Bool {
        let didBackUp = fileManager.fileExists(atPath: fileURL.path)
            ? supersedeExistingFileToBackup(label: "superseded") != nil
            : true
        // Clear preservation flags so `save()` no longer refuses, then write fresh defaults.
        // `unsupportedFutureSchemaVersionOnDisk()` will now return nil because the offending
        // file was moved aside by `supersedeExistingFileToBackup`.
        preservingUnsupportedFutureDocument = false
        preservingUnbackedCorruptDocument = false
        writeFallbackDocument(defaultDocument())
        blockReason = nil
        return didBackUp
    }

    func save(_ document: GlobalSettingsDocument) throws {
        guard !preservingUnsupportedFutureDocument else {
            throw GlobalSettingsFileStoreError.unsupportedFutureSchemaPreserved
        }
        guard !preservingUnbackedCorruptDocument else {
            throw GlobalSettingsFileStoreError.corruptDocumentPreserved
        }
        if let futureVersion = unsupportedFutureSchemaVersionOnDisk() {
            preservingUnsupportedFutureDocument = true
            print("⚠️ Global settings JSON schema v\(futureVersion) is newer than supported v\(GlobalSettingsDocument.currentSchemaVersion); preserving file and skipping save.")
            throw GlobalSettingsFileStoreError.unsupportedFutureSchemaPreserved
        }
        try ensureSettingsDirectoryExists()
        var documentToWrite = document
        documentToWrite.schemaVersion = max(document.schemaVersion, GlobalSettingsDocument.currentSchemaVersion)
        documentToWrite.updatedAt = now()
        let data = try Self.encoder.encode(documentToWrite)
        try data.write(to: fileURL, options: .atomic)
    }

    private func defaultDocument() -> GlobalSettingsDocument {
        GlobalSettingsDocument(
            updatedAt: now(),
            globalDefaults: GlobalDefaults(discoverAgentRaw: nil, discoverModelsByAgent: nil),
            scalarPreferences: GlobalScalarPreferences()
        )
    }

    private func writeFallbackDocument(_ document: GlobalSettingsDocument) {
        do {
            try save(document)
        } catch {
            print("⚠️ Failed to write global settings JSON at \(fileURL.path): \(error)")
        }
    }

    private func ensureSettingsDirectoryExists() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Moves (or copies + removes) the current on-disk file into `Backups/` with the given
    /// label. Returns the backup URL on success, or nil if there was no file to back up or the
    /// move failed. The original path is left empty so a following `save()` cannot re-trip the
    /// newer-schema guard.
    @discardableResult
    private func supersedeExistingFileToBackup(label: String) -> URL? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let backupDirectory = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("Backups", isDirectory: true)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

            let stamp = Self.backupTimestamp(for: now())
            var backupURL = backupDirectory
                .appendingPathComponent("globalSettings.\(label)-\(stamp).json")
            if fileManager.fileExists(atPath: backupURL.path) {
                backupURL = backupDirectory
                    .appendingPathComponent("globalSettings.\(label)-\(stamp)-\(UUID().uuidString).json")
            }

            do {
                try fileManager.moveItem(at: fileURL, to: backupURL)
            } catch {
                try fileManager.copyItem(at: fileURL, to: backupURL)
                try? fileManager.removeItem(at: fileURL)
            }
            return backupURL
        } catch {
            print("⚠️ Failed to back up global settings JSON at \(fileURL.path): \(error)")
            return nil
        }
    }

    private func backupCorruptFile(error: Error) -> Bool {
        guard let backupURL = supersedeExistingFileToBackup(label: "corrupt") else { return false }
        print("⚠️ Backed up corrupt global settings JSON to \(backupURL.path): \(error)")
        return true
    }

    private func unsupportedFutureSchemaVersionOnDisk() -> Int? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let header = try? Self.decoder.decode(GlobalSettingsDocumentHeader.self, from: data),
              header.schemaVersion > GlobalSettingsDocument.currentSchemaVersion
        else {
            return nil
        }
        return header.schemaVersion
    }

    private static func backupTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private struct GlobalSettingsDocumentHeader: Decodable {
        let schemaVersion: Int
    }

    enum GlobalSettingsFileStoreError: Error, Equatable {
        case unsupportedFutureSchema(Int)
        case unsupportedFutureSchemaPreserved
        case corruptDocumentPreserved
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
