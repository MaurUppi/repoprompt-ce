@testable import RepoPromptApp
import XCTest

final class MCPClientIdentityGrokFamilyTests: XCTestCase {
    func testGrokVersionedBinaryNameMapsToGrokFamily() {
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("grok"), "grok")
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("grok-0.2.106-macos-aarch64"), "grok")
        XCTAssertEqual(MCPClientIdentity.storageKey("grok-0.2.106-macos-aarch64"), "grok")
        XCTAssertTrue(MCPClientIdentity.matches("grok-0.2.106-macos-aarch64", "grok"))
        XCTAssertTrue(MCPClientIdentity.matches("grok", AgentProviderKind.grokBuildMCPClientID))
        XCTAssertTrue(MCPClientIdentity.isHeadlessAgentClient("grok-0.2.106-macos-aarch64"))
    }

    func testGrokShellServerClientNameMapsToGrokFamily() {
        // Live Grok ACP inject clientInfo.name for session mcpServers entry "RepoPromptCE".
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("grok-shell-RepoPromptCE"), "grok")
        XCTAssertEqual(MCPClientIdentity.storageKey("grok-shell-RepoPromptCE"), "grok")
        XCTAssertTrue(MCPClientIdentity.matches("grok-shell-RepoPromptCE", "grok"))
        XCTAssertTrue(MCPClientIdentity.matches("grok-shell-RepoPromptCE", AgentProviderKind.grokBuildMCPClientID))
        XCTAssertTrue(MCPClientIdentity.isHeadlessAgentClient("grok-shell-RepoPromptCE"))
    }

    func testOpenCodeFamilyCanonicalization() {
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("opencode"), "opencode")
        XCTAssertTrue(MCPClientIdentity.matches("opencode", "opencode"))
    }
}
