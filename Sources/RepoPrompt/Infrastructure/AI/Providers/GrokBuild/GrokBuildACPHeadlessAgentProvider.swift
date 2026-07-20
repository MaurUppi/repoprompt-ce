import Foundation

/// Headless/discovery adapter for Grok Build's ACP runtime.
final class GrokBuildACPHeadlessAgentProvider: HeadlessAgentProvider {
    typealias ProviderFactory = @Sendable (_ config: GrokBuildAgentConfig) -> any ACPAgentProvider
    typealias ControllerFactory = ACPHeadlessAgentProviderBridge.ControllerFactory

    private let config: GrokBuildAgentConfig
    private let bridge: ACPHeadlessAgentProviderBridge

    #if DEBUG
        var test_config: GrokBuildAgentConfig {
            config
        }
    #endif

    init(
        config: GrokBuildAgentConfig,
        workspacePath: String? = nil,
        providerFactory: ProviderFactory? = nil,
        controllerFactory: @escaping ControllerFactory = { provider, request, diagnosticSink in
            try ACPAgentSessionController(
                provider: provider,
                runRequest: request,
                diagnosticSink: diagnosticSink
            )
        }
    ) {
        self.config = config
        let resolvedProviderFactory = providerFactory ?? { config in
            GrokBuildACPAgentProvider(config: config)
        }
        bridge = ACPHeadlessAgentProviderBridge(
            providerName: "Grok Build",
            makeProvider: {
                resolvedProviderFactory(config)
            },
            makeRequest: { message, _ in
                ACPRunRequest(
                    agentKind: .grokBuild,
                    modelString: config.modelString,
                    workspacePath: workspacePath,
                    resumeSessionID: message.resumeSessionID,
                    attachments: [],
                    taskLabelKind: nil
                )
            },
            makeController: controllerFactory,
            beforePrompt: { controller, _ in
                if let model = Self.selectedModelToApply(config: config) {
                    let specifier = GrokBuildModelSpecifier(raw: model)
                    let base = specifier.runtimeModelID ?? model
                    try await controller.setSessionModel(base)
                    if let modeID = specifier.sessionModeIDToApply {
                        try await controller.setSessionMode(modeID)
                    }
                }
            },
            approvalPolicy: .declineUnsupported
        )
    }

    func streamAgentMessage(
        _ message: AgentMessage,
        runID: UUID? = nil
    ) async throws -> AsyncThrowingStream<AIStreamResult, Error> {
        try await bridge.streamAgentMessage(message, runID: runID)
    }

    func dispose() async {
        await bridge.dispose()
    }

    private static func selectedModelToApply(config: GrokBuildAgentConfig) -> String? {
        guard let model = config.modelString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty,
              model.caseInsensitiveCompare(AgentModel.defaultModel.rawValue) != .orderedSame
        else {
            return nil
        }
        if model.caseInsensitiveCompare(AgentModel.grokBuildDefault.rawValue) == .orderedSame {
            return model
        }
        guard AgentACPModelRegistry.shared.resolvedSnapshot(for: .grokBuild)?.contains(rawModel: model) == true else {
            return nil
        }
        return model
    }
}
