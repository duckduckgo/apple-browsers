//
//  DuckURLSchemeHandler.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import ContentScopeScripts
import FeatureFlags_macOS
import Foundation
import MaliciousSiteProtection
import Persistence
import PrivacyConfig
import WebKit

final class DuckURLSchemeHandler: NSObject, WKURLSchemeHandler {

    let featureFlagger: FeatureFlagger
    let faviconManager: FaviconManagement
    let permissionManager: PermissionManagerProtocol
    let isNTPSpecialPageSupported: Bool
    let userBackgroundImagesManager: UserBackgroundImagesManaging?

    private var failureURLSchemeDebugKeyedStorage: some KeyedStoring<FailureURLSchemeDebugSettingsKeys> {
        UserDefaults.standard.keyedStoring()
    }

    /// Identifiers of in-flight favicon scheme tasks that complete asynchronously (after awaiting the
    /// image decode). Used to skip messaging a task that WebKit has already stopped.
    private var runningFaviconTasks = Set<ObjectIdentifier>()

    /// Debug-only Favicons inspector served at `duck://favicons` (Debug ▸ Inspect Favicons).
    private lazy var faviconsDebugInspector = FaviconsDebugInspector(faviconManager: faviconManager)

    /// Debug-only Permissions inspector served at `duck://permissions` (Debug ▸ Permissions ▸ Inspect).
    private lazy var permissionsDebugInspector = PermissionsDebugInspector(permissionManager: permissionManager)

    init(
        featureFlagger: FeatureFlagger,
        faviconManager: FaviconManagement = NSApp.delegateTyped.faviconManager,
        permissionManager: PermissionManagerProtocol = NSApp.delegateTyped.permissionManager,
        isNTPSpecialPageSupported: Bool = false,
        userBackgroundImagesManager: UserBackgroundImagesManaging? = NSApp.delegateTyped.newTabPageCustomizationModel.customImagesManager
    ) {
        self.featureFlagger = featureFlagger
        self.faviconManager = faviconManager
        self.permissionManager = permissionManager
        self.isNTPSpecialPageSupported = isNTPSpecialPageSupported
        self.userBackgroundImagesManager = userBackgroundImagesManager
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            assertionFailure("No URL for Duck scheme handler")
            return
        }

        if requestURL.isDebugURLScheme {
            handleDebugSchemeURL(requestURL: requestURL, urlSchemeTask: urlSchemeTask)
            return
        }

        let webViewURL = webView.url ?? requestURL

        switch webViewURL.type {
        case .onboarding, .releaseNotes:
            handleSpecialPages(urlSchemeTask: urlSchemeTask)
        case .duckPlayer:
            handleDuckPlayer(requestURL: webViewURL, urlSchemeTask: urlSchemeTask, webView: webView)
        case .error:
            handleErrorPage(urlSchemeTask: urlSchemeTask)
        case .newTab where isNTPSpecialPageSupported:
            switch requestURL.type {
            case .favicon:
                handleFavicon(urlSchemeTask: urlSchemeTask)
            case .customBackgroundImage:
                handleCustomBackgroundImage(urlSchemeTask: urlSchemeTask)
            case .customBackgroundImageThumbnail:
                handleCustomBackgroundImage(urlSchemeTask: urlSchemeTask, isThumbnail: true)
            default:
                handleSpecialPages(urlSchemeTask: urlSchemeTask)
            }
        case .history:
            switch requestURL.type {
            case .favicon:
                handleFavicon(urlSchemeTask: urlSchemeTask)
            default:
                handleSpecialPages(urlSchemeTask: urlSchemeTask)
            }
        // Matched only for internal users; for everyone else no case matches and `duck://permissions`
        // falls to `default:`, the same empty native UI page any unknown duck:// host gets.
        case .permissions where featureFlagger.internalUserDecider.isInternalUser:
            permissionsDebugInspector.handle(requestURL: requestURL, urlSchemeTask: urlSchemeTask)
        case .favicons:
            guard featureFlagger.internalUserDecider.isInternalUser else {
                fallthrough
            }
            faviconsDebugInspector.handle(requestURL: requestURL, urlSchemeTask: urlSchemeTask)
        default:
            handleNativeUIPages(requestURL: requestURL, urlSchemeTask: urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // A favicon task may still be awaiting its image decode; drop it so the pending completion is
        // skipped instead of messaging a stopped task (which would crash).
        runningFaviconTasks.remove(ObjectIdentifier(urlSchemeTask))
        faviconsDebugInspector.webViewDidStop(urlSchemeTask)
    }

    private static let failureSchemeDemoHtml = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <title>debug://failure</title>
      <style>
        body { font: -apple-system-body; margin: 2rem; line-height: 1.4; }
        code { font: -apple-system-monospaced; }
      </style>
    </head>
    <body>
      <h1><code>debug://failure</code></h1>
      <p>This page is served by the app URL scheme handler.</p>
      <p>Turn on <strong>Debug → debug:// URL scheme → Simulate debug://failure connection error</strong> to produce a
      connection-lost navigation failure instead of this page.</p>
    </body>
    </html>
    """

    /// UI tests only: `debug://failure?alternatingFailures=1` alternates simulated `URLError` on successive handler invocations (tab reactivation / reload), matching the former `ErrorPageTests` connection-lost vs not-connected style updates without the tests server.
    ///
    /// `debug://failure?simulatedError=notConnected` always uses `URLError.notConnectedToInternet`; `simulatedError=hostNotFound` always uses `URLError.cannotFindHost` (no auto-reload on tab reactivation). Simulated failures append ` · attempt N` to `NSLocalizedDescriptionKey` (counter resets with the alternating pass index when the Debug simulate toggle changes).
    static func resetFailureSchemeAlternatingStateForUITests() {
        alternatingFailuresLock.lock()
        alternatingFailuresPassIndex = 0
        alternatingFailuresLock.unlock()
        failureSimulateAttemptLock.lock()
        failureSimulateAttemptIndex = 0
        failureSimulateAttemptLock.unlock()
    }

    private static let alternatingFailuresLock = NSLock()
    private static var alternatingFailuresPassIndex = 0

    private static let failureSimulateAttemptLock = NSLock()
    private static var failureSimulateAttemptIndex = 0

    private static func nextSimulatedFailureAttemptNumber() -> Int {
        failureSimulateAttemptLock.lock()
        failureSimulateAttemptIndex += 1
        let n = failureSimulateAttemptIndex
        failureSimulateAttemptLock.unlock()
        return n
    }

    private func shouldUseAlternatingSimulatedFailures(requestURL: URL) -> Bool {
        guard featureFlagger.isFeatureOn(.debugURLScheme) else { return false }
        return requestURL.hasDebugURLAlternatingFailures
    }

    /// UI tests: `debug://failure?simulatedError=notConnected` always fails with `URLError.notConnectedToInternet` (when simulate is on).
    private func failureSchemeForcesNotConnectedToInternetError(requestURL: URL) -> Bool {
        guard featureFlagger.isFeatureOn(.debugURLScheme) else { return false }
        switch requestURL.debugURLSimulatedError {
        case .notConnected, .notConnectedToInternet:
            return true
        case .hostNotFound, .cannotFindHost, nil:
            return false
        }
    }

    /// UI tests: `debug://failure?simulatedError=hostNotFound` always fails with `URLError.cannotFindHost` (when simulate is on).
    /// Unlike the connection-style errors above, this error kind must NOT trigger the tab-reactivation auto-reload
    /// (`Tab.shouldReload` reloads only for `.notConnectedToInternet` / `.networkConnectionLost`), which the attempt counter makes observable.
    private func failureSchemeForcesHostNotFoundError(requestURL: URL) -> Bool {
        guard featureFlagger.isFeatureOn(.debugURLScheme) else { return false }
        switch requestURL.debugURLSimulatedError {
        case .hostNotFound, .cannotFindHost:
            return true
        case .notConnected, .notConnectedToInternet, nil:
            return false
        }
    }

    private func handleDebugSchemeURL(requestURL: URL, urlSchemeTask: WKURLSchemeTask) {
        guard featureFlagger.isFeatureOn(.debugURLScheme) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }

        switch requestURL.debugURLIdentifier {
        case .failure:
            handleDebugFailureURL(requestURL: requestURL, urlSchemeTask: urlSchemeTask)
        case nil:
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
        }
    }

    private func handleDebugFailureURL(requestURL: URL, urlSchemeTask: WKURLSchemeTask) {
        if failureURLSchemeDebugKeyedStorage.simulateConnectionLost == true {
            if failureSchemeForcesHostNotFoundError(requestURL: requestURL) {
                let attempt = Self.nextSimulatedFailureAttemptNumber()
                let error = URLError(.cannotFindHost, userInfo: [
                    NSURLErrorFailingURLErrorKey: requestURL,
                    NSLocalizedDescriptionKey: "Debug simulated host not found (debug://failure) · attempt \(attempt)"
                ])
                urlSchemeTask.didFailWithError(error)
                return
            }
            if failureSchemeForcesNotConnectedToInternetError(requestURL: requestURL) {
                let attempt = Self.nextSimulatedFailureAttemptNumber()
                let error = URLError(.notConnectedToInternet, userInfo: [
                    NSURLErrorFailingURLErrorKey: requestURL,
                    NSLocalizedDescriptionKey: "Debug simulated not connected to internet (debug://failure) · attempt \(attempt)"
                ])
                urlSchemeTask.didFailWithError(error)
                return
            }
            if shouldUseAlternatingSimulatedFailures(requestURL: requestURL) {
                Self.alternatingFailuresLock.lock()
                let pass = Self.alternatingFailuresPassIndex
                Self.alternatingFailuresPassIndex += 1
                Self.alternatingFailuresLock.unlock()

                let attempt = Self.nextSimulatedFailureAttemptNumber()
                let error: URLError
                if pass % 2 == 0 {
                    error = URLError(.networkConnectionLost, userInfo: [
                        NSURLErrorFailingURLErrorKey: requestURL,
                        NSLocalizedDescriptionKey: "Debug simulated connection lost (debug://failure) · attempt \(attempt)"
                    ])
                } else {
                    error = URLError(.notConnectedToInternet, userInfo: [
                        NSURLErrorFailingURLErrorKey: requestURL,
                        NSLocalizedDescriptionKey: "Debug simulated not connected to internet (debug://failure) · attempt \(attempt)"
                    ])
                }
                urlSchemeTask.didFailWithError(error)
                return
            }

            let attempt = Self.nextSimulatedFailureAttemptNumber()
            let error = URLError(.networkConnectionLost, userInfo: [
                NSURLErrorFailingURLErrorKey: requestURL,
                NSLocalizedDescriptionKey: "Debug simulated connection lost (debug://failure) · attempt \(attempt)"
            ])
            urlSchemeTask.didFailWithError(error)
            return
        }

        let data = Self.failureSchemeDemoHtml.utf8data
        let response = URLResponse(url: requestURL,
                                   mimeType: "text/html",
                                   expectedContentLength: data.count,
                                   textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

}

// MARK: - Native UI Paged
extension DuckURLSchemeHandler {
    static let emptyHtml = """
    <html>
      <head>
        <style>
          body {
            background: rgb(255, 255, 255);
            display: flex;
            height: 100vh;
          }
          // avoid page blinking in dark mode
          @media (prefers-color-scheme: dark) {
            body {
              background: rgb(51, 51, 51);
            }
          }
        </style>
      </head>
      <body />
    </html>
    """

    private func handleNativeUIPages(requestURL: URL, urlSchemeTask: WKURLSchemeTask) {
        // return empty page for native UI pages navigations (like the Home page or Settings) if the request is not for the Duck Player
        let data = Self.emptyHtml.utf8data
        let response = URLResponse(url: requestURL,
                                   mimeType: "text/html",
                                   expectedContentLength: data.count,
                                   textEncodingName: nil)

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
}

// MARK: - DuckPlayer
private extension DuckURLSchemeHandler {
    func handleDuckPlayer(requestURL: URL, urlSchemeTask: WKURLSchemeTask, webView: WKWebView) {
        let youtubeHandler = YoutubePlayerNavigationHandler()
        let html = youtubeHandler.makeHTMLFromTemplate()

        // Apply the fast redirection workaround from PR #1331
        webView.stopLoading()
        let newRequest = youtubeHandler.makeDuckPlayerRequest(from: URLRequest(url: requestURL))
        // Workaround for https://app.asana.com/1/137249556945/project/1204099484721401/task/1209931387442142
        // On fast redirections, the webview maybe still loading the old page, when simulated request is sent
        // A more robust KVO fix did not work as observation misses events in fast redirections
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            webView.loadSimulatedRequest(newRequest, responseHTML: html)
        }
    }
}

// MARK: - Favicons

extension DuckURLSchemeHandler {
    /**
     * This handler supports special Duck favicon URLs and uses `FaviconManager`
     * to return a favicon in response, based on the actual favicon URL that's
     * encoded in the URL path.
     *
     * Favicon images are decoded lazily, so this awaits the decode (via the async
     * `getCachedFavicon`) and completes the scheme task once the image is ready —
     * rather than returning a cache-missed `HTTP 404` that the web layer would cache.
     * If no favicon exists, an `HTTP 404` response is returned.
     */
    func handleFavicon(urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            assertionFailure("No URL for Favicon scheme handler")
            return
        }

        /**
         * Favicon URL has the format of `duck://favicon/<url_percent_encoded_favicon_url>`.
         * Calling `requestURL.path` drops leading `duck://favicon` and automatically
         * handles percent-encoding. We only need to drop the leading forward slash to get the favicon URL.
         */
        guard let faviconURL = requestURL.path.dropping(prefix: "/").url else {
            assertionFailure("Favicon URL malformed \(requestURL.path.dropping(prefix: "/"))")
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask)
        runningFaviconTasks.insert(taskID)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let favicon = await self.faviconManager.resolvedCachedFavicon(for: faviconURL, sizeCategory: .medium, fallBackToSmaller: true)

            // The task may have been stopped while we awaited the decode; `remove` returns nil if so.
            guard self.runningFaviconTasks.remove(taskID) != nil else { return }

            guard let (response, data) = self.response(for: requestURL, favicon: favicon) else {
                urlSchemeTask.didFailWithError(URLError(.badServerResponse))
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    private func response(for requestURL: URL, favicon: Favicon?) -> (URLResponse, Data)? {
        guard let imagePNGData = favicon?.image?.pngData() else {
            guard let response = HTTPURLResponse(url: requestURL, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) else {
                return nil
            }
            onFaviconMissing()
            return (response, Data())
        }
        let response = URLResponse(url: requestURL, mimeType: "image/png", expectedContentLength: imagePNGData.count, textEncodingName: nil)
        return (response, imagePNGData)
    }

    private func onFaviconMissing() {
        NotificationCenter.default.post(name: .missingBookmarkFaviconEncountered, object: nil)
    }
}

// MARK: - Custom Background Images

private extension DuckURLSchemeHandler {
    /**
     * This handler supports Duck custom background image URL and uses `UserBackgroundImagesManager`
     * to return an image in response, based on the image ID (file name) that's the last component of the URL path.

     * Custom Background image has the format of `duck://new-tab/background/images/<file_name>`.
     * Custom Background image thumbnail has the format of `duck://new-tab/background/thumbnails/<file_name>`.
     *
     * If an image is not found, an `HTTP 404` response is returned.
     */
    func handleCustomBackgroundImage(urlSchemeTask: WKURLSchemeTask, isThumbnail: Bool = false) {
        guard let requestURL = urlSchemeTask.request.url else {
            assertionFailure("No URL for Favicon scheme handler")
            return
        }

        let fileName = requestURL.lastPathComponent

        guard let (response, data) = response(for: requestURL, withFileName: fileName, isThumbnail: isThumbnail) else { return }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func response(for requestURL: URL, withFileName fileName: String, isThumbnail: Bool) -> (URLResponse, Data)? {
        guard let userBackgroundImagesManager,
              let userBackgroundImage = userBackgroundImagesManager.availableImages.first(where: { $0.fileName == fileName }),
              let image = isThumbnail ? userBackgroundImagesManager.thumbnailImage(for: userBackgroundImage) : userBackgroundImagesManager.image(for: userBackgroundImage),
              let imageJPEGData = image.jpegData()
        else {
            guard let response = HTTPURLResponse(url: requestURL, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) else {
                return nil
            }
            return (response, Data())
        }

        let response = URLResponse(url: requestURL, mimeType: "image/jpeg", expectedContentLength: imageJPEGData.count, textEncodingName: nil)
        return (response, imageJPEGData)
    }
}

// MARK: - Onboarding & Release Notes
private extension DuckURLSchemeHandler {
    func handleSpecialPages(urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            assertionFailure("No URL for Special Pages scheme handler")
            return
        }
        guard let (response, data) = response(for: requestURL) else { return }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func response(for url: URL) -> (URLResponse, Data)? {
        var fileName = "index"
        var fileExtension = "html"
        var directoryURL: URL
        if url.isOnboarding {
            directoryURL = URL(fileURLWithPath: "/pages/onboarding")
        } else if url.isReleaseNotes {
            directoryURL = URL(fileURLWithPath: "/pages/release-notes")
        } else if url.isNewTabPage {
            directoryURL = URL(fileURLWithPath: "/pages/new-tab")
        } else if url.isHistory {
            directoryURL = URL(fileURLWithPath: "/pages/history")
        } else {
            assertionFailure("Unknown scheme")
            return nil
        }
        directoryURL.appendPathComponent(url.path)

        if !directoryURL.pathExtension.isEmpty {
            fileExtension = directoryURL.pathExtension
            directoryURL.deletePathExtension()
            fileName = directoryURL.lastPathComponent
            directoryURL.deleteLastPathComponent()
        }

        guard let file = ContentScopeScripts.Bundle.path(forResource: fileName, ofType: fileExtension, inDirectory: directoryURL.path) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, Data())
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
            return nil
        }

        let headerFields: [String: String] = [
            "Content-type": mimeType(for: fileExtension),
            "Content-length": String(data.count)
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headerFields) else {
            return nil
        }

        return (response, data)
    }

    func mimeType(for fileExtension: String) -> String {
        switch fileExtension {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "text/javascript"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "riv": return "application/octet-stream"
        case "json", "map": return "application/json"
        case "mp4": return "video/mp4"
        case "otf": return "font/otf"
        default:
            assertionFailure("Unknown MIME type for \"\(fileExtension)\" file extension")
            return "application/octet-stream"
        }
    }

}

// MARK: Error Page
private extension DuckURLSchemeHandler {
    func handleErrorPage(urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            assertionFailure("No URL for error page scheme handler")
            return
        }

        guard let (failingUrl: failingUrl, reason: reason, token: token) = requestURL.specialErrorPageParameters,
              URLTokenValidator.shared.validateToken(token, for: failingUrl) else {
            urlSchemeTask.didFailWithError(URLError(.badURL, userInfo: [
                NSURLErrorFailingURLErrorKey: requestURL,
                NSLocalizedDescriptionKey: Bundle(for: URLSession.self).localizedString(forKey: "Err-1000", value: "bad URL", table: "Localizable")
            ]))
            return
        }
        let threatKind: MaliciousSiteProtection.ThreatKind = switch reason {
        case .malware: .malware
        case .phishing: .phishing
        case .scam: .scam
        case .ssl: {
            assertionFailure("SSL error page is handled with NSURLError: NSURLErrorServerCertificateUntrusted error")
            return .phishing
        }()
        }

        let error = MaliciousSiteError(threat: threatKind, failingUrl: failingUrl)
        urlSchemeTask.didFailWithError(error)
    }
}

private extension URL {

    enum URLType {
        case newTab
        case history
        case favicon
        case favicons
        case permissions
        case customBackgroundImage
        case customBackgroundImageThumbnail
        case onboarding
        case duckPlayer
        case releaseNotes
        case error
    }

    var type: URLType? {
        if self.isDuckPlayer {
            return .duckPlayer
        } else if self.isOnboarding {
            return .onboarding
        } else if self.isErrorURL {
            return .error
        } else if self.isReleaseNotes {
            return .releaseNotes
        } else if self.isNewTabPage {
            if self.isCustomBackgroundImage {
                return .customBackgroundImage
            }
            if self.isCustomBackgroundImageThumbnail {
                return .customBackgroundImageThumbnail
            }
            return .newTab
        } else if self.isFavicon {
            return .favicon
        } else if self.isFavicons {
            return .favicons
        } else if self.isPermissions {
            return .permissions
        } else if self.isHistory {
            return .history
        } else {
            return nil
        }
    }

    var isOnboarding: Bool {
        return isDuckURLScheme && host == "onboarding"
    }

    var isNewTabPage: Bool {
        return isDuckURLScheme && host == "newtab"
    }

    var isReleaseNotes: Bool {
        return isDuckURLScheme && host == "release-notes"
    }

    var isFavicon: Bool {
        return isDuckURLScheme && host == "favicon"
    }

    var isCustomBackgroundImage: Bool {
        return isNewTabPage && pathComponents.prefix(3) == ["/", "background", "images"]
    }

    var isCustomBackgroundImageThumbnail: Bool {
        return isNewTabPage && pathComponents.prefix(3) == ["/", "background", "thumbnails"]
    }

}
