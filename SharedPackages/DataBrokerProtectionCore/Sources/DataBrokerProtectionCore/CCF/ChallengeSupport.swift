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
    private var isObservingSystemChanges = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func presentOffscreen() {
        startObservingSystemChanges()
        guard moveOffscreen() else { return }
        orderFrontRegardless()
    }

    func dismissOffscreen() {
        stopObservingSystemChanges()
        orderOut(nil)
        contentView = nil
        close()
    }

    @discardableResult
    func moveOffscreen() -> Bool {
        orderOut(nil)
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

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let intersectsAScreen = NSScreen.screens.contains { $0.frame.intersects(frameRect) }
        return intersectsAScreen ? super.constrainFrameRect(frameRect, to: screen) : frameRect
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
        guard moveOffscreen() else { return }
        orderFrontRegardless()
    }

    @objc private func workspaceWillSleep() {
        orderOut(nil)
    }

    @objc private func workspaceDidWake() {
        guard moveOffscreen() else { return }
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
        try? await Task.sleep(nanoseconds: 100_000_000)
        let clickResult = deliverClick(at: windowPoint, in: webView)
        try? await Task.sleep(nanoseconds: 100_000_000)
        return "css=\(Int(point.x)),\(Int(point.y)) \(clickResult)"
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

    private static func deliverClick(at point: NSPoint, in webView: WKWebView) -> String {
        guard let downEvent = mouseEvent(.leftMouseDown, at: point, in: webView),
              let upEvent = mouseEvent(.leftMouseUp, at: point, in: webView) else {
            return "event=nil"
        }
        webView.window?.sendEvent(downEvent)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        webView.window?.sendEvent(upEvent)
        return "window=\(webView.window != nil)"
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
