import XCTest
@testable import RepoPromptApp

final class GrokBuildACPLaunchResolverTests: XCTestCase {
    func testLaunchArgumentsPlaceModelBeforeStdio() throws {
        let resolver = GrokBuildACPLaunchResolver(environmentProvider: { _ in
            ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        })

        // Use explicit absolute path if grok exists (thin PATH + absolute command).
        let grokPath = (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/grok")
        guard FileManager.default.isExecutableFile(atPath: grokPath) else {
            throw XCTSkip("local grok executable not present at \(grokPath)")
        }

        let launch = try resolver.resolvedLaunch(
            for: GrokBuildAgentConfig(commandName: grokPath, modelString: "grok-4.5")
        )
        XCTAssertEqual(launch.arguments, ["agent", "-m", "grok-4.5", "stdio"])
        XCTAssertTrue(launch.command.hasPrefix("/"))
    }

    func testLaunchArgumentsWithoutModel() throws {
        let grokPath = (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/grok")
        guard FileManager.default.isExecutableFile(atPath: grokPath) else {
            throw XCTSkip("local grok executable not present at \(grokPath)")
        }
        let resolver = GrokBuildACPLaunchResolver(environmentProvider: { _ in
            ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        })
        let launch = try resolver.resolvedLaunch(
            for: GrokBuildAgentConfig(commandName: grokPath, modelString: nil)
        )
        XCTAssertEqual(launch.arguments, ["agent", "stdio"])
    }

    func testProbeSupportAcceptsStdioHelpWithoutLiteralACPToken() async throws {
        let grokPath = (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/grok")
        guard FileManager.default.isExecutableFile(atPath: grokPath) else {
            throw XCTSkip("local grok executable not present at \(grokPath)")
        }
        let resolver = GrokBuildACPLaunchResolver(environmentProvider: { _ in
            [
                "PATH": "/usr/bin:/bin",
                "HOME": NSHomeDirectory()
            ]
        })
        let result = try await resolver.probeSupport(
            for: GrokBuildAgentConfig(commandName: grokPath)
        )
        guard case .supported = result else {
            XCTFail("expected .supported, got \(result)")
            return
        }
    }
}
