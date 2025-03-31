//
//  JsonTestDataLoader.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

enum FileError: Error {
    case unknownFile
    case invalidFileContents
}

final class FileLoader {

    func load(filePath: String, fromBundle bundle: Bundle) throws -> Data {

        guard let resourceUrl = bundle.resourceURL else { throw FileError.unknownFile }

        let url = resourceUrl.appendingPathComponent(filePath)

        let finalURL: URL
        if FileManager.default.fileExists(atPath: url.path) {
            finalURL = url
        } else {
            // Workaround for resource bundle having a different structure when running tests from command line.
            let url = resourceUrl.deletingLastPathComponent().appendingPathComponent(filePath)

            if FileManager.default.fileExists(atPath: url.path) {
                finalURL = url
            } else {
                throw FileError.unknownFile
            }
        }

        guard let data = try? Data(contentsOf: finalURL, options: [.mappedIfSafe]) else { throw  FileError.invalidFileContents }
        return data
    }
}

final class JsonTestDataLoader {

    func empty() -> Data {
        return "".data(using: .utf16)!
    }

    func invalid() -> Data {
        return "{[}".data(using: .utf16)!
    }

    func unexpected() -> Data {
        guard let data = try? FileLoader().load(filePath: "Resources/unexpected.json", fromBundle: bundle) else {
            fatalError("Failed to load Resources/unexpected.json")
        }
        return data
    }

    func fromJsonFile(_ filePath: String) -> Data {

        do {
            return try FileLoader().load(filePath: filePath, fromBundle: bundle)
        } catch {
            fatalError("Unable to load \(filePath) error \(error)")
        }
    }

    private var bundle: Bundle {
        return Bundle.module
    }
}
