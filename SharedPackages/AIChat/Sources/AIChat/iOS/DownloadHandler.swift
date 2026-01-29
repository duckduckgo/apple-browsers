//
//  DownloadHandler.swift
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

#if os(iOS)
import WebKit

// MARK: - Public API

public typealias DownloadCompletionHandler = (Result<String, Error>) -> Void

public protocol DownloadHandling: WKDownloadDelegate {
    var onDownloadComplete: DownloadCompletionHandler? { get set }
}

/// Factory function to create a download handler with the specified downloads path.
public func makeDownloadHandler(downloadsPath: URL) -> DownloadHandling {
    return DownloadHandler(downloadsPath: downloadsPath)
}

// MARK: - Internal Implementation

final class DownloadHandler: NSObject, DownloadHandling {
    var onDownloadComplete: DownloadCompletionHandler?
    private let downloadsPath: URL
    private var filename: String?

    init(downloadsPath: URL) {
        self.downloadsPath = downloadsPath
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        filename = suggestedFilename
        let destination = downloadsPath.appendingPathComponent(suggestedFilename)
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let filename = filename else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onDownloadComplete?(.success(filename))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        DispatchQueue.main.async { [weak self] in
            self?.onDownloadComplete?(.failure(error))
        }
    }
}
#endif
