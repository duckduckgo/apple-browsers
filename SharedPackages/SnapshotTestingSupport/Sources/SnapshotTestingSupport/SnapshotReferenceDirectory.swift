//
//  SnapshotReferenceDirectory.swift
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

func snapshotReferenceDirectory(
    file: StaticString,
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> String? {
    snapshotDirectory(file: file) { repoRoot in
        if let override = environment["SNAPSHOT_REFERENCE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return repoRoot.appendingPathComponent("SnapshotReferences", isDirectory: true)
    }
}

func snapshotExportDirectory(
    file: StaticString,
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> String? {
    guard let exportRoot = environment["SNAPSHOT_EXPORT_DIR"],
          !exportRoot.isEmpty else {
        return nil
    }
    return snapshotDirectory(file: file) { _ in URL(fileURLWithPath: exportRoot, isDirectory: true) }
}

private func snapshotDirectory(file: StaticString, root: (URL) -> URL) -> String? {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let testDirectory = fileURL.deletingLastPathComponent()
    let fileBaseName = fileURL.deletingPathExtension().lastPathComponent
    let fileManager = FileManager.default

    guard let repoRoot = repositoryRoot(startingFrom: testDirectory, fileManager: fileManager) else {
        return nil
    }

    let destination = relativePathComponents(of: testDirectory, from: repoRoot)
        .reduce(root(repoRoot)) { $0.appendingPathComponent($1, isDirectory: true) }
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(fileBaseName, isDirectory: true)

    return destination.path
}

private func repositoryRoot(startingFrom directory: URL, fileManager: FileManager) -> URL? {
    var current = directory.standardizedFileURL
    while true {
        if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
            return current
        }
        let parent = current.deletingLastPathComponent()
        if parent.path == current.path {
            return nil
        }
        current = parent
    }
}

private func relativePathComponents(of url: URL, from base: URL) -> [String] {
    let urlComponents = url.standardizedFileURL.pathComponents
    let baseComponents = base.standardizedFileURL.pathComponents
    guard urlComponents.count >= baseComponents.count,
          Array(urlComponents.prefix(baseComponents.count)) == baseComponents else {
        return []
    }
    return Array(urlComponents.dropFirst(baseComponents.count))
}
