//
//  NativeMessagingHostProcessTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Exercises `NativeMessagingHostProcess` against system binaries standing in for hosts.
@MainActor
final class NativeMessagingHostProcessTests: XCTestCase {

    private static let callerOrigin = "chrome-extension://nngceckbapebfimnlniiiahkandclblb/"

    private var processes: [NativeMessagingHostProcess] = []
    private var inputPipe: Pipe!
    private var outputPipe: Pipe!
    private var errorPipe: Pipe!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(NSApp.isSandboxed, "A sandboxed host can't launch native messaging hosts")
        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()
    }

    override func tearDownWithError() throws {
        processes.forEach { $0.terminate() }
        processes = []
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func testWhenHostIsLaunchedThenItIsItsOwnResponsibleProcess() throws {
        typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
        let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        let responsiblePID = try XCTUnwrap(symbol.map { unsafeBitCast($0, to: ResponsiblePID.self) },
                                           "This macOS can't report a process's responsible process")
        let process = try launch("/bin/cat")

        XCTAssertEqual(responsiblePID(process.processIdentifier), process.processIdentifier)
    }

    func testWhenHostEchoesThenItsInputAndOutputAreConnected() throws {
        try launch("/bin/cat")

        try inputPipe.fileHandleForWriting.write(contentsOf: Data("hello".utf8))
        try inputPipe.fileHandleForWriting.close()

        // Reading to the end only returns once the host's output reaches EOF.
        XCTAssertEqual(try outputPipe.fileHandleForReading.readToEnd(), Data("hello".utf8))
    }

    func testWhenHostWritesToStandardErrorThenItArrivesOnTheErrorPipe() throws {
        try launch("/bin/sh", arguments: ["-c", "printf oops >&2"])

        XCTAssertEqual(try errorPipe.fileHandleForReading.readToEnd(), Data("oops".utf8))
    }

    func testWhenHostIsLaunchedThenItReceivesItsArguments() throws {
        try launch("/bin/sh", arguments: ["-c", "printf %s \"$0\"", Self.callerOrigin])

        XCTAssertEqual(try outputPipe.fileHandleForReading.readToEnd(), Data(Self.callerOrigin.utf8))
    }

    func testWhenHostExitsThenTerminationHandlerReportsItsExitCode() throws {
        let process = makeProcess("/bin/sh", arguments: ["-c", "exit 3"])
        let terminated = expectation(description: "termination handler called once")
        var status: Int32?
        process.terminationHandler = {
            status = $0
            terminated.fulfill()
        }

        try run(process)

        wait(for: [terminated], timeout: 10)
        XCTAssertEqual(status, 3)
        XCTAssertEqual(process.terminationStatus, 3)
        XCTAssertFalse(process.isRunning)
    }

    /// The host is gone before anything watches for its exit, as Apple's helper was on macOS 15.
    func testWhenHostExitsImmediatelyThenTerminationIsStillReported() throws {
        let process = makeProcess("/usr/bin/false")
        let terminated = expectation(description: "termination handler called")
        var status: Int32?
        process.terminationHandler = {
            status = $0
            terminated.fulfill()
        }

        try run(process)

        wait(for: [terminated], timeout: 10)
        XCTAssertEqual(status, 1)
    }

    func testWhenTerminateIsCalledThenStatusIsTheSignal() throws {
        let process = makeProcess("/bin/cat")
        let terminated = expectation(description: "termination handler called")
        var status: Int32?
        process.terminationHandler = {
            status = $0
            terminated.fulfill()
        }

        try run(process)
        XCTAssertTrue(process.isRunning)
        process.terminate()

        wait(for: [terminated], timeout: 10)
        XCTAssertEqual(status, SIGTERM)
        XCTAssertFalse(process.isRunning)
    }

    func testWhenExecutableIsMissingThenRunThrows() {
        let process = makeProcess("/nonexistent/host")

        XCTAssertThrowsError(try run(process)) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(ENOENT))
        }
        XCTAssertFalse(process.isRunning)
    }

    /// Signalling process 0 would end the browser's own process group.
    func testWhenTerminateIsCalledBeforeRunThenNothingHappens() {
        let process = makeProcess("/bin/cat")

        process.terminate()

        XCTAssertFalse(process.isRunning)
        XCTAssertNil(process.terminationStatus)
    }

    // MARK: - Helpers

    private func makeProcess(_ path: String, arguments: [String] = []) -> NativeMessagingHostProcess {
        let process = NativeMessagingHostProcess(executable: URL(fileURLWithPath: path), arguments: arguments)
        processes.append(process)
        return process
    }

    private func run(_ process: NativeMessagingHostProcess) throws {
        try process.run(standardInput: inputPipe, standardOutput: outputPipe, standardError: errorPipe)
    }

    @discardableResult
    private func launch(_ path: String, arguments: [String] = []) throws -> NativeMessagingHostProcess {
        let process = makeProcess(path, arguments: arguments)
        try run(process)
        return process
    }
}
