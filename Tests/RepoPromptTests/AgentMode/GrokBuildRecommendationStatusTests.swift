@testable import RepoPromptApp
import XCTest

@MainActor
final class GrokBuildRecommendationStatusTests: XCTestCase {
    func testProviderStatusSnapshotIncludesGrokBuildInReadyAndFilter() {
        let ready = ProviderStatusSnapshot(
            claudeCodeCLI: .notConfigured,
            codexCLI: .notConfigured,
            cursorCLI: .notConfigured,
            grokBuildCLI: .ready,
            openAI: .notConfigured
        )
        XCTAssertTrue(ready.hasAnyCLIAgentReady)
        XCTAssertTrue(ready.hasAnyReadyProvider)

        let filteredOut = ready.filtered(to: [.claudeCode, .codex, .cursor, .openAI])
        XCTAssertEqual(filteredOut.grokBuildCLI, .notConfigured)
        XCTAssertFalse(filteredOut.hasAnyCLIAgentReady)

        let filteredIn = ready.filtered(to: [.grokBuild])
        XCTAssertEqual(filteredIn.grokBuildCLI, .ready)
        XCTAssertTrue(filteredIn.hasAnyCLIAgentReady)
    }

    func testContextBuilderRecommendationPrefersGrokAfterCursor() {
        let onlyGrok = ProviderStatusSnapshot(
            claudeCodeCLI: .notConfigured,
            codexCLI: .notConfigured,
            cursorCLI: .notConfigured,
            grokBuildCLI: .ready,
            openAI: .notConfigured
        )
        let rec = AutoRecommendationEngine.contextBuilderRecommendation(status: onlyGrok)
        XCTAssertEqual(rec?.recommendedAgent, .grokBuild)
        XCTAssertEqual(rec?.recommendedModel, .grokBuildDefault)

        let cursorAndGrok = ProviderStatusSnapshot(
            claudeCodeCLI: .notConfigured,
            codexCLI: .notConfigured,
            cursorCLI: .ready,
            grokBuildCLI: .ready,
            openAI: .notConfigured
        )
        let cursorFirst = AutoRecommendationEngine.contextBuilderRecommendation(status: cursorAndGrok)
        XCTAssertEqual(cursorFirst?.recommendedAgent, .cursor)
    }

    func testContextBuilderRecommendationStillPrefersCodexOverGrok() {
        let status = ProviderStatusSnapshot(
            claudeCodeCLI: .notConfigured,
            codexCLI: .ready,
            cursorCLI: .ready,
            grokBuildCLI: .ready,
            openAI: .notConfigured
        )
        let rec = AutoRecommendationEngine.contextBuilderRecommendation(status: status)
        XCTAssertEqual(rec?.recommendedAgent, .codexExec)
    }

    func testMcpAgentAvailabilityReflectsGrokBuildReady() {
        // AvailabilityContext used by resolveTaskLabel when only Grok is connected.
        let availability = AgentModelCatalog.AvailabilityContext(
            claudeCodeAvailable: false,
            codexAvailable: false,
            openCodeAvailable: false,
            cursorAvailable: false,
            grokBuildAvailable: true
        )
        XCTAssertTrue(AgentModelCatalog.isAgentAvailable(.grokBuild, availability: availability))

        let explore = AgentModelCatalog.resolveTaskLabel("explore", availability: availability)
        XCTAssertEqual(explore?.agent, .grokBuild)
        XCTAssertNotNil(explore?.modelRaw)
    }

    func testChatBackendKindGrokBuildDisplayName() {
        XCTAssertEqual(ChatBackendKind.grokBuild.displayName, "Grok Build")
        let option = ChatBackendOption(
            kind: .grokBuild,
            displayName: "Grok Build",
            modelString: AIModel.grokBuildCustom(name: "grok-4.5:medium").rawValue,
            description: "test",
            tradeoffs: []
        )
        let rec = ChatModelRecommendation(
            defaultBackend: .grokBuild,
            codexOption: nil,
            openAIOption: nil,
            claudeCodeOption: nil,
            grokBuildOption: option,
            priorityPath: ["Grok Build"]
        )
        XCTAssertEqual(rec.option(for: .grokBuild)?.modelString, "grokbuild_custom_grok-4.5:medium")
        XCTAssertEqual(rec.availableOptions.count, 1)
    }
}
