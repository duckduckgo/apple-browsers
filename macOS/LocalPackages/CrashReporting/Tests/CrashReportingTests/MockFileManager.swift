//
//  MockFileManager.swift
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

import Foundation

final class MockFileManager: FileManager, @unchecked Sendable {

    private struct MockFile {
        let url: URL
        let contents: String
        let creationDate: Date
    }

    private var directoryContents: [URL: [URL]] = [:]
    private var files: [URL: MockFile] = [:]

    override func contentsOfDirectory(at url: URL,
                                      includingPropertiesForKeys keys: [URLResourceKey]?,
                                      options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        directoryContents[url] ?? []
    }

    override func contents(atPath path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let contents = files[url]?.contents else {
            return nil
        }
        return contents.data(using: .utf8)
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let url = URL(fileURLWithPath: path)
        if let file = files[url] {
            return [.creationDate: file.creationDate]
        }
        assertionFailure("Unexpected file attributes requested for: \(url)")
        return [:]
    }

    func registerFile(at url: URL, in directory: URL, contents: String, creationDate: Date) {
        directoryContents[directory, default: []].append(url)
        files[url] = MockFile(url: url, contents: contents, creationDate: creationDate)
    }
}
