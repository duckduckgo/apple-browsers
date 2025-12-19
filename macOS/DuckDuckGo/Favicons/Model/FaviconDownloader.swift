//
//  FaviconDownloader.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import Foundation
import OSLog
import WebKit

/// Downloads favicons using WKDownload to avoid App Transport Security restrictions on HTTP URLs
@MainActor
final class FaviconDownloader: NSObject {

    private struct FaviconDownloadTask {
        let url: URL
        let continuation: CheckedContinuation<Data, Error>
        var destinationURL: URL?
    }

    /// Maximum allowed size for favicon downloads (1MB)
    private static nonisolated let maxFaviconSize: Int64 = 1024 * 1024

    private var pendingDownloads: [WKDownload: FaviconDownloadTask] = [:]
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private lazy var faviconURLSession = URLSession(configuration: .ephemeral)

    nonisolated init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
        super.init()
    }

    /// Downloads a favicon from the given URL using the provided webView (if available)
    func download(from url: URL, using webView: WKWebView?) async throws -> Data {
        try Task.checkCancellation()

        guard privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(MacOSBrowserConfigSubfeature.faviconWKDownload, defaultValue: true) else {
            return try await faviconURLSession.data(from: url).0
        }
        return try await downloadUsingWKDownload(from: url, using: webView)
    }

    private func downloadUsingWKDownload(from url: URL, using webView: WKWebView?) async throws -> Data {
        // Use provided webView (to share session/cookies), or create a temporary one if needed
        let targetWebView = webView ?? createTemporaryWebView()

        let download = await targetWebView.startDownload(using: URLRequest(url: url))

        // Observe progress to cancel if download exceeds size limit
        let progressObserver = download.progress.observe(\.completedUnitCount) { [weak self, weak download] progress, _ in
            if progress.completedUnitCount > Self.maxFaviconSize, let self, let download {
                Logger.favicons.debug("FaviconDownloader: Cancelling favicon download - \(progress.completedUnitCount) bytes exceeds limit of \(Self.maxFaviconSize) bytes")
                self.cancel(download)
            }
        }
        defer { withExtendedLifetime(progressObserver) {} }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = FaviconDownloadTask(url: url, continuation: continuation)
                pendingDownloads[download] = task
                download.delegate = self
            }
        } onCancel: {
            self.cancel(download)
        }
    }

    private func createTemporaryWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }

    nonisolated private func cancel(_ download: WKDownload) {
        DispatchQueue.main.asyncOrNow {
            let task = self.pendingDownloads.removeValue(forKey: download)
            defer {
                // continuation is always called after removing the FaviconDownloadTask from the store on MainActor.
                // it should guarantee the continuation is only called once.
                task?.continuation.resume(with: .failure(URLError(.cancelled)))
            }
            download.delegate = nil
            download.cancel { _ in
                try? task?.destinationURL.map(FileManager.default.removeItem(at:))
            }
        }
    }

    deinit {
        let pendingDownloads = self.pendingDownloads
        self.pendingDownloads.removeAll()

        for (download, task) in pendingDownloads {
            DispatchQueue.main.asyncOrNow {
                download.cancel { _ in
                    try? task.destinationURL.map(FileManager.default.removeItem(at:))
                }
            }
            task.continuation.resume(with: .failure(URLError(.cancelled)))
        }
    }
}

extension FaviconDownloader: WKNavigationDelegate {

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        // We're only using this WebView for downloads, not navigation
        decisionHandler(.cancel, preferences)
    }
}

extension FaviconDownloader: WKDownloadDelegate {

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        // Check size limit if Content-Length header is available
        if response.expectedContentLength > 0 && response.expectedContentLength > Self.maxFaviconSize {
            Logger.favicons.debug("FaviconDownloader: Rejecting favicon download - size \(response.expectedContentLength) exceeds limit of \(Self.maxFaviconSize) bytes")
            return nil
        }

        // Create a temporary file URL for the download
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileName = UUID().uuidString
        let destinationURL = tempDirectory.appendingPathComponent(fileName)

        // Store the destination URL so we can read the file later
        guard var task = pendingDownloads[download] else { return nil }
        task.destinationURL = destinationURL
        pendingDownloads[download] = task

        return destinationURL
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let task = pendingDownloads.removeValue(forKey: download) else { return }
        let result: Result<Data, Error>
        defer {
            task.continuation.resume(with: result)
        }

        // Read the downloaded file
        do {
            guard let destinationURL = task.destinationURL else { throw CocoaError(.fileNoSuchFile) }
            defer {
                // Clean up the temporary file
                try? FileManager.default.removeItem(at: destinationURL)
            }

            // Check actual file size
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > Self.maxFaviconSize {
                Logger.favicons.debug("FaviconDownloader: Rejecting downloaded favicon - size \(fileSize) exceeds limit of \(Self.maxFaviconSize) bytes")
                throw URLError(.dataLengthExceedsMaximum, userInfo: [NSURLErrorKey: task.url])
            }

            let data = try Data(contentsOf: destinationURL)
            result = .success(data)
        } catch {
            Logger.favicons.error("FaviconDownloader: Failed to read downloaded file: \(error.localizedDescription)")
            result = .failure(error)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let task = pendingDownloads.removeValue(forKey: download) else { return }
        let result: Result<Data, Error>
        defer {
            task.continuation.resume(with: result)
        }

        Logger.favicons.debug("FaviconDownloader: Download failed for \(task.url.absoluteString): \(error.localizedDescription)")

        // Clean up temporary file if it exists
        if let destinationURL = task.destinationURL {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        result = .failure(error)
    }
}
