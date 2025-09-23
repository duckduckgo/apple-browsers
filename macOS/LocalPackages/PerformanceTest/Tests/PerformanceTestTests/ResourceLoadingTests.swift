//
//  ResourceLoadingTests.swift
//  PerformanceTestTests
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import PerformanceTest

final class ResourceLoadingTests: XCTestCase {

    func testPerformanceMetricsJavaScriptFileExists() throws {
        // Test that the performanceMetrics.js file exists in the built resources
        // Since SPM puts resources in PerformanceTest_PerformanceTest.bundle, we test that the file exists

        let buildDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // PerformanceTestTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent(".build/arm64-apple-macosx/debug/PerformanceTest_PerformanceTest.bundle")

        let jsFile = buildDir.appendingPathComponent("performanceMetrics.js")

        print("Looking for JS file at: \(jsFile.path)")
        let fileExists = FileManager.default.fileExists(atPath: jsFile.path)
        print("File exists: \(fileExists)")

        if fileExists {
            let content = try String(contentsOf: jsFile)
            print("File content length: \(content.count)")
            XCTAssertFalse(content.isEmpty, "performanceMetrics.js should not be empty")
            XCTAssertTrue(content.contains("performance.getEntriesByType"), "JavaScript should contain performance API calls")
            XCTAssertTrue(content.contains("loadComplete"), "JavaScript should define loadComplete metric")
            XCTAssertTrue(content.contains("firstContentfulPaint"), "JavaScript should define firstContentfulPaint metric")
        }

        XCTAssertTrue(fileExists, "performanceMetrics.js should be built into the bundle")
    }
}