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
import FeatureFlags_macOS
@_spi(Testing) import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class FaviconRasterizerTests: XCTestCase {

    private var rasterizer: FaviconRasterizer!

    override func setUp() {
        super.setUp()
        rasterizer = Self.makeRasterizer(enabled: true)
    }

    override func tearDown() {
        rasterizer = nil
        super.tearDown()
    }

    private static func makeRasterizer(enabled: Bool, pixelFiring: PixelFiring? = nil) -> FaviconRasterizer {
        let featureFlagger = MockFeatureFlagger.enabling(enabled ? [.faviconWebKitSVGRendering] : [])
        return FaviconRasterizer(featureFlagger: featureFlagger, pixelFiring: pixelFiring)
    }

    /// A one-page PDF (`%PDF-1.x` header), which CoreImage can't decode but `NSImage(data:)` can.
    private static func pdfData() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 32, height: 32)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    // MARK: - Fixtures

    /// CoreSVG overflows the stack (`EXC_BAD_ACCESS` in `SVGFilter::draw`) when the root `<svg>` and a child
    /// reference the same filter.
    private static let recursiveFilterSVG = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" filter="url(#f)">
      <filter id="f"><feOffset/></filter>
      <rect width="64" height="64" fill="#000" filter="url(#f)"/>
    </svg>
    """##

    private static func svg(width: Int, height: Int) -> String {
        ##"<svg xmlns="http://www.w3.org/2000/svg" width="\##(width)" height="\##(height)"><rect width="\##(width)" height="\##(height)" fill="#000"/></svg>"##
    }

    // MARK: - Rasterization

    func testRasterizesSVGThatCrashesCoreSVG() async throws {
        let png = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))

        let image = try decode(png)
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testSmallSVGIsRasterizedAtMinimumSizeToStaySharp() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))

        XCTAssertEqual(try decode(png).size, NSSize(width: 64, height: 64))
    }

    func testLargeSVGIsCappedAtMaximumSize() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 1024, height: 512).utf8))

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

    /// The same SVG in other encodings and with a long prolog, which a byte scan or a sniff of the first bytes
    /// would miss. It matters only that rendering doesn't crash, whatever WebKit makes of the data.
    func testSVGInOtherEncodingsDoesNotCrash() async throws {
        let svg = Self.recursiveFilterSVG
        let prolog = "<!--" + String(repeating: "x", count: 8192) + "-->"
        let utf7 = "+ADw-svg xmlns=+ACI-http://www.w3.org/2000/svg+ACI- filter=+ACI-url(+ACM-f)+ACI-+AD4-+ADw-/svg+AD4-"
        let entity = "<!DOCTYPE svg [<!ENTITY n \"&#102;ilter\">]><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" &n;=\"url(#f)\"><filter id=\"f\"/></svg>"
        let variants: [Data] = try [
            XCTUnwrap(svg.data(using: .utf16)),
            XCTUnwrap(svg.data(using: .utf16LittleEndian)),
            XCTUnwrap(svg.data(using: .utf16BigEndian)),
            Data((prolog + svg).utf8),
            Data(utf7.utf8),
            Data(entity.utf8)
        ]

        for data in variants {
            _ = try? await rasterizer.rasterize(data)
        }
    }

    func testThrowsForDataThatIsNotAnImage() async {
        do {
            _ = try await rasterizer.rasterize(Data("not an image".utf8))
            XCTFail("Expected an error")
        } catch {}
    }

    func testThrowsForDataLargerThanTheLimit() async {
        let data = Data(Self.svg(width: 16, height: 16).utf8) + Data(repeating: UInt8(ascii: " "), count: FaviconRasterizer.maxDataSize)
        do {
            _ = try await rasterizer.rasterize(data)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .dataTooLarge)
        }
    }

    func testConcurrentCallsAreAllRasterized() async throws {
        let data = Data(Self.recursiveFilterSVG.utf8)

        async let first = rasterizer.rasterize(data)
        async let second = rasterizer.rasterize(data)
        async let third = rasterizer.rasterize(data)
        let results = try await [first, second, third]

        XCTAssertTrue(try results.allSatisfy { try decode($0).hasVisiblePixels() })
    }

    // MARK: - Feature flag off

    /// With the flag off the legacy decoding is kept: a lazy `NSImage(data:)`, which for an SVG is vector-backed.
    func testStorableImageUsesLegacyDecodingWhenTheFlagIsOff() async throws {
        let legacy = Self.makeRasterizer(enabled: false)
        let svg = Data(Self.svg(width: 16, height: 16).utf8)

        let rendered = await legacy.storableImage(from: svg)

        let image = try XCTUnwrap(rendered)
        XCTAssertFalse(image.representations.contains { $0 is NSBitmapImageRep })
        XCTAssertFalse(legacy.hasWebView)
    }

    func testImportedFaviconsUseLegacyDecodingWhenTheFlagIsOff() async throws {
        let legacy = Self.makeRasterizer(enabled: false)
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let svg = Data(Self.svg(width: 16, height: 16).utf8)
        let imported = ["https://example.com": [ImportedFavicon(imageData: png), ImportedFavicon(imageData: svg)]]

        let faviconsByDocument = await legacy.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let images = try XCTUnwrap(faviconsByDocument[url]).map(\.image)
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0 != nil })
        XCTAssertFalse(images[1]?.representations.contains { $0 is NSBitmapImageRep } ?? true)
        XCTAssertFalse(legacy.hasWebView)
    }

    // MARK: - PDF

    func testPDFIsRecognizedOnlyByTheMagicAtOffsetZero() {
        let pdf = Self.pdfData()
        XCTAssertTrue(pdf.isPDFData)
        XCTAssertFalse((Data(" ".utf8) + pdf).isPDFData)
        XCTAssertFalse((Data(repeating: 0x20, count: 100) + pdf).isPDFData)
        XCTAssertFalse(Data(Self.svg(width: 16, height: 16).utf8).isPDFData)
        XCTAssertFalse(Data("not an image".utf8).isPDFData)
        XCTAssertFalse(Data().isPDFData)
    }

    /// The data is loaded as SVG unless it starts with the PDF magic.
    func testSVGWithPDFMagicInsideIsRenderedAsSVG() async throws {
        let svg = Data(("<!-- %PDF-1.4 -->" + Self.recursiveFilterSVG).utf8)
        XCTAssertFalse(svg.isPDFData)

        let stored = await rasterizer.storableImage(from: svg)

        let image = try XCTUnwrap(stored)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testPDFIsRenderedByWebKitToABitmap() async throws {
        let pdf = Self.pdfData()
        XCTAssertNil(CIImage(data: pdf), "The fixture must be data CoreImage can't decode")

        let png = try await rasterizer.rasterize(pdf)

        let image = try decode(png)
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testStoredPDFFaviconIsABitmap() async throws {
        let stored = await rasterizer.storableImage(from: Self.pdfData())

        let image = try XCTUnwrap(stored)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(rasterizer.hasWebView)
    }

    func testImportedFaviconsWithTheSameDataShareOneImage() async throws {
        let first = Data(Self.svg(width: 100, height: 50).utf8)
        let second = Data(Self.svg(width: 50, height: 100).utf8)
        let imported = [
            "https://a.example": [ImportedFavicon(imageData: first), ImportedFavicon(imageData: second)],
            "https://b.example": [ImportedFavicon(imageData: first)],
            "https://c.example": [ImportedFavicon(imageData: second), ImportedFavicon(imageData: first)]
        ]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        func image(_ page: String, _ index: Int) throws -> NSImage {
            let url = try XCTUnwrap(URL(string: page))
            return try XCTUnwrap(faviconsByDocument[url]?[index].image)
        }
        let firstImage = try image("https://a.example", 0)
        XCTAssertEqual(firstImage.size, NSSize(width: 64, height: 32))
        XCTAssertTrue(try image("https://b.example", 0) === firstImage)
        XCTAssertTrue(try image("https://c.example", 1) === firstImage)
        let secondImage = try image("https://a.example", 1)
        XCTAssertEqual(secondImage.size, NSSize(width: 32, height: 64))
        XCTAssertTrue(try image("https://c.example", 0) === secondImage)
    }

    func testImportedPDFFaviconIsKept() async throws {
        let imported = ["https://example.com": [ImportedFavicon(imageData: Self.pdfData())]]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let image = try XCTUnwrap(faviconsByDocument[url]?.first?.image)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
    }

    // MARK: - Process termination

    func testProcessTerminationFiresAPixelAndDiscardsTheWebView() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Self.makeRasterizer(enabled: true, pixelFiring: pixelKit)
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(rasterizer.currentWebView)
        let terminated = WKError(.webContentProcessTerminated)

        rasterizer.handle(failure: terminated, of: webView)

        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.name), ["favicon-svg-rendering_process-terminated_macos"])
        XCTAssertEqual(pixelKit.actualFireCalls.first?.frequency, .dailyAndCount)
        XCTAssertFalse(rasterizer.hasWebView)
    }

    func testFailuresOfAnAlreadyDiscardedWebViewAreIgnored() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Self.makeRasterizer(enabled: true, pixelFiring: pixelKit)
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(rasterizer.currentWebView)
        let terminated = WKError(.webContentProcessTerminated)

        rasterizer.handle(failure: terminated, of: webView)
        rasterizer.handle(failure: terminated, of: webView)
        rasterizer.handle(failure: terminated, of: webView)

        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)
    }

    /// A rendering that hangs the process never returns on its own. Discarding the web view ends the process, which
    /// ends the call in flight.
    func testDiscardingTheWebViewEndsAProcessThatIsStuck() async throws {
        let rasterizer = Self.makeRasterizer(enabled: true)
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(rasterizer.currentWebView)
        let callEnded = expectation(description: "the stuck call ends")
        Task {
            _ = try? await webView.callAsyncJavaScript("while (true) {}", arguments: [:], in: nil, contentWorld: .defaultClient)
            callEnded.fulfill()
        }
        try await Task.sleep(nanoseconds: 500_000_000)

        rasterizer.handle(failure: FaviconRasterizer.RasterizationError.timedOut, of: webView)

        await fulfillment(of: [callEnded], timeout: 10)
    }

    func testOtherFailuresDoNotFireTheProcessTerminationPixel() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Self.makeRasterizer(enabled: true, pixelFiring: pixelKit)
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(rasterizer.currentWebView)

        rasterizer.handle(failure: FaviconRasterizer.RasterizationError.timedOut, of: webView)

        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
        XCTAssertFalse(rasterizer.hasWebView)
    }

    func testDecodeFailureDoesNotDiscardTheWebViewOrFireAPixel() async throws {
        let pixelKit = PixelKitMock()
        let rasterizer = Self.makeRasterizer(enabled: true, pixelFiring: pixelKit)
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(rasterizer.currentWebView)

        rasterizer.handle(failure: FaviconRasterizer.RasterizationError.undecodable, of: webView)

        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
        XCTAssertTrue(rasterizer.hasWebView)
    }

    // MARK: - Isolation

    func testWebViewHasNoStoredDataNoScriptsAndNoWindows() async throws {
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let webView = try XCTUnwrap(rasterizer.currentWebView)

        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertNotNil(webView.navigationDelegate)
    }

    /// An SVG that references the network, and a navigation attempt, must not make a request. The scheme handler sees
    /// every http(s) request of the web views it configures; the control shows that it does see requests.
    func testRenderingAnSVGThatReferencesTheNetworkMakesNoRequests() async throws {
        let recorder = RequestRecorder()

        let control = WKWebView(frame: .zero, configuration: recorder.handler.webViewConfiguration())
        control.loadHTMLString(#"<img src="http://probe.example/control.png">"#, baseURL: URL(string: "http://probe.example/"))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(recorder.paths.isEmpty, "The scheme handler doesn't see the web view's requests")
        recorder.reset()

        rasterizer.makeConfiguration = { recorder.handler.webViewConfiguration() }
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
        let webView = try XCTUnwrap(rasterizer.currentWebView)
        webView.load(URLRequest(url: try XCTUnwrap(URL(string: "http://probe.example/page"))))
        webView.loadHTMLString("<html><title>page</title></html>", baseURL: URL(string: "http://probe.example/"))
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertTrue(try decode(png).hasVisiblePixels())
        XCTAssertEqual(recorder.paths, [])
        XCTAssertNil(webView.url)
        XCTAssertFalse(webView.isLoading)
    }

    // MARK: - Failures

    func testHardTimeoutThrowsDiscardsTheWebViewAndTheNextCallRecovers() async throws {
        rasterizer.hardTimeout = 0.001
        do {
            _ = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .timedOut)
        }
        XCTAssertFalse(rasterizer.hasWebView)

        rasterizer.hardTimeout = FaviconRasterizer.defaultHardTimeout
        let png = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
    }

    func testDecodeFailureKeepsTheWebView() async throws {
        _ = try? await rasterizer.rasterize(Data("<svg>broken".utf8))

        XCTAssertTrue(rasterizer.hasWebView)
    }

    func testRasterizationErrorsHaveAStableDomainAndUniqueCodes() {
        let errors: [FaviconRasterizer.RasterizationError] = [.dataTooLarge, .unsupportedData, .invalidResult, .undecodable, .timedOut, .scriptTimedOut]

        XCTAssertEqual(Set(errors.map(\.errorCode)).count, errors.count)
        XCTAssertTrue(errors.allSatisfy { ($0 as NSError).domain == "com.duckduckgo.favicons.rasterization" })
    }

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
        let svg = Self.svg(width: 16, height: 16)
        XCTAssertTrue(Data(svg.utf8).looksLikeSVG)
        XCTAssertTrue(Data(svg.uppercased().utf8).looksLikeSVG)
        XCTAssertTrue((Data([0xEF, 0xBB, 0xBF]) + Data(svg.utf8)).looksLikeSVG)
        XCTAssertTrue(try XCTUnwrap(svg.data(using: .utf16)).looksLikeSVG)
        XCTAssertTrue(Data(("<?xml version=\"1.0\"?><!-- " + String(repeating: "x", count: 4000) + " -->" + svg).utf8).looksLikeSVG)
        XCTAssertFalse(Data((String(repeating: " ", count: Data.svgSniffLength) + svg).utf8).looksLikeSVG)
        XCTAssertFalse(Data("<html><body>Not found</body></html>".utf8).looksLikeSVG)
        XCTAssertFalse(Data("not an image".utf8).looksLikeSVG)
        XCTAssertFalse(Data().looksLikeSVG)
    }

    func testCancellingTheCallerReleasesItWithoutWaitingForTheWebView() async {
        let data = Data(Self.recursiveFilterSVG.utf8)
        let task = Task { try await rasterizer.rasterize(data) }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testWebViewIsReleasedAfterIdleLifetime() async throws {
        rasterizer.idleLifetime = 0.05
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        XCTAssertTrue(rasterizer.hasWebView)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(rasterizer.hasWebView)
    }

    func testScriptTimeoutIsReportedAndDiscardsTheWebView() async throws {
        rasterizer.scriptTimeout = 0
        var timedOut = false
        for _ in 0..<20 where !timedOut {
            do {
                _ = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))
            } catch {
                timedOut = (error as? FaviconRasterizer.RasterizationError) == .scriptTimedOut
            }
        }
        try XCTSkipUnless(timedOut, "The image always loaded before a zero script timeout fired")
        XCTAssertFalse(rasterizer.hasWebView)

        rasterizer.scriptTimeout = FaviconRasterizer.timeout
        let png = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
    }

    func testSVGWithOnlyWidthKeepsASaneSize() async throws {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="32"><rect width="32" height="16" fill="#000"/></svg>"##

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        let size = try decode(png).size
        XCTAssertTrue((64...256).contains(max(size.width, size.height)))
    }

    // MARK: - Imported favicons

    func testStorableImageDecodesRasterDataAsIs() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))

        let storable = await rasterizer.storableImage(from: png)
        let image = try XCTUnwrap(storable)

        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
    }

    func testStorableImageRendersSVGWithWebKitAndCapsItAtMaxStoredSize() async throws {
        let rendered = await rasterizer.storableImage(from: Data(Self.recursiveFilterSVG.utf8))
        let image = try XCTUnwrap(rendered)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(image.hasVisiblePixels())

        let largeImage = await rasterizer.storableImage(from: Data(Self.svg(width: 1024, height: 512).utf8))
        let large = try XCTUnwrap(largeImage)
        XCTAssertEqual(large.size, NSSize(width: 64, height: 32))
    }

    func testStorableImageIsNilForDataThatIsNotAnImage() async {
        let image = await rasterizer.storableImage(from: Data("not an image".utf8))
        XCTAssertNil(image)
    }

    func testImportedFaviconsAreBuiltPerPageURLAndSVGIsRendered() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let imported = [
            "https://example.com": [ImportedFavicon(imageData: png), ImportedFavicon(imageData: Data(Self.recursiveFilterSVG.utf8))],
            "https://broken.example": [ImportedFavicon(imageData: Data("not an image".utf8))]
        ]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let exampleURL = try XCTUnwrap(URL(string: "https://example.com"))
        let brokenURL = try XCTUnwrap(URL(string: "https://broken.example"))
        let example = try XCTUnwrap(faviconsByDocument[exampleURL])
        XCTAssertEqual(example.count, 2)
        XCTAssertTrue(example.allSatisfy { $0.image?.representations.allSatisfy { $0 is NSBitmapImageRep } == true })
        XCTAssertEqual(faviconsByDocument[brokenURL]?.count, 1)
        XCTAssertNil(faviconsByDocument[brokenURL]?.first?.image)
    }

    func testImportedFaviconsKeepTheirOrderWhenDecodedConcurrently() async throws {
        let wide = Data(Self.svg(width: 100, height: 50).utf8)
        let tall = Data(Self.svg(width: 50, height: 100).utf8)
        let datas = (0..<12).map { $0.isMultiple(of: 2) ? wide : tall }
        let imported = ["https://example.com": datas.map(ImportedFavicon.init)]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let sizes = try XCTUnwrap(faviconsByDocument[url]).map { $0.image?.size }
        let expected = (0..<12).map { $0.isMultiple(of: 2) ? NSSize(width: 64, height: 32) : NSSize(width: 32, height: 64) }
        XCTAssertEqual(sizes, expected)
    }

    /// Decoding thousands of imported raster favicons must not block the main thread.
    func testImportingManyRasterFaviconsDoesNotBlockTheMainThread() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let imported = ["https://example.com": (0..<3000).map { _ in ImportedFavicon(imageData: png) }]
        let rasterizer = self.rasterizer!

        let importTask = Task.detached { await rasterizer.favicons(fromImported: imported) }
        var isFinished = false
        Task {
            _ = await importTask.value
            isFinished = true
        }
        var longestGap: TimeInterval = 0
        var last = Date()
        let start = last
        while Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(nanoseconds: 2_000_000)
            let now = Date()
            longestGap = max(longestGap, now.timeIntervalSince(last))
            last = now
            if isFinished { break }
        }
        let result = await importTask.value

        XCTAssertEqual(result.values.first?.count, 3000)
        XCTAssertLessThan(longestGap, 0.5)
    }

    // MARK: - Helpers

    private struct ImportedFavicon: ImportedFaviconDataProviding {
        let imageData: Data
    }

    private func decode(_ png: Data) throws -> NSImage {
        try XCTUnwrap(NSImage(dataUsingCIImage: png, maxPixelSize: nil))
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
