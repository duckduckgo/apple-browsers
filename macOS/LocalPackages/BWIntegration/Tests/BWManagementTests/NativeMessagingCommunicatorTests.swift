//
//  NativeMessagingCommunicatorTests.swift
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

import XCTest
@testable import BWManagement

final class NativeMessagingCommunicatorTests: XCTestCase {

    private func makeCommunicator() -> NativeMessagingCommunicator {
        NativeMessagingCommunicator(appPath: "/usr/bin/true", arguments: [])
    }

    // The installed handlers are inert and removed in defer: a live handler would
    // race the test's own blocking availableData read, and a handler left installed
    // on an EOF'd pipe keeps a dispatch source spinning for the rest of the test run.

    func testWhenPipeReachesEOFThenReadabilityHandlerIsUninstalled() throws {
        let communicator = makeCommunicator()
        let pipe = Pipe()
        let readingHandle = pipe.fileHandleForReading
        readingHandle.readabilityHandler = { _ in }
        defer { readingHandle.readabilityHandler = nil }

        // Closing the write end puts the read end at EOF
        try pipe.fileHandleForWriting.close()
        communicator.receiveData(readingHandle)

        XCTAssertNil(readingHandle.readabilityHandler)
    }

    func testWhenDataIsAvailableThenReadabilityHandlerStaysInstalled() throws {
        let communicator = makeCommunicator()
        let pipe = Pipe()
        let readingHandle = pipe.fileHandleForReading
        readingHandle.readabilityHandler = { _ in }
        defer { readingHandle.readabilityHandler = nil }

        // A well-formed native messaging frame: 4-byte length prefix + payload
        var messageLength = UInt32(1)
        let header = Data(bytes: &messageLength, count: 4)
        try pipe.fileHandleForWriting.write(contentsOf: header + Data([0x42]))
        communicator.receiveData(readingHandle)

        XCTAssertNotNil(readingHandle.readabilityHandler)
    }

    func testWhenEOFMonitoringIsDisabledThenReadabilityHandlerStaysInstalled() throws {
        let communicator = makeCommunicator()
        let pipe = Pipe()
        let readingHandle = pipe.fileHandleForReading
        readingHandle.readabilityHandler = { _ in }
        defer { readingHandle.readabilityHandler = nil }

        try pipe.fileHandleForWriting.close()
        communicator.receiveData(readingHandle, stopMonitoringAtEOF: false)

        XCTAssertNotNil(readingHandle.readabilityHandler)
    }

}
