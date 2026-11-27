//
//  FaviconRasterizer.swift
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

import CoreImage
import DDGError
import FeatureFlags_macOS
import Foundation
import OSLog
import PixelKit
import PrivacyConfig
import WebKit

/// Rasterizes favicon data that CoreImage can't decode (SVG and PDF) to PNG using WebKit.
///
/// `NSImage(data:)` renders SVG with CoreSVG, which overflows the stack (an uncatchable crash) on some
/// filtered SVGs. WebKit renders SVG with its own engine, treats it as an inert image (no scripts, no
/// external loads), and does it in the web content process, so a rendering failure can't take the app down.
///
/// The image is drawn into a canvas by an `<img>` element in a private, non-persistent web view that
/// shows no page: nothing from a visited page (scripts, Content Security Policy, a busy main thread) takes
/// part in the rendering, and the page can't observe it. The web view is released after a period of inactivity.
@MainActor
final class FaviconRasterizer {

    enum RasterizationError: DDGError {
        case dataTooLarge
        /// The data is neither a PDF nor SVG-like (see `Data.looksLikeSVG`), so it never reaches the web view.
        case unsupportedData
        case invalidResult
        /// WebKit loaded the data and it isn't an image.
        case undecodable
        /// The caller gave up waiting for the web view.
        case timedOut
        /// The web view reported that the image didn't load in time, so it may still be busy with it.
        case scriptTimedOut

        static var errorDomain: String { "com.duckduckgo.favicons.rasterization" }

        var errorCode: Int {
            switch self {
            case .dataTooLarge: return 1
            case .unsupportedData: return 2
            case .invalidResult: return 3
            case .undecodable: return 4
            case .timedOut: return 5
            case .scriptTimedOut: return 6
            }
        }

        var description: String {
            switch self {
            case .dataTooLarge: return "The favicon data is larger than the limit"
            case .unsupportedData: return "The favicon data is neither an SVG nor a PDF"
            case .invalidResult: return "The web view returned no image"
            case .undecodable: return "The favicon data could not be decoded as an image"
            case .timedOut: return "The web view did not answer in time"
            case .scriptTimedOut: return "The image did not load in time"
            }
        }
    }

    /// The largest input accepted, the same limit the favicon downloader applies.
    nonisolated static let maxDataSize = 1024 * 1024
    /// Vector images are rasterized at their intrinsic longest side raised to this value, so a small SVG
    /// stays sharp where it's displayed at the maximum stored size.
    nonisolated static let minPixelSize = 64
    /// ...and capped at this value.
    nonisolated static let maxPixelSize = 256
    /// Time the rendering gets in the web view, enforced by the page script.
    nonisolated static let timeout: TimeInterval = 5
    /// Time after which the caller stops waiting even if the web view never answers.
    nonisolated static let defaultHardTimeout: TimeInterval = timeout + 2
    /// How long the web view (and its web content process) stays alive after the last call.
    nonisolated static let defaultIdleLifetime: TimeInterval = 30

    /// Settable so tests can shorten them.
    var hardTimeout: TimeInterval
    var idleLifetime: TimeInterval
    var scriptTimeout: TimeInterval

    /// Creates the configuration the web view starts from. Tests replace it to observe the web view's requests.
    var makeConfiguration: () -> WKWebViewConfiguration = { WKWebViewConfiguration() }

    nonisolated(unsafe) private let featureFlagger: FeatureFlagger

    /// Whether favicons are rendered with WebKit (the temporary `faviconWebKitSVGRendering` flag).
    /// When off, `storableImage` and the import helpers keep the legacy decoding, `NSImage(data:)`.
    var isEnabled: Bool { featureFlagger.isFeatureOn(.faviconWebKitSVGRendering) }

    nonisolated(unsafe) private let pixelFiring: PixelFiring?

    nonisolated init(featureFlagger: FeatureFlagger,
                     pixelFiring: PixelFiring? = PixelKit.shared,
                     hardTimeout: TimeInterval = FaviconRasterizer.defaultHardTimeout,
                     idleLifetime: TimeInterval = FaviconRasterizer.defaultIdleLifetime,
                     scriptTimeout: TimeInterval = FaviconRasterizer.timeout) {
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.hardTimeout = hardTimeout
        self.idleLifetime = idleLifetime
        self.scriptTimeout = scriptTimeout
    }

    /// Whether a web view (and its web content process) is currently alive.
    var hasWebView: Bool { webView != nil }

    /// The current web view, for tests.
    var currentWebView: WKWebView? { webView }

    private var webView: WKWebView?
    private var activeCalls = 0
    private var releaseTask: Task<Void, Never>?

    /// Returns PNG data of the image rendered at its intrinsic size, within `minPixelSize...maxPixelSize`.
    /// Throws if WebKit can't decode the data as an image or doesn't answer in time.
    ///
    /// When the web view itself fails (it doesn't answer in time, or its web content process is gone), it is
    /// discarded so that the next call starts with a fresh one instead of reusing a dead or busy process.
    func rasterize(_ data: Data) async throws -> Data {
        guard data.count <= Self.maxDataSize else { throw RasterizationError.dataTooLarge }
        guard data.isPDFData || data.looksLikeSVG else {
            Logger.favicons.debug("FaviconRasterizer: the data is neither a PDF nor an SVG, skipping it")
            throw RasterizationError.unsupportedData
        }
        try Task.checkCancellation()

        let webView = acquireWebView()
        defer { releaseWebViewWhenIdle() }

        do {
            return try await withHardTimeout { [self] in
                try await render(data, in: webView)
            }
        } catch {
            handle(failure: error, of: webView)
            throw error
        }
    }

    /// Logs a failed rendering and discards the web view when the web view itself failed. When its web content
    /// process terminated, a pixel is fired too.
    func handle(failure error: Error, of failedWebView: WKWebView) {
        guard !(error is CancellationError) else { return }

        guard Self.isWebViewFailure(error) else {
            Logger.favicons.debug("FaviconRasterizer: the data could not be rendered as an image")
            return
        }
        // The calls in flight on a failed web view all fail together. The first one handles it.
        guard webView === failedWebView else { return }

        Logger.favicons.error("FaviconRasterizer: the web view failed (\(error.localizedDescription)), discarding it")
        if Self.isProcessTermination(error) {
            pixelFiring?.fire(FaviconPixel.svgRenderingProcessTerminated(error: error), frequency: .dailyAndCount)
        }
        discardWebView(failedWebView)
    }

    private static func isProcessTermination(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == WKError.errorDomain && nsError.code == WKError.webContentProcessTerminated.rawValue
    }

    /// Data that isn't an image leaves the web view healthy; a timeout, or anything unexpected, doesn't.
    private static func isWebViewFailure(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let error = error as? RasterizationError {
            return error == .timedOut || error == .scriptTimedOut
        }
        let nsError = error as NSError
        let isScriptException = nsError.domain == WKError.errorDomain
            && nsError.code == WKError.javaScriptExceptionOccurred.rawValue
        return !isScriptException
    }

    /// Drops the failed web view and ends its web content process. Releasing the web view is not enough: the call in
    /// flight keeps it, and a process stuck in a rendering never exits on its own.
    private func discardWebView(_ failedWebView: WKWebView) {
        webView = nil
        guard failedWebView.responds(to: Selector.killWebContentProcessAndResetState) else { return }
        failedWebView.perform(Selector.killWebContentProcessAndResetState)
    }

    private enum Selector {
        static let killWebContentProcessAndResetState = NSSelectorFromString("_killWebContentProcessAndResetState")
    }

    private func acquireWebView() -> WKWebView {
        releaseTask?.cancel()
        releaseTask = nil
        activeCalls += 1
        if let webView {
            return webView
        }
        let newWebView = makeWebView()
        Logger.favicons.debug("FaviconRasterizer: created a web view")
        webView = newWebView
        return newWebView
    }

    /// A web view that can do nothing but draw the image it is given: no stored data or credentials, no scripts from
    /// web content, no windows, and every navigation and authentication challenge is refused.
    func makeWebView() -> WKWebView {
        let configuration = makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = navigationGuard
        return newWebView
    }

    private let navigationGuard = NavigationGuard()

    /// Refuses everything the web view could load or ask for. The rendering needs neither.
    private final class NavigationGuard: NSObject, WKNavigationDelegate {

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func releaseWebViewWhenIdle() {
        activeCalls -= 1
        guard activeCalls == 0 else { return }
        let idleLifetime = self.idleLifetime
        releaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(idleLifetime * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            Logger.favicons.debug("FaviconRasterizer: releasing the idle web view")
            webView = nil
        }
    }

    private func render(_ data: Data, in webView: WKWebView) async throws -> Data {
        let arguments: [String: Any] = [
            "base64": data.base64EncodedString(),
            "mimeType": data.isPDFData ? "application/pdf" : "image/svg+xml",
            "minSize": Self.minPixelSize,
            "maxSize": Self.maxPixelSize,
            "timeoutMs": Int(scriptTimeout * 1000),
        ]
        let result = try await webView.callAsyncJavaScript(Self.script,
                                                           arguments: arguments,
                                                           in: nil,
                                                           contentWorld: .defaultClient)
        guard let result = result as? [String: Any] else { throw RasterizationError.invalidResult }
        if let failure = result["error"] as? String {
            throw failure == "timeout" ? RasterizationError.scriptTimedOut : RasterizationError.undecodable
        }
        guard let base64 = result["png"] as? String, let png = Data(base64Encoded: base64), !png.isEmpty else {
            throw RasterizationError.invalidResult
        }
        return png
    }

    /// `callAsyncJavaScript` can't be cancelled, so the caller is released by whichever of the work, the timer
    /// and the cancellation of the calling task comes first (a task group would wait for the work).
    private func withHardTimeout(_ work: @escaping @MainActor () async throws -> Data) async throws -> Data {
        let outcome = Outcome()
        let hardTimeout = self.hardTimeout
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                outcome.timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(hardTimeout * 1_000_000_000))
                    outcome.finish(.failure(RasterizationError.timedOut))
                }
                Task {
                    do {
                        outcome.finish(.success(try await work()))
                    } catch {
                        outcome.finish(.failure(error))
                    }
                }
                outcome.attach(continuation)
            }
        } onCancel: {
            Task { @MainActor in outcome.finish(.failure(CancellationError())) }
        }
    }

    /// Delivers the first result to the continuation, once, even when it arrives before the continuation does.
    @MainActor
    private final class Outcome {
        private var continuation: CheckedContinuation<Data, Error>?
        private var result: Result<Data, Error>?
        private var isDelivered = false
        var timer: Task<Void, Never>?

        func attach(_ continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
            deliverIfPossible()
        }

        func finish(_ result: Result<Data, Error>) {
            guard self.result == nil else { return }
            self.result = result
            timer?.cancel()
            deliverIfPossible()
        }

        private func deliverIfPossible() {
            guard !isDelivered, let continuation, let result else { return }
            isDelivered = true
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    /// `<img>` + canvas. The image is loaded from a `data:` URL, which doesn't taint the canvas.
    private static let script = """
    const image = new Image();
    const loaded = new Promise((resolve) => {
        image.onload = () => resolve('loaded');
        image.onerror = () => resolve('undecodable');
    });
    const timeout = new Promise((resolve) => setTimeout(() => resolve('timeout'), timeoutMs));
    image.src = 'data:' + mimeType + ';base64,' + base64;
    const outcome = await Promise.race([loaded, timeout]);
    if (outcome !== 'loaded') {
        return { error: outcome };
    }

    let width = image.naturalWidth;
    let height = image.naturalHeight;
    if (!width || !height) {
        width = minSize;
        height = minSize;
    }
    const longestSide = Math.max(width, height);
    const target = Math.min(Math.max(longestSide, minSize), maxSize);
    const scale = target / longestSide;

    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    return { png: canvas.toDataURL('image/png').split(',')[1] };
    """
}

extension Data {

    /// Returns whether the data is a PDF: it starts with the `%PDF-` magic.
    ///
    /// Only the very start counts, like the magic of other image formats. It selects the MIME type WebKit
    /// loads the data with: PDF needs `application/pdf`, anything else is loaded as SVG.
    var isPDFData: Bool {
        starts(with: Data("%PDF-".utf8))
    }
}

extension Data {

    /// How many leading bytes are searched for `<svg`. Editors put comments, a DOCTYPE and metadata before the root
    /// element, and a few KB cover them.
    static let svgSniffLength = 8192

    /// Returns whether the first `svgSniffLength` bytes contain `<svg`, ignoring case, in UTF-8 (the BOM is
    /// harmless) or in UTF-16 with a byte order mark.
    ///
    /// This only spares the web view for data that can't be an SVG (an HTML error page, a truncated file). It is not
    /// a safety check: WebKit renders whatever passes, and anything that fails to render is dropped.
    var looksLikeSVG: Bool {
        let head = prefix(Self.svgSniffLength)
        let isUTF16 = head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF])
        let text = isUTF16 ? String(data: head, encoding: .utf16) : String(bytes: head, encoding: .isoLatin1)
        return text?.lowercased().contains("<svg") ?? false
    }
}

/// Favicon data read from another browser's database, to be imported.
protocol ImportedFaviconDataProviding {
    var imageData: Data { get }
}

extension FaviconRasterizer {

    /// How many imported favicons are decoded at once. Raster data is decoded off the main thread, and
    /// SVG renders queue up in the single web view, so the limit keeps each render well inside `hardTimeout`.
    nonisolated static let importConcurrency = 4

    /// Returns an image to store for the given favicon data.
    ///
    /// With the `faviconWebKitSVGRendering` flag on, raster data is decoded as is, on the calling executor (not
    /// the main thread), and data CoreImage can't decode (SVG, PDF) is rendered by WebKit, because `NSImage(data:)`
    /// would keep a lazy SVG that CoreSVG renders later, while archiving, and CoreSVG can crash. With the flag
    /// off, the legacy `NSImage(data:)` is used. Returns nil if the data can't be decoded.
    nonisolated func storableImage(from data: Data) async -> NSImage? {
        guard await isEnabled else { return NSImage(data: data) }
        return await renderedImage(from: data)
    }

    private nonisolated func renderedImage(from data: Data) async -> NSImage? {
        if CIImage(data: data) != nil {
            return NSImage(data: data)
        }
        guard let png = try? await rasterize(data) else { return nil }
        return NSImage(dataUsingCIImage: png, maxPixelSize: NSImage.maxStoredFaviconPixelSize)
    }

    /// Builds the favicons to store for each page URL read from another browser's favicon database.
    ///
    /// The databases return one row per page and icon, so one icon repeats for every page that uses it. Each distinct
    /// image data is decoded once, and the pages that use it share the resulting image.
    nonisolated func favicons<F: ImportedFaviconDataProviding>(fromImported faviconsByPageURL: [String: [F]]) async -> [URL: [Favicon]] {
        var distinctDatas = [Data]()
        var indexesByData = [Data: Int]()
        var pages = [(url: URL, imageIndexes: [Int])]()
        for (pageURLString, importedFavicons) in faviconsByPageURL {
            guard let pageURL = URL(string: pageURLString) else { continue }
            let imageIndexes = importedFavicons.map { imported -> Int in
                if let index = indexesByData[imported.imageData] { return index }
                indexesByData[imported.imageData] = distinctDatas.count
                distinctDatas.append(imported.imageData)
                return distinctDatas.count - 1
            }
            pages.append((pageURL, imageIndexes))
        }

        let images = await storableImages(from: distinctDatas, isEnabled: await isEnabled)

        var faviconsByDocument = [URL: [Favicon]]()
        for page in pages {
            faviconsByDocument[page.url] = page.imageIndexes.map { imageIndex in
                Favicon(identifier: UUID(),
                        url: page.url,
                        image: images[imageIndex],
                        relation: .icon,
                        documentUrl: page.url,
                        dateCreated: Date())
            }
        }
        return faviconsByDocument
    }

    /// `NSImage` is `Sendable` only from macOS 14. Each image is created by one task and then only handed on.
    private struct DecodedImage: @unchecked Sendable {
        let index: Int
        let image: NSImage?
    }

    /// Decodes the favicons with at most `importConcurrency` in flight, keeping the order of `datas`.
    private nonisolated func storableImages(from datas: [Data], isEnabled: Bool) async -> [NSImage?] {
        guard isEnabled else { return datas.map { NSImage(data: $0) } }
        return await withTaskGroup(of: DecodedImage.self) { group in
            var images = [NSImage?](repeating: nil, count: datas.count)
            var nextIndex = 0

            while nextIndex < min(Self.importConcurrency, datas.count) {
                let index = nextIndex
                group.addTask { DecodedImage(index: index, image: await self.renderedImage(from: datas[index])) }
                nextIndex += 1
            }
            for await decoded in group {
                images[decoded.index] = decoded.image
                guard nextIndex < datas.count else { continue }
                let index = nextIndex
                group.addTask { DecodedImage(index: index, image: await self.renderedImage(from: datas[index])) }
                nextIndex += 1
            }
            return images
        }
    }
}
