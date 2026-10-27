//
//  FireWindowAnimationTests.swift
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

import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FireWindowAnimationTests: XCTestCase {
    @MainActor
    func testNativeCaptureOfOwnVisibleWindowProducesSnapshot() throws {
        let source = makeSource()
        defer { source.close() }
        // WindowServer registers a newly ordered window asynchronously.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        XCTAssertTrue(source.isVisible)
        XCTAssertGreaterThan(source.windowNumber, 0)
        let presentation = try XCTUnwrap(FireWindowAnimationController(sourceWindow: source),
                                         "Native capture of the application's own visible window must succeed")
        defer { presentation.start(playback: .init(isEnabled: false)) {} }
        XCTAssertNotNil(presentation.window?.contentView?.layer?.sublayers?.first?.contents)
    }

    @MainActor
    func testSnapshotMatchesSourceFrameIncludingShadowWithoutMovingSource() throws {
        let source = makeSource()
        defer { source.close() }
        let frame = source.frame
        let presentation = try makePresentation(source: source)
        defer { presentation.start(playback: .init(isEnabled: false)) {} }
        XCTAssertEqual(source.frame, frame)
        XCTAssertEqual(presentation.window?.frame, frame.insetBy(dx: -80, dy: -80))
        XCTAssertFalse(source.isVisible)
        XCTAssertTrue(presentation.window?.isVisible == true)
        XCTAssertFalse(presentation.window?.hasShadow ?? true, "The native shadow is already in the captured image")
        XCTAssertTrue(presentation.window?.ignoresMouseEvents == true)
        XCTAssertNotNil(presentation.window?.contentView?.layer?.sublayers?.first?.contents)
    }

    @MainActor
    func testInvisibleSourceDoesNotCreateSnapshot() {
        let source = makeSource()
        defer { source.close() }
        source.orderOut(nil)
        XCTAssertNil(FireWindowAnimationController(sourceWindow: source))
    }

    @MainActor
    func testCaptureFailureLeavesSourceVisibleForLegacyFallback() {
        let source = makeSource()
        defer { source.close() }
        let frame = source.frame
        XCTAssertNil(FireWindowAnimationController(sourceWindow: source, capture: { _, _ in nil }))
        XCTAssertTrue(source.isVisible, "Failed capture must not remove the only visible presentation")
        XCTAssertEqual(source.frame, frame)
    }

    @MainActor
    func testSnapshotStaysAlignedAfterSourceMovesBetweenAvailableDisplays() throws {
        let source = makeSource()
        defer { source.close() }
        for screen in NSScreen.screens {
            source.setFrame(.init(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.maxY - 420,
                                  width: 700, height: 400), display: true)
            source.orderFront(nil)
            let frame = source.frame
            let presentation = try makePresentation(source: source)
            XCTAssertEqual(presentation.window?.frame, frame.insetBy(dx: -80, dy: -80), screen.localizedName)
            presentation.start(playback: .init(isEnabled: false)) {}
        }
    }

    @MainActor
    func testMissingAssetClosesSnapshotAndCompletesExactlyOnce() async throws {
        let source = makeSource()
        defer { source.close() }
        let presentation = try makePresentation(source: source)
        var completions = 0
        let finished = expectation(description: "Missing asset releases the burn")
        presentation.start(playback: .init(isEnabled: true, reduceMotion: false, load: { nil })) {
            completions += 1
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        presentation.window?.close()
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(presentation.window?.isVisible ?? false)
    }

    @MainActor
    func testMissingContentViewStillCompletesAndClosesSnapshot() async throws {
        let loaded = await DefaultFireAnimationLoader().load()
        let fire = try XCTUnwrap(loaded)
        let source = makeSource()
        defer { source.close() }
        let presentation = try makePresentation(source: source)
        // Release the retained presentation even when the regression leaves its completion pending.
        defer { presentation.start(playback: .init(isEnabled: false)) {} }
        presentation.window?.contentView = nil
        let finished = expectation(description: "Losing the content view must release the burn")
        presentation.start(playback: .init(isEnabled: true, reduceMotion: false, load: { fire })) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertFalse(presentation.window?.isVisible ?? false)
    }

    @MainActor
    func testCancelledAssetLoadingStillCompletesAndClosesSnapshot() async throws {
        let source = makeSource()
        defer { source.close() }
        let presentation = try makePresentation(source: source)
        defer { presentation.start(playback: .init(isEnabled: false)) {} }
        let finished = expectation(description: "Cancelling the load must release the burn")
        presentation.start(playback: .init(isEnabled: true, reduceMotion: false, load: {
            withUnsafeCurrentTask { $0?.cancel() }
            return nil
        })) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertFalse(presentation.window?.isVisible ?? false)
    }

    @MainActor
    func testReduceMotionClosesSnapshotWithoutLoadingLottie() async throws {
        let source = makeSource()
        defer { source.close() }
        let presentation = try makePresentation(source: source)
        let finished = expectation(description: "Reduce Motion fade finishes")
        presentation.start(playback: .init(isEnabled: true, reduceMotion: true, load: {
            XCTFail("Reduce Motion must not load the full animation")
            return nil
        })) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(presentation.window?.isVisible ?? false)
    }

    @MainActor
    func testRealBundledLottiePlaysWithSnapshotWipeAndFinishes() async throws {
        let source = makeSource()
        defer { source.close() }
        let presentation = try makePresentation(source: source)
        defer { presentation.start(playback: .init(isEnabled: false)) {} }
        let finished = expectation(description: "Real bundled animation finishes")
        finished.assertForOverFulfill = true
        let appeared = expectation(for: NSPredicate { _, _ in
            presentation.window?.contentView?.subviews.contains {
                $0.identifier?.rawValue == "02_Fire_rebranded"
            } == true
        }, evaluatedWith: nil)
        presentation.start(playback: .init(isEnabled: true, reduceMotion: false)) { finished.fulfill() }
        await fulfillment(of: [appeared], timeout: 5)
        XCTAssertNotNil(presentation.window?.contentView?.layer?.sublayers?.first?.mask)
        XCTAssertFalse(source.isVisible)
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertFalse(presentation.window?.isVisible ?? false)
    }

    @MainActor
    private func makePresentation(source: NSWindow) throws -> FireWindowAnimationController {
        // Isolate playback and completion from WindowServer capture availability in the test host.
        let context = try XCTUnwrap(CGContext(data: nil, width: 860, height: 582, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 860, height: 582))
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(FireWindowAnimationController(sourceWindow: source, capture: { _, _ in image }))
    }

    @MainActor
    private func makeSource() -> NSWindow {
        let source = NSWindow(contentRect: NSRect(x: 220, y: 240, width: 700, height: 400),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        source.isReleasedWhenClosed = false
        source.contentView = NSView(frame: .init(x: 0, y: 0, width: 700, height: 400))
        source.orderFront(nil)
        source.displayIfNeeded()
        return source
    }
}
