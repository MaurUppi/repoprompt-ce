@testable import RepoPromptApp
import XCTest

final class GrokBuildModelSpecifierTests: XCTestCase {
    func testBareBaseDefaultsEffortNilAndRuntimeModel() {
        let specifier = GrokBuildModelSpecifier(raw: "grok-4.5")
        XCTAssertEqual(specifier.runtimeModelID, "grok-4.5")
        XCTAssertNil(specifier.effort)
        XCTAssertEqual(specifier.sessionModeIDToApply, GrokBuildReasoningEffort.defaultEffort.sessionModeID)
    }

    func testCompoundEncodesAndParsesEffort() {
        let raw = GrokBuildModelSpecifier.encodedRaw(baseModelRaw: "grok-4.5", effort: .medium)
        XCTAssertEqual(raw, "grok-4.5:medium")
        let specifier = GrokBuildModelSpecifier(raw: raw)
        XCTAssertEqual(specifier.runtimeModelID, "grok-4.5")
        XCTAssertEqual(specifier.effort, .medium)
        XCTAssertEqual(specifier.sessionModeIDToApply, "medium")
    }

    func testCatalogExpandsEffortOptionsWhenAvailable() {
        let options = AgentModelCatalog.options(
            for: .grokBuild,
            availability: AgentModelCatalog.AvailabilityContext(grokBuildAvailable: true)
        )
        let raws = Set(options.map { $0.rawValue.lowercased() })
        XCTAssertTrue(raws.contains("grok-4.5:high"))
        XCTAssertTrue(raws.contains("grok-4.5:medium"))
        XCTAssertTrue(raws.contains("grok-4.5:low"))
        XCTAssertEqual(options.count, 3)
    }

    func testIsValidAcceptsBareAndCompound() {
        let availability = AgentModelCatalog.AvailabilityContext(grokBuildAvailable: true)
        XCTAssertTrue(AgentModelCatalog.isValid(rawModel: "grok-4.5", for: .grokBuild, availability: availability))
        XCTAssertTrue(AgentModelCatalog.isValid(rawModel: "grok-4.5:low", for: .grokBuild, availability: availability))
        XCTAssertFalse(AgentModelCatalog.isValid(rawModel: "unknown-model", for: .grokBuild, availability: availability))
    }
}
