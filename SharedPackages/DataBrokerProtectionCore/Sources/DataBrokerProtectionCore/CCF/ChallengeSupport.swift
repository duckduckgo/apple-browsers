//
//  ChallengeSupport.swift
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

#if os(macOS)
import AppKit
import Foundation
import os
import Vision
import WebKit

@MainActor
final class ChallengeOffscreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func presentOffscreen() {
        guard moveOffscreen() else { return }
        orderFrontRegardless()
    }

    func dismissOffscreen() {
        orderOut(nil)
        contentView = nil
        close()
    }

    private func moveOffscreen() -> Bool {
        let size = frame.size
        let screens = NSScreen.screens
        let union = screens.dropFirst().reduce(screens.first?.frame ?? .zero) { $0.union($1.frame) }
        let horizontalGap: CGFloat = 100
        setFrameOrigin(NSPoint(
            x: union.minX - size.width - horizontalGap,
            y: 120))
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else {
            Logger.action.error("Challenge: panel frame intersects a screen; leaving it hidden")
            return false
        }
        return true
    }
}

@MainActor
final class ChallengeSnapshotRequest {
    private var continuation: CheckedContinuation<CGImage?, Never>?

    init(continuation: CheckedContinuation<CGImage?, Never>) {
        self.continuation = continuation
    }

    func finish(with image: CGImage?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: image)
    }
}

@MainActor
final class WebViewChallengePage: ChallengePage {
    private enum Constants {
        static let clickSettleDelayNanoseconds: UInt64 = 200_000_000
        static let mouseDownDurationNanoseconds: UInt64 = 80_000_000
        static let mouseUpSettleDelayNanoseconds: UInt64 = 100_000_000
        static let snapshotTimeout: TimeInterval = 2
    }

    private weak var webView: WKWebView?
    private var panel: ChallengeOffscreenPanel?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func locateLabel(matching text: String) async -> ChallengeLabel? {
        guard let webView else { return nil }
        let snapshotRect = webView.bounds
        guard let image = await snapshot(of: webView, rect: snapshotRect) else { return nil }
        return await ChallengeVision.findLabel(matching: text, in: image, viewSize: snapshotRect.size)
    }

    func click(at point: CGPoint, onMouseDown: () -> Void) async throws {
        guard let webView else { return }
        attachPanelIfNeeded(to: webView)
        defer { dismissPanel() }

        try await Task.sleep(nanoseconds: Constants.clickSettleDelayNanoseconds)
        guard let window = webView.window else { return }
        let windowPoint = windowPoint(fromCSS: point, in: webView)
        guard let downEvent = mouseEvent(.leftMouseDown, at: windowPoint, in: window),
              let upEvent = mouseEvent(.leftMouseUp, at: windowPoint, in: window) else {
            return
        }

        window.sendEvent(downEvent)
        onMouseDown()
        try? await Task.sleep(nanoseconds: Constants.mouseDownDurationNanoseconds)
        guard webView.window === window else { return }
        window.sendEvent(upEvent)
        try? await Task.sleep(nanoseconds: Constants.mouseUpSettleDelayNanoseconds)
    }

    private func snapshot(of webView: WKWebView, rect: CGRect) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let request = ChallengeSnapshotRequest(continuation: continuation)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = rect
            webView.takeSnapshot(with: configuration) { image, _ in
                Task { @MainActor in
                    request.finish(with: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.snapshotTimeout) {
                request.finish(with: nil)
            }
        }
    }

    private func windowPoint(fromCSS point: CGPoint, in webView: WKWebView) -> NSPoint {
        let viewPoint = webView.isFlipped
            ? point
            : NSPoint(x: point.x, y: webView.bounds.height - point.y)
        return webView.convert(viewPoint, to: nil)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: Int.random(in: 1..<10_000),
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0)
    }

    /// A `WKWebView` outside a window ignores synthetic mouse events, so the hidden web view joins an off-screen panel for the click only.
    private func attachPanelIfNeeded(to webView: WKWebView) {
        guard webView.window == nil else { return }
        let panel = ChallengeOffscreenPanel(
            contentRect: NSRect(origin: .zero, size: webView.frame.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .white
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.contentView = webView
        self.panel = panel
        panel.presentOffscreen()
    }

    private func dismissPanel() {
        panel?.dismissOffscreen()
        panel = nil
    }
}

enum ChallengeVision {
    nonisolated static func findLabel(matching text: String, in image: CGImage, viewSize: CGSize) async -> ChallengeLabel? {
        await Task.detached(priority: .utility) {
            recognizeLabel(matching: text, in: image, viewSize: viewSize)
        }.value
    }

    /// Prefers the shortest line containing the text, so the widget label wins over a page heading that starts with the same words.
    private nonisolated static func recognizeLabel(matching text: String, in image: CGImage, viewSize: CGSize) -> ChallengeLabel? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil else { return nil }

        let matches = (request.results ?? []).compactMap { observation -> (length: Int, boundingBox: CGRect)? in
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: text, options: [.caseInsensitive]),
                  let box = try? candidate.boundingBox(for: range) else { return nil }
            return (candidate.string.count, box.boundingBox)
        }
        guard let boundingBox = matches.min(by: { $0.length < $1.length })?.boundingBox else { return nil }

        return ChallengeLabel(frame: CGRect(
            x: boundingBox.minX * viewSize.width,
            y: (1 - boundingBox.maxY) * viewSize.height,
            width: boundingBox.width * viewSize.width,
            height: boundingBox.height * viewSize.height))
    }
}
#endif
