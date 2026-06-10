import Foundation
import MCP
@testable import RepoPromptMCP
import XCTest

#if DEBUG
    final class InteractiveMCPClientSessionCancellationTests: XCTestCase {
        func testTimeoutSendsMCPRequestCancellationAndReturnsTimeout() async throws {
            let timeoutTrigger = CLIAsyncSignal()
            let fixture = try await makeFixture(
                cancellationBehavior: .ignoreUntilReleased,
                timeoutSleep: { _ in
                    await timeoutTrigger.wait()
                }
            )
            do {
                let call = Task {
                    try await fixture.session.callTool(
                        name: "slow_tool",
                        arguments: nil,
                        timeout: .seconds(42)
                    )
                }
                await fixture.handlerStarted.wait()
                await timeoutTrigger.signal()

                do {
                    _ = try await call.value
                    XCTFail("Expected tool timeout")
                } catch let error as InteractiveSessionError {
                    guard case let .toolCallTimeout(toolName, seconds) = error else {
                        XCTFail("Expected tool timeout, got \(error)")
                        await fixture.cleanup()
                        return
                    }
                    XCTAssertEqual(toolName, "slow_tool")
                    XCTAssertEqual(seconds, 42)
                }

                await fixture.handlerCancelled.wait()
                await fixture.ignoredCancellationRelease.signal()
                await fixture.cleanup()
            } catch {
                await fixture.cleanup()
                throw error
            }
        }

        func testCallerCancellationSendsMCPRequestCancellationAndReturnsCancellation() async throws {
            let fixture = try await makeFixture()
            do {
                let call = Task {
                    try await fixture.session.callTool(
                        name: "slow_tool",
                        arguments: nil,
                        timeout: .none
                    )
                }
                await fixture.handlerStarted.wait()
                call.cancel()

                do {
                    _ = try await call.value
                    XCTFail("Expected caller cancellation")
                } catch is CancellationError {
                    // Expected.
                }

                await fixture.handlerCancelled.wait()
                await fixture.cleanup()
            } catch {
                await fixture.cleanup()
                throw error
            }
        }

        private func makeFixture(
            cancellationBehavior: CLICancellationBehavior = .cooperative,
            timeoutSleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        ) async throws -> CLISessionCancellationFixture {
            let transports = await InMemoryTransport.createConnectedPair()
            let handlerStarted = CLIAsyncSignal()
            let handlerCancelled = CLIAsyncSignal()
            let ignoredCancellationRelease = CLIAsyncSignal()
            let cancellationSuspension = CLICancellationSuspension()
            let server = Server(
                name: "CLI cancellation test server",
                version: "1.0",
                capabilities: .init(tools: .init())
            )
            await server.withMethodHandler(CallTool.self) { _ in
                await handlerStarted.signal()
                do {
                    try await cancellationSuspension.wait()
                    return .init(
                        content: [.text(text: "unexpected", annotations: nil, _meta: nil)],
                        isError: false
                    )
                } catch is CancellationError {
                    await handlerCancelled.signal()
                    switch cancellationBehavior {
                    case .cooperative:
                        throw CancellationError()
                    case .ignoreUntilReleased:
                        await ignoredCancellationRelease.wait()
                        return .init(
                            content: [.text(text: "late result", annotations: nil, _meta: nil)],
                            isError: false
                        )
                    }
                }
            }
            try await server.start(transport: transports.server)

            let client = Client(name: "CLI cancellation test client", version: "1.0")
            _ = try await client.connect(transport: transports.client)
            let session = InteractiveMCPClientSession(
                connectedClientForTesting: client,
                timeoutSleep: timeoutSleep
            )
            return CLISessionCancellationFixture(
                client: client,
                server: server,
                session: session,
                handlerStarted: handlerStarted,
                handlerCancelled: handlerCancelled,
                ignoredCancellationRelease: ignoredCancellationRelease
            )
        }
    }

    private enum CLICancellationBehavior {
        case cooperative
        case ignoreUntilReleased
    }

    private struct CLISessionCancellationFixture {
        let client: Client
        let server: Server
        let session: InteractiveMCPClientSession
        let handlerStarted: CLIAsyncSignal
        let handlerCancelled: CLIAsyncSignal
        let ignoredCancellationRelease: CLIAsyncSignal

        func cleanup() async {
            await ignoredCancellationRelease.signal()
            await client.disconnect()
            await server.stop()
        }
    }

    private actor CLIAsyncSignal {
        private var signalled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func signal() {
            guard !signalled else { return }
            signalled = true
            let waiters = waiters
            self.waiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        func wait() async {
            guard !signalled else { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private actor CLICancellationSuspension {
        private struct Waiter {
            let id: UUID
            let continuation: CheckedContinuation<Void, Error>
        }

        private var waiter: Waiter?

        func wait() async throws {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiter = Waiter(id: waiterID, continuation: continuation)
                }
            } onCancel: {
                Task { await self.cancel(waiterID) }
            }
        }

        private func cancel(_ waiterID: UUID) {
            guard let waiter, waiter.id == waiterID else { return }
            self.waiter = nil
            waiter.continuation.resume(throwing: CancellationError())
        }
    }
#endif
