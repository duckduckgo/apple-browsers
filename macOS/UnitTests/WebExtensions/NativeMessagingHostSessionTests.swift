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

import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Exercises `NativeMessagingHostSession` against fake hosts, which are Python scripts that
/// speak the native messaging wire format. Bitwarden's own host is a compiled binary that
/// quits at once when its desktop app is absent, and case-by-case scripts stand in for the
/// ways a host can end.
@MainActor
final class NativeMessagingHostSessionTests: XCTestCase {

    private static let callerOrigin = "chrome-extension://nngceckbapebfimnlniiiahkandclblb/"

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeMessagingHostSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

    /// Bitwarden's extension opens a port from two services, each retrying every ten seconds
    /// for as long as its desktop app stays away, so a refused connection happens over and
    /// over. Every attempt has to end on its own and leave nothing behind.
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

    // MARK: - Helpers

    private func makeSession(executable: URL) -> NativeMessagingHostSession {
        NativeMessagingHostSession(hostName: "com.duckduckgo.test.host",
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

    /// Says why it is leaving, and leaves at once. This is Bitwarden's proxy without its
    /// desktop app, and the message is the only explanation the browser gets.
    private static let farewellHostScript = NativeMessagingHostSessionTests.framingPreamble + """
    write_frame(b'{"type":"disconnected"}')
    sys.exit(0)
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
