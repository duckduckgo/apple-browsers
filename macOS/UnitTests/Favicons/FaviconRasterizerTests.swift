//
//  FaviconRasterizerTests.swift
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
@_spi(Testing) import PixelKit
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class FaviconRasterizerTests: XCTestCase {

    private typealias Fixtures = FaviconTestFixtures

    /// The hard timeout of the tests that wait for it. The first render of a rasterizer also launches the web content
    /// process, which took over a second on a CI machine, so the allowance is several times that.
    private static let slowRenderAllowance: TimeInterval = 5

    private var webViews: WebViewTracker!
    private var rasterizer: FaviconRasterizer!

    override func setUp() {
        super.setUp()
        webViews = WebViewTracker()
        rasterizer = Fixtures.makeRasterizer(didCreateWebView: webViews.record)
    }

    override func tearDown() {
        rasterizer = nil
        webViews = nil
        super.tearDown()
    }

    // MARK: - Rasterization

    func testRasterizesSVGThatCrashesCoreSVG() async throws {
        let png = try await rasterizer.rasterize(Data(Fixtures.recursiveFilterSVG.utf8))

        let image = try decode(png)
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testSmallSVGIsRasterizedAtMinimumSizeToStaySharp() async throws {
        let png = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))

        XCTAssertEqual(try decode(png).size, NSSize(width: 64, height: 64))
    }

    func testLargeSVGIsCappedAtMaximumSize() async throws {
        let png = try await rasterizer.rasterize(Data(Fixtures.svg(width: 1024, height: 512).utf8))

        XCTAssertEqual(try decode(png).size, NSSize(width: 256, height: 128))
    }

    func testSVGWithoutIntrinsicSizeUsesViewBoxAspectRatio() async throws {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 20"><rect width="10" height="20" fill="#000"/></svg>"##

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        // The intrinsic size WebKit reports for such an SVG differs between OS versions; the aspect ratio doesn't.
        let size = try decode(png).size
        XCTAssertEqual(size.width / size.height, 0.5, accuracy: 0.02)
        XCTAssertTrue((64...256).contains(size.height))
    }

    func testSVGWithOnlyWidthIsRasterizedWithinTheSizeLimits() async throws {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="32"><rect width="32" height="16" fill="#000"/></svg>"##

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        let image = try decode(png)
        XCTAssertTrue((64...256).contains(max(image.size.width, image.size.height)))
        XCTAssertLessThanOrEqual(min(image.size.width, image.size.height), 256)
        XCTAssertTrue(image.hasVisiblePixels())
    }

    /// AppKit ignores CSS in SVG and renders this one fully transparent; WebKit applies it.
    func testSVGColoredOnlyWithCSSHasVisiblePixels() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" fill="none">
          <style>:root { fill: #000; }</style>
          <rect x="10" y="10" width="160" height="160"/>
        </svg>
        """

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
    }

    /// The same crashing SVG in other encodings and behind a long prolog. What matters is that none of them reaches
    /// CoreSVG: each one is either rendered by WebKit or refused before it reaches the web view.
    func testSVGInOtherEncodingsIsRenderedByWebKitOrRefused() async throws {
        let svg = Fixtures.recursiveFilterSVG
        let shortProlog = "<!--" + String(repeating: "x", count: 4000) + "-->"
        let longProlog = "<!--" + String(repeating: "x", count: Data.svgSniffLength) + "-->"
        let rendered: [String: Data] = try [
            "UTF-8": Data(svg.utf8),
            "UTF-8 with a BOM": Data([0xEF, 0xBB, 0xBF]) + Data(svg.utf8),
            "UTF-16 with a byte order mark": XCTUnwrap(svg.data(using: .utf16)),
            "a prolog within the sniffed bytes": Data((shortProlog + svg).utf8)
        ]
        let refused: [String: Data] = try [
            "UTF-16 little endian without a byte order mark": XCTUnwrap(svg.data(using: .utf16LittleEndian)),
            "UTF-16 big endian without a byte order mark": XCTUnwrap(svg.data(using: .utf16BigEndian)),
            "a prolog longer than the sniffed bytes": Data((longProlog + svg).utf8),
            "UTF-7": Data("+ADw-svg xmlns=+ACI-http://www.w3.org/2000/svg+ACI- filter=+ACI-url(+ACM-f)+ACI-+AD4-+ADw-/svg+AD4-".utf8)
        ]

        for (name, data) in rendered {
            let png = try await rasterizer.rasterize(data)
            XCTAssertTrue(try decode(png).hasVisiblePixels(), name)
        }
        for (name, data) in refused {
            do {
                _ = try await rasterizer.rasterize(data)
                XCTFail("\(name) should be refused")
            } catch {
                XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .unsupportedData, name)
            }
        }
    }

    func testThrowsForDataLargerThanTheLimit() async {
        let data = Data(Fixtures.svg(width: 16, height: 16).utf8) + Data(repeating: UInt8(ascii: " "), count: FaviconRasterizer.maxDataSize)
        do {
            _ = try await rasterizer.rasterize(data)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .dataTooLarge)
        }
    }

    func testConcurrentCallsAreAllRasterized() async throws {
        let data = Data(Fixtures.recursiveFilterSVG.utf8)

        async let first = rasterizer.rasterize(data)
        async let second = rasterizer.rasterize(data)
        async let third = rasterizer.rasterize(data)
        let results = try await [first, second, third]

        XCTAssertTrue(try results.allSatisfy { try decode($0).hasVisiblePixels() })
    }

    // MARK: - PDF

    func testPDFIsRecognizedOnlyByTheMagicAtOffsetZero() {
        let pdf = Fixtures.pdfData()
        XCTAssertTrue(pdf.isPDFData)
        XCTAssertFalse((Data(" ".utf8) + pdf).isPDFData)
        XCTAssertFalse((Data(repeating: 0x20, count: 100) + pdf).isPDFData)
        XCTAssertFalse(Data(Fixtures.svg(width: 16, height: 16).utf8).isPDFData)
        XCTAssertFalse(Data("not an image".utf8).isPDFData)
        XCTAssertFalse(Data().isPDFData)
    }

    func testPDFIsRenderedByWebKitToABitmap() async throws {
        let pdf = Fixtures.pdfData()
        XCTAssertNil(CIImage(data: pdf), "The fixture must be data CoreImage can't decode")

        let png = try await rasterizer.rasterize(pdf)

        let image = try decode(png)
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    // MARK: - Input check

    func testDataThatIsNeitherPDFNorSVGDoesNotReachTheWebView() async {
        let html = Data("<html><body>Not found</body></html>".utf8)
        do {
            _ = try await rasterizer.rasterize(html)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .unsupportedData)
        }
        XCTAssertFalse(rasterizer.hasWebView)
    }

    func testLooksLikeSVGSniffsTheFirstBytes() throws {
        let svg = Fixtures.svg(width: 16, height: 16)
        let padding = { (count: Int) in String(repeating: " ", count: count) }
        XCTAssertTrue(Data(svg.utf8).looksLikeSVG)
        XCTAssertTrue(Data(svg.uppercased().utf8).looksLikeSVG)
        XCTAssertTrue((Data([0xEF, 0xBB, 0xBF]) + Data(svg.utf8)).looksLikeSVG)
        XCTAssertTrue(try XCTUnwrap(svg.data(using: .utf16)).looksLikeSVG)
        XCTAssertTrue(Data(("<?xml version=\"1.0\"?><!-- " + String(repeating: "x", count: 4000) + " -->" + svg).utf8).looksLikeSVG)
        XCTAssertTrue(Data((padding(Data.svgSniffLength - 4) + svg).utf8).looksLikeSVG, "`<svg` ends at the last sniffed byte")
        XCTAssertFalse(Data((padding(Data.svgSniffLength - 3) + svg).utf8).looksLikeSVG, "`<svg` straddles the end of the sniffed bytes")
        XCTAssertFalse(Data((padding(Data.svgSniffLength) + svg).utf8).looksLikeSVG)
        XCTAssertFalse(Data("<html><body>Not found</body></html>".utf8).looksLikeSVG)
        XCTAssertFalse(Data("not an image".utf8).looksLikeSVG)
        XCTAssertFalse(Data().looksLikeSVG)
    }

    // MARK: - Isolation

    /// Scripts, windows and stored data can't be observed from outside: an SVG loaded through `<img>` never runs
    /// scripts or loads resources whatever the configuration is. So the configuration is read back.
    func testWebViewHasNoStoredDataNoScriptsAndNoWindows() async throws {
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(webViews.latest)

        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
    }

    /// An SVG that references the network, and a navigation attempt, must not make a request. The scheme handler sees
    /// every http(s) request of the web views it configures; the control shows that it does see requests.
    func testRenderingAnSVGThatReferencesTheNetworkMakesNoRequests() async throws {
        let recorder = RequestRecorder()

        let control = WKWebView(frame: .zero, configuration: recorder.handler.webViewConfiguration())
        control.loadHTMLString(#"<img src="http://probe.example/control.png">"#, baseURL: URL(string: "http://probe.example/"))
        let controlWasSeen = await waitUntil { !recorder.paths.isEmpty }
        XCTAssertTrue(controlWasSeen, "The scheme handler doesn't see the web view's requests")
        recorder.reset()

        let rasterizer = Fixtures.makeRasterizer(makeConfiguration: { recorder.handler.webViewConfiguration() },
                                                 didCreateWebView: webViews.record)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64">
          <style>@import url(http://probe.example/style.css);</style>
          <script>fetch('http://probe.example/script'); new Image().src = 'http://probe.example/script-image';</script>
          <image href="http://probe.example/image.png" width="64" height="64"/>
          <use xlink:href="http://probe.example/use.svg#u"/>
          <circle r="8" fill="url(http://probe.example/paint.svg#p)"/>
          <rect width="64" height="64" fill="#000"/>
        </svg>
        """

        let png = try await rasterizer.rasterize(Data(svg.utf8))
        let webView = try XCTUnwrap(webViews.latest)
        webView.load(URLRequest(url: try XCTUnwrap(URL(string: "http://probe.example/page"))))
        webView.loadHTMLString("<html><title>page</title></html>", baseURL: URL(string: "http://probe.example/"))
        // Nothing is expected to happen, so there is nothing to wait for but a grace period.
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(try decode(png).hasVisiblePixels())
        XCTAssertEqual(recorder.paths, [])
        XCTAssertNil(webView.url)
        XCTAssertFalse(webView.isLoading)
    }

    // MARK: - Failures

    /// A render that hangs the web content process is given up after the hard timeout. The process is ended, which
    /// is not a crash, and the next call renders on a new web view.
    func testHardTimeoutThrowsEndsTheProcessAndTheNextCallRecovers() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Fixtures.makeRasterizer(pixelFiring: pixelKit,
                                                 hardTimeout: Self.slowRenderAllowance,
                                                 didCreateWebView: webViews.record)
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let hog = hogWebContentProcess(of: try XCTUnwrap(webViews.latest))
        await settle()

        do {
            _ = try await rasterizer.rasterize(Data(Fixtures.recursiveFilterSVG.utf8))
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .timedOut)
        }
        XCTAssertFalse(rasterizer.hasWebView)
        await hog.value
        let png = try await rasterizer.rasterize(Data(Fixtures.recursiveFilterSVG.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
        XCTAssertEqual(webViews.webViews.count, 2)
        // The delegate hears about the process the rasterizer ended after the call failed; nothing is expected to
        // follow, so there is nothing to wait for but a grace period.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty, "Ending the process after a timeout is not a crash")
    }

    /// One render at a time: a render that times out takes down the web view, and the calls waiting for their turn
    /// render on a new one. Their own timeout doesn't run while they wait.
    func testATimeoutDoesNotFailTheCallsWaitingBehindIt() async throws {
        let rasterizer = Fixtures.makeRasterizer(hardTimeout: Self.slowRenderAllowance, didCreateWebView: webViews.record)
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let hog = hogWebContentProcess(of: try XCTUnwrap(webViews.latest))
        await settle()
        let calls = (0..<3).map { _ in Task { try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8)) } }

        var timedOut = 0
        var rendered = 0
        for call in calls {
            do {
                let png = try await call.value
                XCTAssertTrue(try decode(png).hasVisiblePixels())
                rendered += 1
            } catch {
                XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .timedOut)
                timedOut += 1
            }
        }
        await hog.value

        XCTAssertEqual(timedOut, 1)
        XCTAssertEqual(rendered, 2)
    }

    func testDataThatFailsToDecodeThrowsAndKeepsTheWebView() async {
        let pixelKit = PixelKitMock()
        let rasterizer = Fixtures.makeRasterizer(pixelFiring: pixelKit)
        do {
            _ = try await rasterizer.rasterize(Data("<svg>broken".utf8))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .undecodable)
        }

        XCTAssertTrue(rasterizer.hasWebView)
        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
    }

    func testRasterizationErrorsHaveUniqueCodes() {
        let errors: [FaviconRasterizer.RasterizationError] = [.dataTooLarge, .unsupportedData, .invalidResult, .undecodable, .timedOut, .scriptTimedOut]

        XCTAssertEqual(Set(errors.map(\.errorCode)).count, errors.count)
    }

    /// The image of an SVG with thousands of shapes takes far longer than a millisecond to load.
    func testScriptTimeoutIsReportedAndDiscardsTheWebView() async throws {
        let shapes = (0..<12000).map { #"<rect x="\#($0 % 64)" y="\#($0 / 64)" width="1" height="1"/>"# }.joined()
        let heavySVG = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">\##(shapes)</svg>"##.utf8)
        XCTAssertLessThan(heavySVG.count, FaviconRasterizer.maxDataSize)
        let rasterizer = Fixtures.makeRasterizer(scriptTimeout: 0.001)

        do {
            _ = try await rasterizer.rasterize(heavySVG)
            XCTFail("Expected a script timeout")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .scriptTimedOut)
        }

        XCTAssertFalse(rasterizer.hasWebView)
    }

    func testWebViewIsReleasedAfterIdleLifetime() async throws {
        let rasterizer = Fixtures.makeRasterizer(idleLifetime: 0.05)
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        XCTAssertTrue(rasterizer.hasWebView)

        let released = await waitUntil { !rasterizer.hasWebView }

        XCTAssertTrue(released)
    }

    // MARK: - Cancellation

    /// A call that is stuck in a busy web view is released by the cancellation without waiting for the web view.
    func testCancellingTheCallerReleasesItWhileTheWebViewIsBusy() async throws {
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(webViews.latest)
        let hog = hogWebContentProcess(of: webView)
        await settle()
        let rasterizer = self.rasterizer!
        let call = Task { try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8)) }
        await settle()

        call.cancel()

        do {
            _ = try await call.value
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        endWebContentProcess(of: webView)
        await hog.value
    }

    /// A call waiting for its turn leaves the queue when it is cancelled, without waiting for the render in front.
    func testCancellingACallThatIsWaitingForItsTurnReleasesItAtOnce() async throws {
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(webViews.latest)
        let hog = hogWebContentProcess(of: webView)
        await settle()
        let rasterizer = self.rasterizer!
        let stuck = Task { try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8)) }
        await settle()
        let waiting = Task { try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8)) }
        await settle()

        waiting.cancel()

        do {
            _ = try await waiting.value
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        endWebContentProcess(of: webView)
        _ = try? await stuck.value
        await hog.value
    }

    // MARK: - Process termination

    /// The web content process is killed while a render is stuck in it and two more calls wait for their turn. Only
    /// the render in flight fails, the pixel is fired once, and the waiting calls render on a new web view.
    func testProcessTerminationFiresOnePixelAndOnlyFailsTheRenderInFlight() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Fixtures.makeRasterizer(pixelFiring: pixelKit, didCreateWebView: webViews.record)
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(webViews.latest)
        let processID = try XCTUnwrap(webProcessIdentifier(of: webView))
        let hog = hogWebContentProcess(of: webView)
        await settle()
        let calls = (0..<3).map { _ in Task { try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8)) } }
        await settle()

        try XCTSkipUnless(kill(processID, SIGKILL) == 0, "The test host can't signal the web content process")

        var failed = 0
        for call in calls {
            do {
                let png = try await call.value
                XCTAssertTrue(try decode(png).hasVisiblePixels())
            } catch {
                failed += 1
            }
        }
        await hog.value
        XCTAssertEqual(failed, 1)
        let pixelWasFired = await waitUntil { !pixelKit.actualFireCalls.isEmpty }
        XCTAssertTrue(pixelWasFired)
        // The pixel must not be repeated by the calls that failed along with the process, and there is nothing to
        // wait for but a grace period.
        try await Task.sleep(nanoseconds: 500_000_000)
        let fireCall = try XCTUnwrap(pixelKit.actualFireCalls.first)
        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)
        XCTAssertEqual(fireCall.pixel.name, "favicon-svg-rendering_process-terminated_macos")
        XCTAssertEqual(fireCall.frequency, .dailyAndCount)
        guard case .svgRenderingProcessTerminated(let error) = try XCTUnwrap(fireCall.pixel as? FaviconPixel) else {
            return XCTFail("Unexpected pixel")
        }
        XCTAssertEqual((error as NSError).domain, WKError.errorDomain)
        XCTAssertEqual((error as NSError).code, WKError.webContentProcessTerminated.rawValue)
        XCTAssertEqual(webViews.webViews.count, 2, "The calls that waited rendered on a new web view")
    }

    /// What WebKit tells the web view's delegate when the process ends, without ending a process: the host can't
    /// always signal the process.
    func testTerminationReportedByTheDelegateFiresOnePixelAndDiscardsTheWebView() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Fixtures.makeRasterizer(pixelFiring: pixelKit, didCreateWebView: webViews.record)
        _ = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(webViews.latest)

        webView.navigationDelegate?.webViewWebContentProcessDidTerminate?(webView)

        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.name), ["favicon-svg-rendering_process-terminated_macos"])
        XCTAssertEqual(pixelKit.actualFireCalls.first?.frequency, .dailyAndCount)
        XCTAssertFalse(rasterizer.hasWebView)
    }

    // MARK: - Helpers

    private func decode(_ png: Data) throws -> NSImage {
        try XCTUnwrap(NSImage(dataUsingCIImage: png, maxPixelSize: nil))
    }

    /// Lets the main-actor work that is already queued run up to its next suspension point: the calls started by a
    /// test reach the web view, or the queue in front of it.
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    /// Polls until `condition` holds, for at most `timeout` seconds. Returns whether it held.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// Keeps the web content process busy forever. Whatever is sent to the process after it waits behind it, so no
    /// pause is needed. The task ends when the process does.
    private func hogWebContentProcess(of webView: WKWebView) -> Task<Void, Never> {
        Task {
            _ = try? await webView.callAsyncJavaScript("while (true) {}", arguments: [:], in: nil, contentWorld: .defaultClient)
        }
    }

    /// Ends the process like the rasterizer does when it gives up on a web view.
    private func endWebContentProcess(of webView: WKWebView) {
        webView.perform(NSSelectorFromString("_killWebContentProcessAndResetState"))
    }

    private func webProcessIdentifier(of webView: WKWebView) -> pid_t? {
        let key = "_webProcessIdentifier"
        guard webView.responds(to: NSSelectorFromString(key)) else { return nil }
        return (webView.value(forKey: key) as? NSNumber)?.int32Value
    }
}

/// Records the paths of the http(s) requests that web views configured by `handler` make.
@MainActor
private final class RequestRecorder {

    private(set) var paths = [String]()
    private(set) var handler: TestSchemeHandler!

    init() {
        handler = TestSchemeHandler { [weak self] request in
            MainActor.assumeMainThread { self?.paths.append(request.url?.path ?? "") }
            return nil
        }
    }

    func reset() {
        paths = []
    }
}
