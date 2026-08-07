//
//  RunningApplicationCheckTests.swift
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

final class RunningApplicationCheckTests: XCTestCase {

    func testWhenProcessIsSpawnedByCurrentProcessThenItIsRecognizedAsChild() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()
        defer { process.terminate() }

        XCTAssertTrue(RunningApplicationCheck.isChildOfCurrentProcess(process.processIdentifier))
    }

    func testWhenProcessIsNotSpawnedByCurrentProcessThenItIsNotRecognizedAsChild() {
        // launchd (pid 1) is never a child of the test runner
        XCTAssertFalse(RunningApplicationCheck.isChildOfCurrentProcess(1))
    }

}
