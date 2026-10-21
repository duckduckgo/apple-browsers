//
//  ChromeWebStoreDownloader.swift
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

public protocol ChromeWebStoreDownloading {
    func download(extensionID: String) async throws -> Data
}

public struct ChromeWebStoreDownloader: ChromeWebStoreDownloading {
    public init() {}

    public func download(extensionID: String) async throws -> Data {
        let url = try ChromeWebStoreURL.downloadURL(for: extensionID)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let policy = DownloadPolicy()
        let (file, response) = try await session.download(for: URLRequest(url: url, timeoutInterval: 120), delegate: policy)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let responseURL = response.url, ChromeWebStoreURL.isAllowedDownloadDestination(responseURL) else {
            throw ChromeWebStoreError.downloadFailed
        }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }

    private final class DownloadPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let url = request.url, ChromeWebStoreURL.isAllowedDownloadDestination(url) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
}
