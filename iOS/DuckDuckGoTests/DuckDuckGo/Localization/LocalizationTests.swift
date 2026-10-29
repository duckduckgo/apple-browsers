//
//  LocalizationTests.swift
//  DuckDuckGo
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

#if targetEnvironment(simulator)
    func testNoDuplicateLocalizationKeys() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let regex = try NSRegularExpression(pattern: #"NSLocalizedString\("([^"\\]+)"#, options: [])

        let fileManager = FileManager.default
        let allPaths = try fileManager.subpathsOfDirectory(atPath: projectRoot.path)
        let targetPaths = allPaths.filter { $0.hasSuffix("UserText.swift") }
        XCTAssertFalse(targetPaths.isEmpty, "Expected to find UserText.swift files under \(projectRoot.path)")

        var failures: [(file: String, duplicates: [String])] = []

        for relativePath in targetPaths {
            let fileURL = projectRoot.appendingPathComponent(relativePath)
            let content = try String(contentsOf: fileURL)

            let matches = regex.matches(
                in: content, options: [],
                range: NSRange(content.startIndex..<content.endIndex, in: content)
            ).compactMap { match in
                Range(match.range(at: 1), in: content).map { String(content[$0]) }
            }

            let dupKeys = Dictionary(grouping: matches, by: { $0 })
                .filter { $1.count > 1 }
                .keys.sorted()

            if !dupKeys.isEmpty {
                failures.append((relativePath, Array(dupKeys)))
            }
        }

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
#endif
}
