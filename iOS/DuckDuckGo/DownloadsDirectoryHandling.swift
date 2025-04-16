//
//  DownloadsDirectoryHandling.swift
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

import Foundation

protocol DownloadsDirectoryHandling {
    var downloadsDirectory: URL { get }
    var downloadsDirectoryFiles: [URL] { get }
    func createDownloadsDirectoryIfNeeded()
    func downloadsDirectoryExists() -> Bool
    func createDownloadsDirectory()
}

struct DownloadsDirectoryHandler: DownloadsDirectoryHandling {

    private enum Constants {
        static var downloadsDirectoryName = "Downloads"
    }

    var downloadsDirectory: URL {
        do {
            let documentsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            return documentsDirectory.appendingPathComponent(Constants.downloadsDirectoryName, isDirectory: true)
        } catch {
            Logger.general.error("Failed to create downloads directory: \(error.localizedDescription, privacy: .public)")
            let temporaryDirectory = FileManager.default.temporaryDirectory
            return temporaryDirectory.appendingPathComponent(Constants.downloadsDirectoryName, isDirectory: true)
        }
    }

    var downloadsDirectoryFiles: [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: downloadsDirectory,
                                                                     includingPropertiesForKeys: nil,
                                                                     options: .skipsHiddenFiles)) ?? []
        return contents.filter { !$0.hasDirectoryPath }
    }

    func createDownloadsDirectoryIfNeeded() {
        if !downloadsDirectoryExists() {
            createDownloadsDirectory()
        }
    }

    func downloadsDirectoryExists() -> Bool {
        FileManager.default.fileExists(atPath: downloadsDirectory.path)
    }

    func createDownloadsDirectory() {
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
    }
}
