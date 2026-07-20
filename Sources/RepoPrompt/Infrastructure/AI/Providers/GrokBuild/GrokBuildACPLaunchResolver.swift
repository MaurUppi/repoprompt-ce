import Foundation

struct GrokBuildACPResolvedLaunch: Equatable {
    let command: String
    let arguments: [String]
    let additionalPathHints: [String]
    let executableIdentity: ExecutableFileIdentity
}

enum GrokBuildACPLaunchResolutionError: Error, Equatable, LocalizedError {
    case missingConfiguredCommand
    case exactPathNotFound(String)
    case noValidLaunchCandidate(String, [String], ShellEnvironmentSource?)
    case environmentDiscoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguredCommand:
            "Grok Build ACP launch requires an `grok` command or executable path."
        case let .exactPathNotFound(command):
            "Grok Build CLI was not found as a valid executable regular file for `\(command)`. Install Grok Build or configure its absolute path."
        case let .noValidLaunchCandidate(command, failures, source):
            AgentCLILaunchDiagnostics.appendFallbackEnvironmentHint(
                to: "Grok Build CLI was not found as a valid executable regular file for `\(command)`. Tried: \(failures.joined(separator: "; "))",
                source: source
            )
        case let .environmentDiscoveryRequired(command):
            "Grok Build CLI path discovery has not completed for `\(command)`. Run the Grok Build ACP support preflight or configure an absolute executable path."
        }
    }
}

final class GrokBuildACPLaunchResolver: @unchecked Sendable {
    typealias EnvironmentProvider = @Sendable (_ enableDebugLogging: Bool) async -> ACPLaunchEnvironment

    private static let helpArguments = ["agent", "stdio", "--help"]

    private static func launchArguments(modelString: String?) -> [String] {
        let trimmed = modelString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return ["agent", "-m", trimmed, "stdio"]
        }
        return ["agent", "stdio"]
    }

    private let environmentProvider: EnvironmentProvider
    private let probeMutex = AsyncMutex()
    private let lock = NSLock()
    private var cachedLaunchByKey: [String: GrokBuildACPResolvedLaunch] = [:]

    convenience init(
        environmentProvider: @escaping @Sendable (_ enableDebugLogging: Bool) async -> [String: String]
    ) {
        self.init(launchEnvironmentProvider: { enableDebugLogging in
            await ACPLaunchEnvironment(environment: environmentProvider(enableDebugLogging))
        })
    }

    init(
        launchEnvironmentProvider: @escaping EnvironmentProvider = { enableDebugLogging in
            let result = await ProcessEnvironmentBuilder.build(
                ProcessEnvironmentRequest(
                    purpose: .acpAgent(providerID: ACPProviderID.grokBuild.rawValue),
                    enableDebugLogging: enableDebugLogging
                )
            )
            return ACPLaunchEnvironment(
                environment: result.environment,
                shellEnvironmentSource: result.shellEnvironmentSource
            )
        }
    ) {
        environmentProvider = launchEnvironmentProvider
    }

    func resolvedLaunch(for config: GrokBuildAgentConfig) throws -> GrokBuildACPResolvedLaunch {
        let key = cacheKey(for: config)
        if let cached = cachedLaunch(forKey: key) {
            do {
                try cached.executableIdentity.validateForTrustedPathLaunch(atPath: cached.command)
                return cached
            } catch {
                invalidate(key: key)
                throw error
            }
        }

        let launch = try resolveExplicitLaunch(for: config)
        cache(launch, key: key)
        return launch
    }

    func probeSupport(for config: GrokBuildAgentConfig) async throws -> ACPSupportResult {
        try await probeMutex.withLock { [self] in
            try await probeSupportSerially(for: config)
        }
    }

    private func probeSupportSerially(for config: GrokBuildAgentConfig) async throws -> ACPSupportResult {
        let key = cacheKey(for: config)
        invalidate(key: key)
        do {
            // Resolve from the current effective environment on every support check. The cache only
            // bridges this successful probe to the immediately following launch configuration.
            let launch = try await resolveLaunchForProbe(for: config)
            let processConfig = CLIProcessConfiguration(
                command: launch.command,
                additionalPaths: [],
                enableDebugLogging: config.enableDebugLogging,
                shellLookupMode: .fallbackOnly
            )
            let result = try await CLIProcessRunner(config: processConfig).run(
                args: Self.helpArguments,
                stdin: nil,
                outputMode: .none,
                timeout: 10,
                cancelChildOnTaskCancellation: true
            )
            guard result.status == 0 else {
                return .unsupported(
                    reason: "Grok Build ACP preflight failed: `grok agent stdio --help` exited with status \(result.status)."
                )
            }

            let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            guard "\(stdout)\n\(stderr)".localizedCaseInsensitiveContains("acp") else {
                return .unsupported(reason: "Installed Grok Build CLI does not advertise ACP support.")
            }

            try launch.executableIdentity.validateForTrustedPathLaunch(atPath: launch.command)
            cache(launch, key: key)
            return .supported
        } catch is CancellationError {
            invalidate(key: key)
            throw CancellationError()
        } catch {
            invalidate(key: key)
            return .unsupported(reason: error.localizedDescription)
        }
    }

    private func resolveLaunchForProbe(for config: GrokBuildAgentConfig) async throws -> GrokBuildACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        let launchEnvironment = await environmentProvider(config.enableDebugLogging)
        let environment = launchEnvironment.environment
        try Task.checkCancellation()
        if configuredCommand.contains("/") {
            return try resolveExplicitLaunch(
                for: config,
                environment: environment,
                shellEnvironmentSource: launchEnvironment.shellEnvironmentSource
            )
        }

        let effectiveHints = Self.effectiveSearchPaths(providerSpecificPaths: config.additionalPathHints)
        return try firstValidLaunch(
            candidates: launchCandidates(
                configuredCommand: configuredCommand,
                additionalPathHints: effectiveHints,
                environment: environment
            ),
            configuredCommand: configuredCommand,
            additionalPathHints: effectiveHints,
            modelString: config.modelString,
            shellEnvironmentSource: launchEnvironment.shellEnvironmentSource
        )
    }

    private func resolveExplicitLaunch(
        for config: GrokBuildAgentConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shellEnvironmentSource: ShellEnvironmentSource? = nil
    ) throws -> GrokBuildACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        guard configuredCommand.contains("/") else {
            throw GrokBuildACPLaunchResolutionError.environmentDiscoveryRequired(configuredCommand)
        }
        let effectiveHints = Self.effectiveSearchPaths(providerSpecificPaths: config.additionalPathHints)
        return try firstValidLaunch(
            candidates: [CommandPathResolver.expandPath(configuredCommand, environment: environment)],
            configuredCommand: configuredCommand,
            additionalPathHints: effectiveHints,
            modelString: config.modelString,
            shellEnvironmentSource: shellEnvironmentSource
        )
    }

    private func validatedConfiguredCommand(_ config: GrokBuildAgentConfig) throws -> String {
        let command = config.commandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw GrokBuildACPLaunchResolutionError.missingConfiguredCommand
        }
        return command
    }

    private func validatedLaunch(
        entryPath: String,
        configuredCommand: String,
        additionalPathHints: [String],
        modelString: String?
    ) throws -> GrokBuildACPResolvedLaunch {
        guard entryPath.hasPrefix("/") else {
            throw GrokBuildACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }
        let identity = try ExecutableFileIdentity.captureForTrustedPathLaunch(atPath: entryPath)

        return GrokBuildACPResolvedLaunch(
            command: identity.canonicalPath,
            arguments: Self.launchArguments(modelString: modelString),
            additionalPathHints: additionalPathHints,
            executableIdentity: identity
        )
    }

    private func launchCandidates(
        configuredCommand: String,
        additionalPathHints: [String],
        environment: [String: String]
    ) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func append(_ candidate: String) {
            let expanded = CommandPathResolver.expandPath(candidate, environment: environment)
            guard !expanded.isEmpty,
                  seen.insert(expanded).inserted
            else { return }
            candidates.append(expanded)
        }

        append(
            CommandPathResolver.resolve(
                configuredCommand,
                environment: environment,
                additionalPaths: additionalPathHints,
                preferredBasenames: [configuredCommand],
                shellLookupMode: .fallbackOnly
            )
        )
        for directory in CommandPathResolver.mergedPathComponents(
            environment: environment,
            additionalPaths: additionalPathHints
        ) {
            append((directory as NSString).appendingPathComponent(configuredCommand))
        }
        return candidates
    }

    private func firstValidLaunch(
        candidates: [String],
        configuredCommand: String,
        additionalPathHints: [String],
        modelString: String?,
        shellEnvironmentSource: ShellEnvironmentSource?
    ) throws -> GrokBuildACPResolvedLaunch {
        var failures: [String] = []
        for candidate in candidates {
            do {
                return try validatedLaunch(
                    entryPath: candidate,
                    configuredCommand: configuredCommand,
                    additionalPathHints: additionalPathHints,
                    modelString: modelString
                )
            } catch {
                failures.append("\(candidate): \(candidateDiagnostic(candidate, validationError: error))")
            }
        }
        if failures.isEmpty {
            throw GrokBuildACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }
        AgentCLILaunchDiagnostics.recordPathResolutionFailure(
            providerKind: .grokBuild,
            shellEnvironmentSource: shellEnvironmentSource,
            candidateCount: candidates.count
        )
        throw GrokBuildACPLaunchResolutionError.noValidLaunchCandidate(configuredCommand, failures, shellEnvironmentSource)
    }

    private func candidateDiagnostic(_ candidate: String, validationError: Error) -> String {
        guard candidate.hasPrefix("/") else { return "not an absolute path" }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) else {
            return "missing"
        }
        if isDirectory.boolValue { return "directory" }
        guard FileManager.default.isExecutableFile(atPath: candidate) else {
            return "not executable"
        }
        return validationError.localizedDescription
    }

    private func cachedLaunch(forKey key: String) -> GrokBuildACPResolvedLaunch? {
        lock.lock()
        defer { lock.unlock() }
        return cachedLaunchByKey[key]
    }

    private func cache(_ launch: GrokBuildACPResolvedLaunch, key: String) {
        lock.lock()
        cachedLaunchByKey[key] = launch
        lock.unlock()
    }

    private func invalidate(key: String) {
        lock.lock()
        cachedLaunchByKey.removeValue(forKey: key)
        lock.unlock()
    }

    private func cacheKey(for config: GrokBuildAgentConfig) -> String {
        ([config.commandName, config.modelString ?? ""] + config.additionalPathHints).joined(separator: "\u{1F}")
    }

    private static func effectiveSearchPaths(providerSpecificPaths: [String]) -> [String] {
        CLILaunchProfiles.providerSpecificPathsSupplementedWithNativeDefaults(providerSpecificPaths)
    }
}
