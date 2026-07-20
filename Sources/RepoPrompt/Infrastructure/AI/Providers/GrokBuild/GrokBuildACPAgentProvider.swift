import Foundation

struct GrokBuildACPAgentProvider: ACPAgentProvider {
    private let config: GrokBuildAgentConfig
    private let repoPromptMCPConfiguration: RepoPromptMCPServerConfiguration
    private let launchResolver: GrokBuildACPLaunchResolver

    #if DEBUG
        var test_config: GrokBuildAgentConfig {
            config
        }
    #endif

    init(
        config: GrokBuildAgentConfig,
        repoPromptMCPConfiguration: RepoPromptMCPServerConfiguration = .repoPrompt,
        launchResolver: GrokBuildACPLaunchResolver = GrokBuildACPLaunchResolver()
    ) {
        self.config = config
        self.repoPromptMCPConfiguration = repoPromptMCPConfiguration
        self.launchResolver = launchResolver
    }

    var providerID: ACPProviderID {
        .grokBuild
    }

    func support(for _: ACPRunRequest) async throws -> ACPSupportResult {
        try await launchResolver.probeSupport(for: config)
    }

    func makeLaunchConfiguration(for request: ACPRunRequest) throws -> ACPLaunchConfiguration {
        let workingDirectory = try standardizedWorkingDirectory(from: request.workspacePath)
        let resolvedLaunch = try launchResolver.resolvedLaunch(for: config)
        if config.includeRepoPromptMCPServer {
            try repoPromptMCPConfiguration.validateACPLaunchCommand(workingDirectory: workingDirectory)
        }

        return ACPLaunchConfiguration(
            providerID: providerID,
            command: resolvedLaunch.command,
            arguments: resolvedLaunch.arguments,
            environment: [:],
            workingDirectory: workingDirectory,
            additionalPathHints: resolvedLaunch.additionalPathHints,
            enableDebugLogging: config.enableDebugLogging,
            expectedExecutableIdentity: resolvedLaunch.executableIdentity
        )
    }

    func makeSessionConfiguration(
        for request: ACPRunRequest,
        mcpServer _: RepoPromptMCPServerConfiguration
    ) throws -> ACPSessionConfiguration {
        let mode: ACPSessionConfiguration.Mode = if let resume = request.resumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    !resume.isEmpty
        {
            .load(existingSessionID: resume)
        } else {
            .new
        }

        return try ACPSessionConfiguration(
            mode: mode,
            workingDirectory: standardizedWorkingDirectory(from: request.workspacePath),
            mcpServers: config.includeRepoPromptMCPServer ? [repoPromptMCPConfiguration] : []
        )
    }

    func buildPromptBlocks(
        for message: AgentMessage,
        request: ACPRunRequest
    ) throws -> [[String: Any]] {
        let isFollowUp = request.resumeSessionID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let systemPrompt = message.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = message.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String = if isFollowUp || systemPrompt.isEmpty {
            userMessage.isEmpty ? message.userMessage : userMessage
        } else if userMessage.isEmpty {
            systemPrompt
        } else {
            "\(systemPrompt)\n\n\(userMessage)"
        }

        return try ACPPromptContentBuilder.blocks(
            text: text,
            attachments: request.attachments
        )
    }

    func normalizeSessionUpdate(
        _ payload: [String: Any],
        sessionID _: String
    ) -> [NormalizedAgentRuntimeEvent] {
        ACPDefaultSessionUpdateNormalizer.normalize(payload, providerID: .grokBuild)
    }

    func preferredAuthMethodID(context: ACPAuthenticationContext) -> String? {
        context.authMethodIDs.first {
            $0.caseInsensitiveCompare("cached_token") == .orderedSame
        }
    }

    func normalizeError(_ error: Error) -> Error {
        if error is AIProviderError {
            return error
        }
        if let runnerError = error as? CLIProcessRunnerError,
           case .commandNotFound = runnerError
        {
            return AIProviderError.invalidConfiguration(
                detail: "Grok Build CLI was not found. Install Grok Build and ensure `grok` is available on your login-shell PATH."
            )
        }
        if error is GrokBuildACPLaunchResolutionError || error is ExecutableFileIdentityError {
            return AIProviderError.invalidConfiguration(detail: error.localizedDescription)
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = description.lowercased()
        if lower.contains("not authenticated")
            || lower.contains("unauthenticated")
            || lower.contains("cached_token")
            || lower.contains("login")
        {
            return AIProviderError.invalidConfiguration(
                detail: "Grok Build is not authenticated. Run `grok login`, then retry Connect."
            )
        }
        return AIProviderError.apiError(source: error)
    }

    private func standardizedWorkingDirectory(from workspacePath: String?) throws -> String {
        if let cwd = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            return URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoPromptGrokBuildACPPreflight", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url.standardizedFileURL.path
    }
}
