//
//  SpyDownloadManager.swift
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
@testable import DuckDuckGo

class SpyDownloadManager: DownloadManaging {
    var downloadList: Set<Download> = []
    var downloadsDirectory: URL?
    private var stubbedDownloadsDirectoryFiles: [URL] = []

    var downloadsDirectoryFiles: [URL] {
        get {
            guard let downloadsDirectory else { return stubbedDownloadsDirectoryFiles }
            return (try? FileManager.default.contentsOfDirectory(at: downloadsDirectory,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: .skipsHiddenFiles)) ?? []
        }
        set {
            stubbedDownloadsDirectoryFiles = newValue
        }
    }

    func startMonitoringDownloadsDirectoryChanges() { }

    func stopMonitoringDownloadsDirectoryChanges() { }

    func markAllDownloadsSeen() { }

    private(set) var cancelledDownloads: [Download] = []

    func cancelDownload(_ download: Download) {
        cancelledDownloads.append(download)
    }

    var cancelAllDownloadsCallCount = 0
    
    func cancelAllDownloads() {
        cancelAllDownloadsCallCount += 1
    }
}
