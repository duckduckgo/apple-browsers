//
//  LocalizationTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class LocalizationTests: XCTestCase {

    func testNoDuplicateLocalizationKeys() throws {
        // 1. Extract Root URL
        let testFileURL = URL(fileURLWithPath: #file)
        let projectRoot = testFileURL
            .deletingLastPathComponent()    // …/LocalizationTests
            .deletingLastPathComponent()    // …/UnitTests
            .deletingLastPathComponent()    // …/macOS

        // 2. Regex for NSLocalizedString key
        let regex = try NSRegularExpression(pattern: #"NSLocalizedString\("([^"\\]+)"#, options: [])

        // 3. Gather relevant files
        let fileManager = FileManager.default
        let allPaths = try fileManager.subpathsOfDirectory(atPath: projectRoot.path)
        let targetPaths = allPaths.filter { $0.hasSuffix("UserText.swift") }

        var failures: [(file: String, duplicates: [String])] = []

        for relativePath in targetPaths {
            let fileURL = projectRoot.appendingPathComponent(relativePath)
            let content = try String(contentsOf: fileURL)

            // 4. Extract keys
            let matches = regex.matches(
                in: content, options: [],
                range: NSRange(content.startIndex..<content.endIndex, in: content)
            ).compactMap { match in
                Range(match.range(at: 1), in: content).map { String(content[$0]) }
            }

            // 5. Detect duplicates
            let dupKeys = Dictionary(grouping: matches, by: { $0 })
                .filter { $1.count > 1 }
                .keys.sorted()

            if !dupKeys.isEmpty {
                failures.append((relativePath, Array(dupKeys)))
            }
        }

        // 6. Assert
        if !failures.isEmpty {
            let report = failures.map { file, dups in
                    """
                    \n
                    ❌ Duplicate keys in \(file):
                    \(dups.map { "   • \($0)" }.joined(separator: "\n"))
                    """
            }.joined(separator: "\n")
            XCTFail(report)
        }
    }

}
