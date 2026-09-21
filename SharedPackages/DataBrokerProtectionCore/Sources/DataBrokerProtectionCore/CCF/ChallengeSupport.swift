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
import Vision
import WebKit

@MainActor
final class ChallengeOffscreenPanel: NSPanel {
    private var isObservingSystemChanges = false

    func presentOffscreen() {
        moveOffscreen()
        startObservingSystemChanges()
        orderFrontRegardless()
    }

    func dismissOffscreen() {
        stopObservingSystemChanges()
        orderOut(nil)
        contentView = nil
        close()
    }

    func moveOffscreen() {
        let size = frame.size
        let leftScreenEdge = NSScreen.screens.map(\.frame.minX).min() ?? 0
        let horizontalGap: CGFloat = 100
        setFrameOrigin(NSPoint(
            x: leftScreenEdge - size.width - horizontalGap,
            y: 120))
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    private func startObservingSystemChanges() {
        guard !isObservingSystemChanges else { return }
        isObservingSystemChanges = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil)
    }

    private func stopObservingSystemChanges() {
        guard isObservingSystemChanges else { return }
        isObservingSystemChanges = false
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func screenParametersDidChange() {
        moveOffscreen()
    }

    @objc private func workspaceWillSleep() {
        orderOut(nil)
    }

    @objc private func workspaceDidWake() {
        moveOffscreen()
        orderFrontRegardless()
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
enum ChallengeClick {
    static func checkbox(at point: NSPoint, in webView: WKWebView) async -> String {
        let windowPoint = windowPoint(fromCSS: point, in: webView)
        let didDeliverMove = deliverMove(at: windowPoint, in: webView)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let clickResult = deliverClick(at: windowPoint, in: webView)
        try? await Task.sleep(nanoseconds: 100_000_000)
        return "css=\(Int(point.x)),\(Int(point.y)) move=\(didDeliverMove) \(clickResult)"
    }

    private static func contentView(in view: NSView) -> NSView? {
        let className = String(describing: type(of: view))
        if className.contains("WKContentView") || className.contains("WKFlippedView") {
            return view
        }
        for subview in view.subviews {
            if let contentView = contentView(in: subview) {
                return contentView
            }
        }
        return nil
    }

    private static func windowPoint(fromCSS point: NSPoint, in webView: WKWebView) -> NSPoint {
        let viewPoint = webView.isFlipped
            ? point
            : NSPoint(x: point.x, y: webView.bounds.height - point.y)
        return webView.convert(viewPoint, to: nil)
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in webView: WKWebView) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: webView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: Int.random(in: 1..<10_000),
            clickCount: type == .leftMouseDown || type == .leftMouseUp ? 1 : 0,
            pressure: type == .leftMouseDown ? 1 : 0)
    }

    private static func deliverMove(at point: NSPoint, in webView: WKWebView) -> Bool {
        guard let event = mouseEvent(.mouseMoved, at: point, in: webView) else { return false }
        let contentView = contentView(in: webView) ?? webView
        contentView.mouseMoved(with: event)
        webView.window?.sendEvent(event)
        return true
    }

    private static func deliverClick(at point: NSPoint, in webView: WKWebView) -> String {
        guard let downEvent = mouseEvent(.leftMouseDown, at: point, in: webView),
              let upEvent = mouseEvent(.leftMouseUp, at: point, in: webView) else {
            return "event=nil"
        }
        let contentView = contentView(in: webView) ?? webView
        let viewPoint = webView.convert(point, from: nil)
        let hitView = webView.hitTest(viewPoint) ?? contentView
        webView.window?.sendEvent(downEvent)
        hitView.mouseDown(with: downEvent)
        if hitView !== contentView {
            contentView.mouseDown(with: downEvent)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        webView.window?.sendEvent(upEvent)
        hitView.mouseUp(with: upEvent)
        if hitView !== contentView {
            contentView.mouseUp(with: upEvent)
        }
        return "hit=\(type(of: hitView)) content=\(type(of: contentView)) window=\(webView.window != nil)"
    }
}

struct ChallengeLabel: Equatable, Sendable {
    let boundingBox: CGRect

    func checkboxPoint(in imageSize: NSSize) -> NSPoint {
        let labelFrame = frame(in: imageSize)
        return NSPoint(x: labelFrame.minX - 20, y: labelFrame.midY)
    }

    func isStable(comparedTo other: ChallengeLabel, in imageSize: NSSize) -> Bool {
        let frame = frame(in: imageSize)
        let otherFrame = other.frame(in: imageSize)
        return abs(frame.minX - otherFrame.minX) < 8
            && abs(frame.minY - otherFrame.minY) < 8
            && abs(frame.width - otherFrame.width) < 8
            && abs(frame.height - otherFrame.height) < 8
    }

    private func frame(in imageSize: NSSize) -> CGRect {
        CGRect(
            x: boundingBox.minX * imageSize.width,
            y: (1 - boundingBox.maxY) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height)
    }
}

enum ChallengeVision {
    nonisolated static func findChallengeLabel(in image: CGImage) async -> ChallengeLabel? {
        let task = Task.detached(priority: .utility) {
            recognizeChallengeLabel(in: image)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func recognizeChallengeLabel(in image: CGImage) -> ChallengeLabel? {
        guard !Task.isCancelled else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil else { return nil }
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            guard let labelRange = candidate.string.range(
                of: "Verify you are human",
                options: [.caseInsensitive]) else { continue }
            guard let labelObservation = try? candidate.boundingBox(for: labelRange) else { continue }
            return ChallengeLabel(boundingBox: labelObservation.boundingBox)
        }
        return nil
    }

}
#endif
