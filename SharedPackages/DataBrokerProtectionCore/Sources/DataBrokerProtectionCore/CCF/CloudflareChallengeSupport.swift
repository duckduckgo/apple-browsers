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
import ApplicationServices
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
    private var continuation: CheckedContinuation<NSImage?, Never>?

    init(continuation: CheckedContinuation<NSImage?, Never>) {
        self.continuation = continuation
    }

    func finish(with image: NSImage?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: image)
    }
}

struct CloudflareAccessibilityCandidate: Sendable {
    let label: String
    let role: String
    let screenPosition: CGPoint?
    let size: CGSize?
    let performedPress: Bool

    var hasGeometry: Bool {
        screenPosition != nil && size != nil
    }

    func isSameControl(as other: CloudflareAccessibilityCandidate) -> Bool {
        guard role == other.role, label == other.label else { return false }
        guard let screenPosition, let size, let otherPosition = other.screenPosition, let otherSize = other.size else {
            return hasGeometry == other.hasGeometry
        }
        return abs(screenPosition.x - otherPosition.x) < 8
            && abs(screenPosition.y - otherPosition.y) < 8
            && abs(size.width - otherSize.width) < 8
            && abs(size.height - otherSize.height) < 8
    }
}

struct CloudflareAccessibilityProbeResult: Sendable {
    let candidate: CloudflareAccessibilityCandidate?
    let visitedCount: Int
    let interactiveCount: Int
    let trusted: Bool
    let diagnostics: [String]
}

struct CloudflareAccessibilityScope: Sendable {
    let webViewScreenFrame: CGRect
    let primaryScreenTop: CGFloat
}

enum CloudflareAccessibilityProbe {
    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated static func inspect(processIdentifier: pid_t,
                                    scope: CloudflareAccessibilityScope,
                                    performPressWhenGeometryIsMissing: Bool) -> CloudflareAccessibilityProbeResult {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            return CloudflareAccessibilityProbeResult(
                candidate: nil,
                visitedCount: 0,
                interactiveCount: 0,
                trusted: false,
                diagnostics: [])
        }

        var queue = [AXUIElementCreateApplication(processIdentifier)]
        var seen = Set<CFHashCode>()
        var visitedCount = 0
        var interactiveCount = 0
        var diagnostics: [String] = []
        var missingGeometryCandidate: (element: AXUIElement, label: String, role: String)?
        var scopedCandidate: CloudflareAccessibilityCandidate?

        while !queue.isEmpty, visitedCount < 2_000 {
            let element = queue.removeFirst()
            guard seen.insert(CFHash(element)).inserted else { continue }
            visitedCount += 1

            let childrenResult = attribute(element, kAXChildrenAttribute as String)
            if let children = childrenResult.value as? [AXUIElement] {
                queue.append(contentsOf: children)
            } else if let error = childrenResult.error {
                diagnostics.append("attribute=AXChildren error=\(describe(error))")
            }

            let roleResult = attribute(element, kAXRoleAttribute as String)
            guard let role = roleResult.value as? String else {
                if let error = roleResult.error {
                    diagnostics.append("attribute=AXRole error=\(describe(error))")
                }
                continue
            }

            let isCheckbox = role == (kAXCheckBoxRole as String)
            let isButton = role == (kAXButtonRole as String)
            guard isCheckbox || isButton else { continue }
            interactiveCount += 1

            let text = accessibilityText(for: element, diagnostics: &diagnostics)
            let normalizedText = text.lowercased()
            let identifiesChallenge = normalizedText.contains("verify")
                && (normalizedText.contains("human") || normalizedText.contains("cloudflare") || normalizedText.contains("challenge"))
            guard identifiesChallenge else { continue }

            let enabledResult = attribute(element, kAXEnabledAttribute as String)
            if let error = enabledResult.error {
                diagnostics.append("attribute=AXEnabled error=\(describe(error))")
            }
            guard (enabledResult.value as? Bool) ?? true else { continue }

            let position = pointAttribute(element, kAXPositionAttribute as String, diagnostics: &diagnostics)
            let size = sizeAttribute(element, kAXSizeAttribute as String, diagnostics: &diagnostics)
            let namesResult = attributeNames(element)
            if let error = namesResult.error {
                diagnostics.append("attributeNames error=\(describe(error))")
            } else {
                diagnostics.append("attributeNames=[\(namesResult.names.joined(separator: ","))]")
            }

            guard let position, let size else {
                if missingGeometryCandidate == nil,
                   belongsToScope(element, scope: scope, diagnostics: &diagnostics) {
                    missingGeometryCandidate = (element, text, role)
                }
                continue
            }

            let candidateFrame = CGRect(
                x: position.x,
                y: scope.primaryScreenTop - position.y - size.height,
                width: size.width,
                height: size.height)
            guard !candidateFrame.isEmpty, candidateFrame.intersects(scope.webViewScreenFrame) else {
                diagnostics.append("candidate rejected=outside-webview")
                continue
            }

            if scopedCandidate == nil {
                scopedCandidate = CloudflareAccessibilityCandidate(
                    label: text,
                    role: role,
                    screenPosition: position,
                    size: size,
                    performedPress: false)
            }
        }

        if scopedCandidate == nil,
           performPressWhenGeometryIsMissing,
           let missingGeometryCandidate {
            let pressError = AXUIElementPerformAction(missingGeometryCandidate.element, kAXPressAction as CFString)
            let performedPress = pressError == .success
            if pressError != .success {
                diagnostics.append("action=AXPress error=\(describe(pressError))")
            }
            scopedCandidate = CloudflareAccessibilityCandidate(
                label: missingGeometryCandidate.label,
                role: missingGeometryCandidate.role,
                screenPosition: nil,
                size: nil,
                performedPress: performedPress)
        }

        return CloudflareAccessibilityProbeResult(
            candidate: scopedCandidate,
            visitedCount: visitedCount,
            interactiveCount: interactiveCount,
            trusted: true,
            diagnostics: diagnostics)
    }

    private nonisolated static func belongsToScope(_ element: AXUIElement,
                                                    scope: CloudflareAccessibilityScope,
                                                    diagnostics: inout [String]) -> Bool {
        let windowResult = attribute(element, kAXWindowAttribute as String)
        guard let windowValue = windowResult.value,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            if let error = windowResult.error {
                diagnostics.append("attribute=AXWindow error=\(describe(error))")
            }
            return false
        }
        let window = windowValue as! AXUIElement
        guard let position = pointAttribute(window, kAXPositionAttribute as String, diagnostics: &diagnostics),
              let size = sizeAttribute(window, kAXSizeAttribute as String, diagnostics: &diagnostics) else { return false }
        let windowFrame = CGRect(
            x: position.x,
            y: scope.primaryScreenTop - position.y - size.height,
            width: size.width,
            height: size.height)
        return !windowFrame.isEmpty && windowFrame.intersects(scope.webViewScreenFrame)
    }

    private nonisolated static func accessibilityText(for element: AXUIElement, diagnostics: inout [String]) -> String {
        let attributeNames = [
            kAXDescriptionAttribute as String,
            kAXTitleAttribute as String,
            kAXRoleDescriptionAttribute as String,
            kAXValueAttribute as String
        ]
        return attributeNames.compactMap { name in
            let result = attribute(element, name)
            if let error = result.error {
                diagnostics.append("attribute=\(name) error=\(describe(error))")
            }
            return result.value as? String
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> (value: CFTypeRef?, error: AXError?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return error == .success ? (value, nil) : (nil, error)
    }

    private nonisolated static func pointAttribute(_ element: AXUIElement,
                                                    _ name: String,
                                                    diagnostics: inout [String]) -> CGPoint? {
        let result = attribute(element, name)
        guard let value = result.value else {
            if let error = result.error {
                diagnostics.append("attribute=\(name) error=\(describe(error))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            diagnostics.append("attribute=\(name) error=unexpected-type")
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            diagnostics.append("attribute=\(name) error=value-conversion")
            return nil
        }
        return point
    }

    private nonisolated static func sizeAttribute(_ element: AXUIElement,
                                                   _ name: String,
                                                   diagnostics: inout [String]) -> CGSize? {
        let result = attribute(element, name)
        guard let value = result.value else {
            if let error = result.error {
                diagnostics.append("attribute=\(name) error=\(describe(error))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            diagnostics.append("attribute=\(name) error=unexpected-type")
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            diagnostics.append("attribute=\(name) error=value-conversion")
            return nil
        }
        return size
    }

    private nonisolated static func attributeNames(_ element: AXUIElement) -> (names: [String], error: AXError?) {
        var names: CFArray?
        let error = AXUIElementCopyAttributeNames(element, &names)
        guard error == .success else { return ([], error) }
        return ((names as? [String]) ?? [], nil)
    }

    private nonisolated static func describe(_ error: AXError) -> String {
        let name: String
        switch error {
        case .success: name = "success"
        case .failure: name = "failure"
        case .illegalArgument: name = "illegalArgument"
        case .invalidUIElement: name = "invalidUIElement"
        case .invalidUIElementObserver: name = "invalidUIElementObserver"
        case .cannotComplete: name = "cannotComplete"
        case .attributeUnsupported: name = "attributeUnsupported"
        case .actionUnsupported: name = "actionUnsupported"
        case .notificationUnsupported: name = "notificationUnsupported"
        case .notImplemented: name = "notImplemented"
        case .notificationAlreadyRegistered: name = "notificationAlreadyRegistered"
        case .notificationNotRegistered: name = "notificationNotRegistered"
        case .apiDisabled: name = "apiDisabled"
        case .noValue: name = "noValue"
        case .parameterizedAttributeUnsupported: name = "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: name = "notEnoughPrecision"
        @unknown default: name = "unknown"
        }
        return "\(name)(\(error.rawValue))"
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

struct CloudflareWidgetBox: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var checkboxPoint: NSPoint {
        NSPoint(x: x + 28, y: y + height / 2)
    }

    func isStable(comparedTo other: CloudflareWidgetBox) -> Bool {
        abs(x - other.x) < 8
            && abs(y - other.y) < 8
            && abs(width - other.width) < 8
            && abs(height - other.height) < 8
    }
}

enum CloudflareWidgetVision {
    nonisolated static func find(in image: NSImage, cssSize: NSSize) -> CloudflareWidgetBox? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let bytes = bitmap.bitmapData else { return nil }
        let pixelWidth = bitmap.pixelsWide
        let pixelHeight = bitmap.pixelsHigh
        guard pixelWidth > 10, pixelHeight > 10, cssSize.width > 0 else { return nil }
        let samplesPerPixel = max(1, bitmap.samplesPerPixel)
        let bytesPerRow = bitmap.bytesPerRow
        let scale = CGFloat(pixelWidth) / cssSize.width
        let minimumWidth = Int(260 * scale)
        let maximumWidth = Int(340 * scale)
        let minimumHeight = Int(52 * scale)
        let maximumHeight = Int(90 * scale)
        let step = max(1, Int(round(scale)))

        var bands: [(y: Int, startX: Int, endX: Int)] = []
        for y in stride(from: 0, to: pixelHeight, by: step) {
            var runStart: Int?
            var bestRun: (start: Int, end: Int)?
            var x = 0
            while x < pixelWidth {
                if isPaleGray(bytes: bytes, offset: y * bytesPerRow + x * samplesPerPixel, samplesPerPixel: samplesPerPixel) {
                    if runStart == nil { runStart = x }
                } else if let start = runStart {
                    let width = x - start
                    let currentBestWidth = bestRun.map { $0.end - $0.start } ?? 0
                    if width >= minimumWidth, width <= maximumWidth, width > currentBestWidth {
                        bestRun = (start, x)
                    }
                    runStart = nil
                }
                x += step
            }
            if let runStart {
                let width = pixelWidth - runStart
                let currentBestWidth = bestRun.map { $0.end - $0.start } ?? 0
                if width >= minimumWidth, width <= maximumWidth, width > currentBestWidth {
                    bestRun = (runStart, pixelWidth)
                }
            }
            if let bestRun {
                bands.append((y, bestRun.start, bestRun.end))
            }
        }

        var bestPair: (top: Int, bottom: Int, startX: Int, endX: Int)?
        for firstIndex in bands.indices {
            let first = bands[firstIndex]
            for secondIndex in bands.index(after: firstIndex)..<bands.endIndex {
                let second = bands[secondIndex]
                let height = second.y - first.y
                guard height >= minimumHeight, height <= maximumHeight else { continue }
                let overlap = min(first.endX, second.endX) - max(first.startX, second.startX)
                guard overlap >= minimumWidth - Int(20 * scale) else { continue }
                let candidate = (first.y, second.y, max(first.startX, second.startX), min(first.endX, second.endX))
                if let currentBestPair = bestPair {
                    let candidateDifference = abs(height - Int(65 * scale))
                    let bestDifference = abs((currentBestPair.bottom - currentBestPair.top) - Int(65 * scale))
                    if candidateDifference < bestDifference {
                        bestPair = candidate
                    }
                } else {
                    bestPair = candidate
                }
            }
        }
        guard let bestPair else { return nil }
        return CloudflareWidgetBox(
            x: CGFloat(bestPair.startX) / scale,
            y: CGFloat(bestPair.top) / scale,
            width: CGFloat(bestPair.endX - bestPair.startX) / scale,
            height: CGFloat(bestPair.bottom - bestPair.top) / scale)
    }

    nonisolated static func containsChallengeText(in image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage)
        guard (try? handler.perform([request])) != nil else { return false }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
        return text.contains("verify you are human")
            || text.contains("cloudflare")
            || text.contains("security verification")
    }

    private nonisolated static func isPaleGray(bytes: UnsafeMutablePointer<UInt8>, offset: Int, samplesPerPixel: Int) -> Bool {
        let red = Double(bytes[offset]) / 255
        let green = Double(bytes[offset + min(1, samplesPerPixel - 1)]) / 255
        let blue = Double(bytes[offset + min(2, samplesPerPixel - 1)]) / 255
        return abs(red - green) < 0.08 && abs(green - blue) < 0.08 && red > 0.62 && red < 0.92
    }

}
#endif
