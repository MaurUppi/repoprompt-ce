import Foundation

protocol GrokBuildACPModelDiscoveryClient: Sendable {
    func discoverModels(workspacePath: String?) async throws -> ACPDiscoveredSessionModels?
}

struct GrokBuildACPControllerModelDiscoveryClient: GrokBuildACPModelDiscoveryClient {
    typealias ProviderFactory = @Sendable (_ agent: AgentProviderKind, _ modelString: String?) -> (any ACPAgentProvider)?
    typealias ControllerFactory = @Sendable (_ provider: any ACPAgentProvider, _ runRequest: ACPRunRequest) throws -> ACPAgentSessionController

    private let providerFactory: ProviderFactory
    private let controllerFactory: ControllerFactory

    init(
        providerFactory: @escaping ProviderFactory = { agent, modelString in
            if agent == .grokBuild {
                return GrokBuildACPAgentProvider(
                    config: GrokBuildAgentConfig(
                        enableDebugLogging: AgentRuntimeProviderService.enableDebugLogging,
                        modelString: modelString,
                        includeRepoPromptMCPServer: false
                    )
                )
            }
            return ACPAgentProviderFactory.makeProvider(for: agent, modelString: modelString)
        },
        controllerFactory: @escaping ControllerFactory = { provider, runRequest in
            try ACPAgentSessionController(provider: provider, runRequest: runRequest)
        }
    ) {
        self.providerFactory = providerFactory
        self.controllerFactory = controllerFactory
    }

    func discoverModels(workspacePath: String?) async throws -> ACPDiscoveredSessionModels? {
        let preferredModel = AgentModel.grokBuildDefault.rawValue
        let request = ACPRunRequest(
            agentKind: .grokBuild,
            modelString: preferredModel,
            workspacePath: workspacePath,
            resumeSessionID: nil,
            attachments: [],
            taskLabelKind: nil
        )
        guard let provider = providerFactory(.grokBuild, preferredModel) else { return nil }
        let support = try await provider.support(for: request)
        guard support == .supported else {
            throw AIProviderError.invalidConfiguration(
                detail: support.reason ?? "Grok Build ACP is not available."
            )
        }

        let controller = try controllerFactory(provider, request)
        do {
            _ = try await controller.bootstrap()
            try? await controller.setSessionModel(preferredModel)
            let snapshot = AgentACPModelRegistry.shared.currentSnapshot(for: .grokBuild)
            await controller.shutdown()
            return snapshot
        } catch {
            await controller.shutdown()
            throw error
        }
    }
}

/// Centralized polling service for Grok Build ACP dynamic model options.
actor GrokBuildACPModelPollingService {
    static let shared = GrokBuildACPModelPollingService(
        client: GrokBuildACPControllerModelDiscoveryClient()
    )

    struct Snapshot: Equatable {
        let models: ACPDiscoveredSessionModels
        let fetchedAt: Date
        let isLiveDiscovery: Bool
    }

    private let client: any GrokBuildACPModelDiscoveryClient
    private let intervalNanos: UInt64

    private var pollingTask: Task<Void, Never>?
    private var inFlightRefresh: Task<Bool, Never>?
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]
    private var latest: Snapshot?
    private var preferredWorkspacePath: String?
    private var isShutdown = false

    init(
        client: any GrokBuildACPModelDiscoveryClient,
        intervalNanos: UInt64 = 300_000_000_000
    ) {
        self.client = client
        self.intervalNanos = intervalNanos
    }

    func latestSnapshot() async -> Snapshot? {
        latest
    }

    func subscribe(workspacePath: String? = nil) -> AsyncStream<Snapshot> {
        if let workspacePath {
            preferredWorkspacePath = workspacePath
        }
        startPollingIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        if let latest {
            continuation.yield(latest)
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    func refreshNow(workspacePath: String? = nil) async -> Bool {
        if let workspacePath {
            preferredWorkspacePath = workspacePath
        }
        if let inFlightRefresh {
            return await inFlightRefresh.value
        }
        let task = Task<Bool, Never> { [client, preferredWorkspacePath] in
            do {
                guard let models = try await client.discoverModels(workspacePath: preferredWorkspacePath) else {
                    return false
                }
                await self.publish(
                    Snapshot(models: models, fetchedAt: Date(), isLiveDiscovery: true)
                )
                return true
            } catch {
                return false
            }
        }
        inFlightRefresh = task
        let ok = await task.value
        inFlightRefresh = nil
        return ok
    }

    func discoverOnce(workspacePath: String? = nil) async throws -> Snapshot? {
        if let workspacePath {
            preferredWorkspacePath = workspacePath
        }
        guard let models = try await client.discoverModels(workspacePath: preferredWorkspacePath) else {
            return nil
        }
        let snapshot = Snapshot(models: models, fetchedAt: Date(), isLiveDiscovery: true)
        await publish(snapshot)
        return snapshot
    }

    func shutdown() {
        isShutdown = true
        pollingTask?.cancel()
        pollingTask = nil
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func startPollingIfNeeded() {
        guard !isShutdown, pollingTask == nil else { return }
        pollingTask = Task { [intervalNanos] in
            while !Task.isCancelled {
                _ = await refreshNow()
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }
    }

    private func publish(_ snapshot: Snapshot) {
        latest = snapshot
        AgentACPModelRegistry.shared.updateDiscoveredModels(snapshot.models, for: .grokBuild)
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
        if continuations.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }
}
