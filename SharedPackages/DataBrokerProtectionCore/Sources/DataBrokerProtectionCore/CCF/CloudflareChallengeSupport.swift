//
//  CloudflareChallengeSupport.swift
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
import ObjectiveC.runtime
import os
import Vision
import WebKit

@MainActor
final class CloudflareOffscreenPanel: NSPanel {
    private static var nextSlot = 0

    static func nextOrigin(for size: NSSize) -> NSPoint {
        let slot = nextSlot
        nextSlot += 1
        let leftScreenEdge = NSScreen.screens.map(\.frame.minX).min() ?? 0
        let horizontalGap: CGFloat = 100
        return NSPoint(
            x: leftScreenEdge - size.width - horizontalGap - CGFloat(slot) * (size.width + horizontalGap),
            y: 120)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class CloudflareSnapshotRequest {
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
enum CloudflareChallengeClick {
    static func checkbox(at point: NSPoint, in webView: WKWebView) async -> String {
        let jitteredPoint = NSPoint(
            x: point.x + CGFloat.random(in: -2...2),
            y: point.y + CGFloat.random(in: -1.5...1.5))
        let startPoint = NSPoint(
            x: CGFloat.random(in: 24...max(48, webView.bounds.width * 0.35)),
            y: CGFloat.random(in: 24...max(48, webView.bounds.height * 0.25)))
        let points = pointerPath(from: startPoint, to: jitteredPoint, steps: Int.random(in: 22...36))

        var deliveredMoveCount = 0
        var previousWindowPoint: NSPoint?
        for (index, point) in points.enumerated() {
            let windowPoint = windowPoint(fromCSS: point, in: webView)
            if deliverMove(at: windowPoint, in: webView, previous: previousWindowPoint) {
                deliveredMoveCount += 1
            }
            previousWindowPoint = windowPoint
            let nanoseconds = index < 3 || index > points.count - 4 ? 14_000_000 : UInt64.random(in: 5_000_000...11_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }

        try? await Task.sleep(nanoseconds: UInt64.random(in: 280_000_000...520_000_000))
        let windowPoint = windowPoint(fromCSS: jitteredPoint, in: webView)
        let clickResult = deliverClick(at: windowPoint, in: webView)
        try? await Task.sleep(nanoseconds: 100_000_000)
        return "css=\(Int(jitteredPoint.x)),\(Int(jitteredPoint.y)) moves=\(deliveredMoveCount)/\(points.count) \(clickResult)"
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

    private static func pointerPath(from start: NSPoint, to end: NSPoint, steps: Int) -> [NSPoint] {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let firstControl = NSPoint(
            x: start.x + deltaX * 0.28 + CGFloat.random(in: -70...70),
            y: start.y + deltaY * 0.18 + CGFloat.random(in: -50...50))
        let secondControl = NSPoint(
            x: start.x + deltaX * 0.72 + CGFloat.random(in: -70...70),
            y: start.y + deltaY * 0.82 + CGFloat.random(in: -50...50))
        return (0...steps).map { index in
            let rawProgress = CGFloat(index) / CGFloat(steps)
            let progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
            let inverseProgress = 1 - progress
            return NSPoint(
                x: inverseProgress * inverseProgress * inverseProgress * start.x
                    + 3 * inverseProgress * inverseProgress * progress * firstControl.x
                    + 3 * inverseProgress * progress * progress * secondControl.x
                    + progress * progress * progress * end.x,
                y: inverseProgress * inverseProgress * inverseProgress * start.y
                    + 3 * inverseProgress * inverseProgress * progress * firstControl.y
                    + 3 * inverseProgress * progress * progress * secondControl.y
                    + progress * progress * progress * end.y)
        }
    }

    private static func deliverMove(at point: NSPoint, in webView: WKWebView, previous: NSPoint?) -> Bool {
        guard let event = mouseEvent(.mouseMoved, at: point, in: webView) else { return false }
        if let previous, let cgEvent = event.cgEvent {
            cgEvent.setIntegerValueField(.mouseEventDeltaX, value: Int64(point.x - previous.x))
            cgEvent.setIntegerValueField(.mouseEventDeltaY, value: Int64(-(point.y - previous.y)))
        }
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
        CloudflarePressedMouseButtons.with(1) {
            webView.window?.sendEvent(downEvent)
            hitView.mouseDown(with: downEvent)
            if hitView !== contentView {
                contentView.mouseDown(with: downEvent)
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        CloudflarePressedMouseButtons.with(0) {
            webView.window?.sendEvent(upEvent)
            hitView.mouseUp(with: upEvent)
            if hitView !== contentView {
                contentView.mouseUp(with: upEvent)
            }
        }
        return "hit=\(type(of: hitView)) content=\(type(of: contentView)) window=\(webView.window != nil)"
    }
}

private enum CloudflarePressedMouseButtons {
    private static var lock = os_unfair_lock_s()
    private static var depth = 0
    private static var value: UInt = 0
    private static var originalImplementation: IMP?

    static func with(_ buttons: UInt, body: () -> Void) {
        install()
        os_unfair_lock_lock(&lock)
        depth += 1
        value = buttons
        os_unfair_lock_unlock(&lock)
        defer {
            os_unfair_lock_lock(&lock)
            depth -= 1
            os_unfair_lock_unlock(&lock)
        }
        body()
    }

    private static func install() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard originalImplementation == nil else { return }
        let selector = #selector(getter: NSEvent.pressedMouseButtons)
        guard let method = class_getClassMethod(NSEvent.self, selector) else { return }
        originalImplementation = method_getImplementation(method)
        let block: @convention(block) (AnyObject) -> UInt = { _ in
            os_unfair_lock_lock(&lock)
            let currentDepth = depth
            let currentValue = value
            let originalImplementation = originalImplementation
            os_unfair_lock_unlock(&lock)
            if currentDepth > 0 { return currentValue }
            typealias OriginalFunction = @convention(c) (AnyObject, Selector) -> UInt
            return originalImplementation.map {
                unsafeBitCast($0, to: OriginalFunction.self)(NSEvent.self, selector)
            } ?? 0
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

struct CloudflareChallengeLabel: Equatable, Sendable {
    let boundingBox: CGRect

    func checkboxPoint(in imageSize: NSSize) -> NSPoint {
        let labelFrame = frame(in: imageSize)
        return NSPoint(x: labelFrame.minX - 20, y: labelFrame.midY)
    }

    func isStable(comparedTo other: CloudflareChallengeLabel, in imageSize: NSSize) -> Bool {
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

enum CloudflareWidgetVision {
    nonisolated static func findChallengeLabel(in image: CGImage) async -> CloudflareChallengeLabel? {
        let task = Task.detached(priority: .utility) {
            recognizeChallengeLabel(in: image)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func recognizeChallengeLabel(in image: CGImage) -> CloudflareChallengeLabel? {
        guard !Task.isCancelled else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil else { return nil }
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if text.caseInsensitiveCompare("Verify you are human") == .orderedSame {
                return CloudflareChallengeLabel(boundingBox: observation.boundingBox)
            }
        }
        return nil
    }

}
#endif
