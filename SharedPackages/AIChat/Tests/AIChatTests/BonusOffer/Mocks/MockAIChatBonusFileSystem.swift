//
//  MockAIChatBonusFileSystem.swift
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

import Foundation
@testable import AIChat

/// An in-memory file system. Each error override makes that call fail without touching the files.
final class MockAIChatBonusFileSystem: AIChatBonusFileStoring {

    enum Operation: Equatable {
        case read(URL)
        case write(URL)
        case remove(URL)
        case prepareDirectory(URL)
    }

    var files: [URL: Data] = [:]

    var readError: Error?
    var writeError: Error?
    var removeError: Error?
    var prepareDirectoryError: Error?

    private(set) var operations: [Operation] = []

    func read(_ url: URL) throws -> Data {
        operations.append(.read(url))
        if let readError { throw readError }
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        operations.append(.write(url))
        if let writeError { throw writeError }
        files[url] = data
    }

    func remove(_ url: URL) throws {
        operations.append(.remove(url))
        if let removeError { throw removeError }
        files[url] = nil
    }

    func prepareDirectory(_ url: URL) throws {
        operations.append(.prepareDirectory(url))
        if let prepareDirectoryError { throw prepareDirectoryError }
    }
}
