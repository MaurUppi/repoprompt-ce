@testable import RepoPromptApp
import XCTest

final class GrokBuildOracleModelCatalogTests: XCTestCase {
    func testGrokBuildCustomRawValueRoundTrip() {
        let model = AIModel.grokBuildCustom(name: "grok-4.5:medium")
        XCTAssertEqual(model.rawValue, "grokbuild_custom_grok-4.5:medium")
        XCTAssertEqual(model.providerType, .grokBuild)
        XCTAssertEqual(model.modelName, "grok-4.5:medium")
        let parsed = AIModel.fromModelName(model.rawValue)
        XCTAssertEqual(parsed, model)
    }

    func testModelsForProviderIncludesEffortVariants() {
        let models = AIModel.modelsForProvider(.grokBuild)
        let names = Set(models.map(\.modelName))
        XCTAssertTrue(names.contains("grok-4.5:high"))
        XCTAssertTrue(names.contains("grok-4.5:medium"))
        XCTAssertTrue(names.contains("grok-4.5:low"))
        XCTAssertTrue(models.allSatisfy { $0.providerType == .grokBuild })
    }

    func testProviderDisplayNameDistinctFromHTTPGrok() {
        XCTAssertEqual(AIProviderType.grok.displayName, "Grok (xAI)")
        XCTAssertEqual(AIProviderType.grokBuild.displayName, "Grok Build")
        XCTAssertNotEqual(AIProviderType.grok, AIProviderType.grokBuild)
    }
}
