//
//  NativeMessagingHostSessionTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import WebExtensions
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Exercises `NativeMessagingHostSession` against fake hosts, which are Python scripts that
/// speak the native messaging wire format. Case-by-case scripts stand in for the ways a host
/// can end.
@MainActor
final class NativeMessagingHostSessionTests: XCTestCase {

    private static let callerOrigin = "chrome-extension://nngceckbapebfimnlniiiahkandclblb/"

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeMessagingHostSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTSkipIf(NSApp.isSandboxed, "A sandboxed host can't launch native messaging hosts")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func testWhenHostEchoesAMessageThenTheSessionDeliversIt() throws {
        let executable = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let session = makeSession(executable: executable)

        let received = expectation(description: "message received")
        var message: [String: String]?
        session.messageHandler = { payload in
            message = payload as? [String: String]
            received.fulfill()
        }

        let terminated = expectation(description: "termination handler is not called after stop()")
        terminated.isInverted = true
        session.terminationHandler = { _ in terminated.fulfill() }

        try session.start()
        try session.send(["command": "biometricUnlock"])

        wait(for: [received], timeout: 10)
        XCTAssertEqual(message, ["command": "biometricUnlock"])

        session.stop()

        wait(for: [terminated], timeout: 1)
        XCTAssertTrue(waitForNoRunningHosts(), "The host process outlived stop()")
    }

    func testWhenManyMessagesAreSentInABurstThenTheHostReceivesThemInOrder() throws {
        let executable = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let session = makeSession(executable: executable)

        let count = 50
        let received = expectation(description: "every message echoed back")
        received.expectedFulfillmentCount = count
        var sequence: [Int] = []
        session.messageHandler = { payload in
            if let message = payload as? [String: Any], let index = message["index"] as? Int {
                sequence.append(index)
            }
            received.fulfill()
        }

        try session.start()
        for index in 0..<count {
            // Each message carries a payload large enough that interleaved writes would corrupt a
            // frame, not only reorder it.
            try session.send(["index": index, "padding": Array(repeating: index, count: 512)] as [String: Any])
        }

        wait(for: [received], timeout: 10)
        XCTAssertEqual(sequence, Array(0..<count), "The host saw the messages in a different order than they were sent")

        session.stop()
        XCTAssertTrue(waitForNoRunningHosts(), "The host process outlived stop()")
    }

    func testWhenHostSendsAMessageAndExitsThenTheMessageArrivesBeforeTermination() throws {
        let executable = try makeHost(named: "farewell-host", script: Self.farewellHostScript)
        let session = makeSession(executable: executable)

        let finished = expectation(description: "session finished")
        var events: [String] = []
        var terminationError: Error?

        session.messageHandler = { message in
            let dictionary = message as? [String: String]
            events.append("message:\(dictionary?["type"] ?? "?")")
        }
        session.terminationHandler = { error in
            terminationError = error
            events.append("termination")
            finished.fulfill()
        }

        try session.start()

        wait(for: [finished], timeout: 10)
        XCTAssertEqual(events, ["message:disconnected", "termination"])
        XCTAssertNil(terminationError)
    }

    /// A pipe hands over whatever the host has written so far, which can be several messages at
    /// once or part of one.
    func testWhenHostWritesMessagesTogetherAndInPiecesThenTheSessionDeliversEachOnce() throws {
        let executable = try makeHost(named: "chunked-host", script: Self.chunkedHostScript)
        let session = makeSession(executable: executable)

        let finished = expectation(description: "session finished")
        var indices: [Int] = []
        session.messageHandler = { message in
            if let index = (message as? [String: Int])?["index"] {
                indices.append(index)
            }
        }
        session.terminationHandler = { error in
            XCTAssertNil(error)
            finished.fulfill()
        }

        try session.start()

        wait(for: [finished], timeout: 10)
        XCTAssertEqual(indices, [1, 2, 3])
    }

    func testWhenHostWritesAMessageAndThenGarbageTogetherThenTheMessageArrivesBeforeTheError() throws {
        let executable = try makeHost(named: "garbage-host", script: Self.garbageHostScript)
        let session = makeSession(executable: executable)

        let finished = expectation(description: "session finished")
        var events: [String] = []
        session.messageHandler = { message in
            events.append("message:\((message as? [String: Int])?["index"] ?? -1)")
        }
        session.terminationHandler = { error in
            events.append(error == nil ? "termination" : "error")
            finished.fulfill()
        }

        try session.start()

        wait(for: [finished], timeout: 10)
        XCTAssertEqual(events, ["message:1", "error"])
    }

    /// A host that fails has to be told apart from one that ended normally, and the exit
    /// status is the only sign. The output pipe reaches EOF at about the same moment, so this
    /// also guards the race between the two.
    func testWhenHostExitsWithFailureThenTerminationReportsHostEnded() throws {
        let executable = try makeHost(named: "failing-host", script: Self.failingHostScript)
        let session = makeSession(executable: executable)

        let finished = expectation(description: "session finished")
        var terminationError: Error?
        session.messageHandler = { _ in XCTFail("The host sends nothing") }
        session.terminationHandler = { error in
            terminationError = error
            finished.fulfill()
        }

        try session.start()

        wait(for: [finished], timeout: 10)
        guard let sessionError = terminationError as? NativeMessagingHostSession.SessionError,
              case .hostEnded = sessionError else {
            return XCTFail("Expected hostEnded, got \(String(describing: terminationError))")
        }
    }

    func testWhenHostExitsButLeavesOutputOpenThenTheStallBackstopFinishesTheSession() throws {
        let executable = try makeHost(named: "leaky-host", script: Self.leakyHostScript)
        let session = makeSession(executable: executable)

        let finished = expectation(description: "session finished")
        var terminationError: Error?
        session.terminationHandler = { error in
            terminationError = error
            finished.fulfill()
        }

        try session.start()

        // The pipe never reaches EOF, so only the two-second backstop can end this.
        wait(for: [finished], timeout: 5)
        XCTAssertNil(terminationError)
    }

    func testWhenHostDeclaresAnOversizedMessageThenTerminationReportsAFramingError() throws {
        let executable = try makeHost(named: "oversized-host", script: Self.oversizedHostScript)
        let session = makeSession(executable: executable)

        let finished = expectation(description: "session finished")
        var terminationError: Error?
        session.messageHandler = { _ in XCTFail("The host sends no valid message") }
        session.terminationHandler = { error in
            terminationError = error
            finished.fulfill()
        }

        try session.start()

        wait(for: [finished], timeout: 10)
        XCTAssertEqual(terminationError as? NativeMessagingFramingError,
                       .messageTooLarge(length: 100 * 1024 * 1024))
    }

    /// An extension may retry a port for as long as its companion app stays away, so a refused
    /// connection happens over and over. Every attempt has to end on its own and leave nothing behind.
    func testWhenTheSameHostIsConnectedRepeatedlyThenEverySessionFinishesAndLeavesNoProcess() throws {
        let executable = try makeHost(named: "farewell-host", script: Self.farewellHostScript)

        for attempt in 1...5 {
            let session = makeSession(executable: executable)
            let finished = expectation(description: "session \(attempt) finished")
            var messageCount = 0

            session.messageHandler = { _ in messageCount += 1 }
            session.terminationHandler = { error in
                XCTAssertNil(error, "Attempt \(attempt) ended with \(String(describing: error))")
                finished.fulfill()
            }

            try session.start()
            wait(for: [finished], timeout: 10)
            XCTAssertEqual(messageCount, 1, "Attempt \(attempt) lost the host's last message")

            session.stop()
        }

        XCTAssertTrue(waitForNoRunningHosts(), "A host process survived the reconnect loop")
    }

    // MARK: - One-shot exchange

    func testWhenHostStopsReadingThenMessageCountOverflowStopsTheSession() throws {
        let executable = try makeHost(named: "stalled-host", script: Self.stalledHostScript)
        let session = NativeMessagingHostSession(hostName: "test", extensionIdentifier: "test-extension",
                                                 executable: executable, callerOrigin: Self.callerOrigin,
                                                 maximumPendingMessages: 1)
        defer { session.stop() }
        var terminationCount = 0
        session.terminationHandler = { error in
            guard let sessionError = error as? NativeMessagingHostSession.SessionError,
                  case .pendingMessagesLimitExceeded = sessionError else {
                return XCTFail("Expected a queue overflow, got \(String(describing: error))")
            }
            terminationCount += 1
        }
        try session.start()
        try session.send(["payload": String(repeating: "x", count: 256 * 1024)])

        XCTAssertThrowsError(try session.send(["command": "ping"]))
        XCTAssertThrowsError(try session.send(["command": "ping"]))
        XCTAssertEqual(terminationCount, 1)
        XCTAssertTrue(waitForNoRunningHosts())
    }

    func testWhenHostStopsReadingThenAggregateByteOverflowStopsTheSession() throws {
        let executable = try makeHost(named: "stalled-host", script: Self.stalledHostScript)
        let message = ["payload": String(repeating: "x", count: 256 * 1024)]
        let size = try NativeMessagingFraming.encode(message).count
        let session = NativeMessagingHostSession(hostName: "test", extensionIdentifier: "test-extension",
                                                 executable: executable, callerOrigin: Self.callerOrigin,
                                                 maximumPendingBytes: size)
        defer { session.stop() }
        try session.start()
        try session.send(message)

        XCTAssertThrowsError(try session.send(message)) { error in
            guard let sessionError = error as? NativeMessagingHostSession.SessionError,
                  case .pendingMessagesLimitExceeded = sessionError else {
                return XCTFail("Expected a queue overflow, got \(error)")
            }
        }
        XCTAssertTrue(waitForNoRunningHosts())
    }

    func testWhenWritesCompleteThenQueueCapacityCanBeReused() throws {
        let executable = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let session = NativeMessagingHostSession(hostName: "test", extensionIdentifier: "test-extension",
                                                 executable: executable, callerOrigin: Self.callerOrigin,
                                                 maximumPendingMessages: 1)
        defer { session.stop() }
        try session.start()

        for index in 0..<3 {
            let received = expectation(description: "reply \(index)")
            session.messageHandler = { message in
                XCTAssertEqual((message as? [String: Int])?["index"], index)
                received.fulfill()
            }
            try session.send(["index": index])
            wait(for: [received], timeout: 5)
        }
    }

    func testWhenHostWritesLargeStderrThenItIsDrainedWithoutBlockingReplies() throws {
        let executable = try makeHost(named: "stderr-host", script: Self.framingPreamble + """
        sys.stderr.write('sensitive-host-output' * 100000)
        sys.stderr.flush()
        write_frame(b'{"ready":true}')
        """)
        let session = makeSession(executable: executable)
        defer { session.stop() }
        let received = expectation(description: "reply after stderr")
        session.messageHandler = { message in
            XCTAssertEqual((message as? [String: Bool])?["ready"], true)
            received.fulfill()
        }

        try session.start()

        wait(for: [received], timeout: 10)
    }

    @available(macOS 15.4, *)
    func testWhenPersistentPortIsOpenThenOneShotRequestsShareItsLimitAndDisconnectReleasesCapacity() async throws {
        let context = try await makeExtensionContext(backgroundScript: """
        const api = globalThis.chrome || globalThis.browser;
        globalThis.testPort = api.runtime.connectNative("echo");
        testPort.onMessage.addListener(() => testPort.disconnect());
        """)
        let echo = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let handler = makeHandler(context: context, silent: echo, echo: echo,
                                  maximumSessionsPerExtension: 1, maximumSessions: 1)
        let connected = expectation(description: "persistent port connected")
        let disconnected = expectation(description: "extension disconnected its port")
        let delegate = NativeMessagingPortTestDelegate(handler: handler) { port, error in
            XCTAssertNil(error)
            let disconnectHandler = port.disconnectHandler
            port.disconnectHandler = { error in
                disconnectHandler?(error)
                disconnected.fulfill()
            }
            connected.fulfill()
        }
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = delegate
        try controller.loadCopyingErrors(context)
        defer { try? controller.unloadCopyingErrors(context) }
        await fulfillment(of: [connected], timeout: 10)

        do {
            _ = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: context)
            XCTFail("Expected the persistent port to use the shared session limit")
        } catch NativeMessagingHandler.HandlerError.sessionLimitExceeded {}

        let port = try XCTUnwrap(delegate.port)
        port.sendMessage(["disconnect": true]) { error in XCTAssertNil(error) }
        await fulfillment(of: [disconnected], timeout: 5)
        let reply = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: context)
        XCTAssertEqual(reply as? [String: Bool], ["ping": true])
        XCTAssertTrue(waitForNoRunningHosts())
    }

    @available(macOS 15.4, *)
    func testWhenOneShotLimitIsReachedThenOtherExtensionsCanConnectAndTimedOutCapacityIsReleased() async throws {
        let context = try await makeExtensionContext()
        let otherContext = try await makeExtensionContext()
        let silent = try makeHost(named: "silent-host", script: Self.silentHostScript)
        let echo = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let started = expectation(description: "silent host started")
        let handler = makeHandler(context: context, silent: silent, echo: echo, started: started,
                                  maximumSessionsPerExtension: 1, maximumSessions: 2)
        let first = Task { try await handler.sendMessage(["ping": true], applicationIdentifier: "silent", for: context) }
        await fulfillment(of: [started], timeout: 5)

        do {
            _ = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: context)
            XCTFail("Expected the per-extension limit to reject the request")
        } catch NativeMessagingHandler.HandlerError.sessionLimitExceeded {}
        let otherReply = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: otherContext)
        XCTAssertEqual(otherReply as? [String: Bool], ["ping": true])

        do {
            _ = try await first.value
            XCTFail("Expected the silent host to time out")
        } catch NativeMessagingHandler.HandlerError.timedOut {}
        let reply = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: context)
        XCTAssertEqual(reply as? [String: Bool], ["ping": true])
        XCTAssertTrue(waitForNoRunningHosts())
    }

    @available(macOS 15.4, *)
    func testWhenGlobalSessionLimitIsReachedThenAnotherExtensionIsRejected() async throws {
        let context = try await makeExtensionContext()
        let otherContext = try await makeExtensionContext()
        let silent = try makeHost(named: "silent-host", script: Self.silentHostScript)
        let echo = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let started = expectation(description: "silent host started")
        let handler = makeHandler(context: context, silent: silent, echo: echo, started: started,
                                  maximumSessionsPerExtension: 2, maximumSessions: 1)
        let first = Task { try await handler.sendMessage(["ping": true], applicationIdentifier: "silent", for: context) }
        await fulfillment(of: [started], timeout: 5)

        do {
            _ = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: otherContext)
            XCTFail("Expected the global limit to reject the request")
        } catch NativeMessagingHandler.HandlerError.sessionLimitExceeded {}

        do {
            _ = try await first.value
            XCTFail("Expected the silent host to time out")
        } catch NativeMessagingHandler.HandlerError.timedOut {}
        let reply = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: otherContext)
        XCTAssertEqual(reply as? [String: Bool], ["ping": true])
    }

    @available(macOS 15.4, *)
    func testWhenHostLaunchFailsThenSessionCapacityIsReleased() async throws {
        let context = try await makeExtensionContext()
        let missing = directory.appendingPathComponent("missing-host")
        let echo = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let started = expectation(description: "missing host selected")
        let handler = makeHandler(context: context, silent: missing, echo: echo, started: started,
                                  maximumSessionsPerExtension: 1, maximumSessions: 1)

        do {
            _ = try await handler.sendMessage(["ping": true], applicationIdentifier: "silent", for: context)
            XCTFail("Expected launch failure")
        } catch NativeMessagingHostSession.SessionError.launchFailed {}
        let reply = try await handler.sendMessage(["ping": true], applicationIdentifier: "echo", for: context)
        XCTAssertEqual(reply as? [String: Bool], ["ping": true])
    }

    @available(macOS 15.4, *)
    func testWhenHostNeverAnswersThenExchangeTimesOutAndStopsTheHost() async throws {
        let executable = try makeHost(named: "silent-host", script: Self.silentHostScript)
        let session = makeSession(executable: executable)

        let start = Date()
        do {
            _ = try await NativeMessagingHandler.exchange(["command": "ping"],
                                                          with: session,
                                                          hostName: "com.duckduckgo.test.host",
                                                          timeout: 0.5)
            XCTFail("Expected the exchange to time out")
        } catch NativeMessagingHandler.HandlerError.timedOut(let host) {
            XCTAssertEqual(host, "com.duckduckgo.test.host")
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertTrue(waitForNoRunningHosts(), "The host process outlived the timeout")
    }

    @available(macOS 15.4, *)
    func testWhenHostAnswersThenExchangeReturnsTheReplyAndStopsTheHost() async throws {
        let executable = try makeHost(named: "echo-host", script: Self.echoHostScript)
        let session = makeSession(executable: executable)

        let reply = try await NativeMessagingHandler.exchange(["command": "ping"],
                                                              with: session,
                                                              hostName: "com.duckduckgo.test.host",
                                                              timeout: 5)

        XCTAssertEqual(reply as? [String: String], ["command": "ping"])
        XCTAssertTrue(waitForNoRunningHosts(), "The host process outlived the exchange")
    }

    // MARK: - Helpers

    @available(macOS 15.4, *)
    private func makeExtensionContext(backgroundScript: String? = nil) async throws -> WKWebExtensionContext {
        let folder = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest: [String: Any] = ["manifest_version": 3, "name": "Native messaging test", "version": "1.0",
                                      "permissions": ["nativeMessaging"], "key": Data("test-key".utf8).base64EncodedString()]
        if let backgroundScript {
            manifest["background"] = ["page": "background.html"]
            try backgroundScript.write(to: folder.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
            try "<script src=\"background.js\"></script>".write(to: folder.appendingPathComponent("background.html"),
                                                             atomically: true, encoding: .utf8)
        }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let webExtension = try await WKWebExtension.makeCopyingErrors(at: folder)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = UUID().uuidString
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        return context
    }

    @available(macOS 15.4, *)
    private func makeHandler(context: WKWebExtensionContext, silent: URL, echo: URL, started: XCTestExpectation? = nil,
                             maximumSessionsPerExtension: Int, maximumSessions: Int) -> NativeMessagingHandler {
        NativeMessagingHandler(singleMessageTimeout: 1, maximumSessionsPerExtension: maximumSessionsPerExtension,
                               maximumSessions: maximumSessions, locateHost: { name in
            let executable = name == "silent" ? silent : echo
            if name == "silent" { started?.fulfill() }
            let manifest = NativeMessagingHostManifest(name: name, path: executable.path, type: .stdio,
                                                       allowedOrigins: context.webExtension.chromeExtensionOrigin.map { [$0] })
            return (manifest, executable)
        })
    }

    private func makeSession(executable: URL) -> NativeMessagingHostSession {
        NativeMessagingHostSession(hostName: "com.duckduckgo.test.host",
                                   extensionIdentifier: "test-extension",
                                   executable: executable,
                                   callerOrigin: Self.callerOrigin)
    }

    private func makeHost(named name: String, script: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Polls until no fake host of this test's directory is running, pumping the run loop so
    /// the session's own main-actor work keeps going.
    private func waitForNoRunningHosts(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !isAnyHostRunning() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return !isAnyHostRunning()
    }

    private func isAnyHostRunning() -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", directory.path]
        let output = Pipe()
        pgrep.standardOutput = output
        pgrep.standardError = Pipe()

        do {
            try pgrep.run()
        } catch {
            XCTFail("pgrep failed to run: \(error)")
            return false
        }

        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        pgrep.waitUntilExit()
        return !data.isEmpty
    }

    // MARK: - Fake hosts

    private static let framingPreamble = """
    #!/usr/bin/env python3
    import struct, sys

    def read_frame():
        prefix = sys.stdin.buffer.read(4)
        if len(prefix) < 4:
            return None
        length = struct.unpack('<I', prefix)[0]
        return sys.stdin.buffer.read(length)

    def write_frame(payload):
        sys.stdout.buffer.write(struct.pack('<I', len(payload)))
        sys.stdout.buffer.write(payload)
        sys.stdout.buffer.flush()

    """

    /// Answers every message with the same message, and stays up like a host with a companion
    /// app behind it.
    private static let echoHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    while True:
        payload = read_frame()
        if payload is None:
            break
        write_frame(payload)
    """

    /// Says why it is leaving, and leaves at once, as a proxy does when its companion app is
    /// absent. The message is the only explanation the browser gets.
    private static let farewellHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    write_frame(b'{"type":"disconnected"}')
    sys.exit(0)
    """

    /// Writes two messages in one go, then a third in two pieces with a pause between them.
    private static let chunkedHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    import time

    def frame(payload):
        return struct.pack('<I', len(payload)) + payload

    sys.stdout.buffer.write(frame(b'{"index":1}') + frame(b'{"index":2}'))
    sys.stdout.buffer.flush()
    third = frame(b'{"index":3}')
    sys.stdout.buffer.write(third[:6])
    sys.stdout.buffer.flush()
    time.sleep(0.3)
    sys.stdout.buffer.write(third[6:])
    sys.stdout.buffer.flush()
    """

    /// Writes a message and a frame that isn't JSON in one go, then stays up.
    private static let garbageHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    import time

    def frame(payload):
        return struct.pack('<I', len(payload)) + payload

    sys.stdout.buffer.write(frame(b'{"index":1}') + frame(b'not json'))
    sys.stdout.buffer.flush()
    time.sleep(5)
    """

    /// Reads its input and never answers.
    private static let silentHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    while read_frame() is not None:
        pass
    """

    private static let stalledHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    import time
    time.sleep(30)
    """

    /// Fails without a word.
    private static let failingHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    sys.exit(1)
    """

    /// Exits while a child of its own holds the output pipe open, so the pipe never reaches
    /// EOF and only the stall backstop can end the session.
    private static let leakyHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    import subprocess
    subprocess.Popen(['/bin/sleep', '5'])
    sys.exit(0)
    """

    /// Declares a message larger than the framing allows.
    private static let oversizedHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    sys.stdout.buffer.write(struct.pack('<I', 100 * 1024 * 1024))
    sys.stdout.buffer.flush()
    import time
    time.sleep(5)
    """
}

@available(macOS 15.4, *)
@MainActor
private final class NativeMessagingPortTestDelegate: NSObject, WKWebExtensionControllerDelegate {
    private let handler: NativeMessagingHandler
    private let connected: (WKWebExtension.MessagePort, Error?) -> Void
    private(set) var port: WKWebExtension.MessagePort?

    init(handler: NativeMessagingHandler, connected: @escaping (WKWebExtension.MessagePort, Error?) -> Void) {
        self.handler = handler
        self.connected = connected
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort,
                                for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        self.port = port
        Task { @MainActor in
            do {
                try await handler.connect(port, applicationIdentifier: port.applicationIdentifier, for: extensionContext)
                completionHandler(nil)
                connected(port, nil)
            } catch {
                completionHandler(error)
                connected(port, error)
            }
        }
    }
}
