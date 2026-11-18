//
//  ModelBundle.swift
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

import DDGError
import Foundation

/// One file of a bundle. `size` and `sha256` describe the downloaded bytes; `name` is what's kept on disk.
public struct ModelFile: Sendable, Equatable {
    public let name: String
    public let url: URL
    public let size: Int64
    public let sha256: String

    public init(name: String, url: URL, size: Int64, sha256: String) {
        self.name = name
        self.url = url
        self.size = size
        self.sha256 = sha256
    }
}

/// The unit ModelStore installs and deletes: every file is installed, or none is.
public struct ModelBundle: Sendable, Equatable {
    public let id: String
    public let version: String
    public let files: [ModelFile]

    public init(id: String, version: String, files: [ModelFile]) {
        self.id = id
        self.version = version
        self.files = files
    }

    /// Download size of the whole bundle.
    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }
}

public struct DownloadPolicy: Sendable {
    /// Runs on each verified download; returns the file to keep. ModelStore stores it as `file.name`.
    public var process: @Sendable (URL, ModelFile) throws -> URL

    public init(process: @escaping @Sendable (URL, ModelFile) throws -> URL = { url, _ in url }) {
        self.process = process
    }
}

public struct InstalledBundle: Sendable, Equatable {
    public let id: String
    public let version: String
    public let folder: URL
}

public enum ModelStoreError: DDGError {
    case invalidName(String)
    case alreadyInstalling(String)
    case httpStatus(file: String, code: Int)
    case sizeMismatch(file: String, expected: Int64, actual: Int64)
    case hashMismatch(file: String)

    public static var errorDomain: String { "com.duckduckgo.localModels.ModelStoreError" }

    public var errorCode: Int {
        switch self {
        case .invalidName: return 1
        case .alreadyInstalling: return 2
        case .httpStatus: return 3
        case .sizeMismatch: return 4
        case .hashMismatch: return 5
        }
    }

    public var description: String {
        switch self {
        case .invalidName(let name): return "Invalid bundle or file name: \(name)"
        case .alreadyInstalling(let id): return "\(id) is already being installed"
        case .httpStatus(let file, let code): return "Downloading \(file) failed with HTTP \(code)"
        case .sizeMismatch(let file, let expected, let actual): return "\(file) is \(actual) bytes, expected \(expected)"
        case .hashMismatch(let file): return "\(file) doesn't match its sha256"
        }
    }
}
