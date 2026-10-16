//
//  AIChatScreenshotRegionCapturer.swift
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

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Selection geometry, kept apart from AppKit so it can be tested.
enum AIChatRegionSelection {

    /// Anything smaller is a click: the selection clears and the overlay stays up.
    static let minimumSize: CGFloat = 4

    /// The rect between the drag's start and its current point, clamped to `bounds` so it never
    /// leaves the screen it started on. `nil` while smaller than `minimumSize` either way.
    static func rect(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect? {
        let clampedEnd = CGPoint(x: min(max(end.x, bounds.minX), bounds.maxX),
                                 y: min(max(end.y, bounds.minY), bounds.maxY))
        let rect = CGRect(x: min(start.x, clampedEnd.x),
                          y: min(start.y, clampedEnd.y),
                          width: abs(clampedEnd.x - start.x),
                          height: abs(clampedEnd.y - start.y))
        guard rect.width >= minimumSize, rect.height >= minimumSize else { return nil }
        return rect
    }

    /// Maps a rect in view points (origin bottom-left) to image pixels (origin top-left). The frozen
    /// frame fills the view, so the ratio is the display's scale whatever its DPI.
    static func pixelRect(for rect: CGRect, viewSize: CGSize, imageWidth: Int, imageHeight: Int) -> CGRect {
        let scaleX = CGFloat(imageWidth) / viewSize.width
        let scaleY = CGFloat(imageHeight) / viewSize.height
        let pixels = CGRect(x: (rect.minX * scaleX).rounded(),
                            y: ((viewSize.height - rect.maxY) * scaleY).rounded(),
                            width: max(1, (rect.width * scaleX).rounded()),
                            height: max(1, (rect.height * scaleY).rounded()))
        return pixels.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }
}

/// Freezes every display, lets the user drag a rectangle on one of them, and returns the crop.
@MainActor
final class AIChatScreenshotRegionCapturer {

    enum Outcome {
        case selected(CGImage)
        case cancelled
        case failed(AIChatScreenshotFailureReason)
    }

    private var panels: [AIChatRegionSelectionPanel] = []
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var isCancelled = false

    func capture(excludingWindowIDs windowIDs: [CGWindowID]) async -> Outcome {
        let frames: [(screen: NSScreen, image: CGImage)]
        do {
            frames = try await freezeScreens(excludingWindowIDs: windowIDs)
        } catch {
            return .failed(.failed)
        }
        // Cancelled while the displays froze: there is no overlay yet for `cancel()` to close.
        guard !isCancelled else { return .cancelled }
        guard !frames.isEmpty else { return .failed(.unavailable) }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showPanels(for: frames)
        }
    }

    /// Captured before the overlay exists, so the overlay is never in its own picture.
    /// ponytail: one display at a time; move to a task group if multi-display freezes feel slow.
    private func freezeScreens(excludingWindowIDs windowIDs: [CGWindowID]) async throws -> [(screen: NSScreen, image: CGImage)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedWindows = content.windows.filter { windowIDs.contains($0.windowID) }

        var frames: [(screen: NSScreen, image: CGImage)] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }

            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let image = try await AIChatScreenshotStill.capture(filter,
                                                                 width: Int(CGFloat(display.width) * screen.backingScaleFactor),
                                                                 height: Int(CGFloat(display.height) * screen.backingScaleFactor))
            frames.append((screen, image))
        }
        return frames
    }

    private func showPanels(for frames: [(screen: NSScreen, image: CGImage)]) {
        panels = frames.map { screen, image in
            let view = AIChatRegionSelectionView(frozenImage: image)
            view.onCommit = { [weak self, weak view] rect in
                guard let self, let view else { return }
                let pixelRect = AIChatRegionSelection.pixelRect(for: rect,
                                                                viewSize: view.bounds.size,
                                                                imageWidth: image.width,
                                                                imageHeight: image.height)
                guard let cropped = image.cropping(to: pixelRect) else { return self.finish(.failed(.failed)) }
                self.finish(.selected(cropped))
            }
            view.onCancel = { [weak self] in
                self?.finish(.cancelled)
            }
            return AIChatRegionSelectionPanel(screen: screen, view: view)
        }

        panels.forEach { $0.orderFrontRegardless() }
        let mouseLocation = NSEvent.mouseLocation
        let keyPanel = panels.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? panels.first
        keyPanel?.makeKey()
        keyPanel?.makeFirstResponder(keyPanel?.contentView)
        observeCancelTriggers()
    }

    private func observeCancelTriggers() {
        let cancel: (Notification) -> Void = { [weak self] _ in self?.finish(.cancelled) }

        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main, using: cancel)))
        for panel in panels {
            // Moving between screens hands key from one panel to another; only losing all of them cancels.
            observers.append((center, center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, !self.panels.isEmpty, !self.panels.contains(where: \.isKeyWindow) else { return }
                    self.finish(.cancelled)
                }
            }))
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                                                       object: nil, queue: .main, using: cancel)))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                                       object: nil, queue: .main, using: cancel)))

        let distributedCenter = DistributedNotificationCenter.default()
        observers.append((distributedCenter, distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                                           object: nil, queue: .main, using: cancel)))
    }

    func cancel() {
        isCancelled = true
        finish(.cancelled)
    }

    /// The result is taken before the panels close, so their resigning key can't turn it into a cancel.
    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil

        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        continuation.resume(returning: outcome)
    }
}

/// Non-activating, so the overlay takes key without bringing browser windows forward when the
/// capture started from the prompt bar over another app.
final class AIChatRegionSelectionPanel: NSPanel {

    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        // Kept out of screen sharing, like the frozen frame it shows.
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// The frozen frame dimmed everywhere but the selection, with its size in pixels.
final class AIChatRegionSelectionView: NSView {

    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let frozenImage: CGImage
    private let dimLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let sizeLabelLayer = CATextLayer()
    private var dragStart: CGPoint?
    private var selection: CGRect? {
        didSet { updateLayers() }
    }

    init(frozenImage: CGImage) {
        self.frozenImage = frozenImage
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = frozenImage
        layer?.contentsGravity = .resize

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.6).cgColor
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.white.cgColor
        outlineLayer.lineWidth = 1
        sizeLabelLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabelLayer.fontSize = 11
        sizeLabelLayer.foregroundColor = NSColor.white.cgColor
        sizeLabelLayer.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        sizeLabelLayer.cornerRadius = 4
        sizeLabelLayer.alignmentMode = .center
        sizeLabelLayer.isHidden = true
        [dimLayer, outlineLayer, sizeLabelLayer].forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sizeLabelLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        selection = AIChatRegionSelection.rect(from: dragStart, to: convert(event.locationInWindow, from: nil), in: bounds)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        guard let selection else { return }
        onCommit?(selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        guard Int(event.keyCode) == kVK_Escape else { return super.keyDown(with: event) }
        onCancel?()
    }

    private func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        dimLayer.frame = bounds
        outlineLayer.frame = bounds
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)

        guard let selection else {
            dimLayer.path = dimPath
            outlineLayer.path = nil
            sizeLabelLayer.isHidden = true
            return
        }

        dimPath.addRect(selection)
        dimLayer.path = dimPath
        outlineLayer.path = CGPath(rect: selection.insetBy(dx: 0.5, dy: 0.5), transform: nil)

        let pixels = AIChatRegionSelection.pixelRect(for: selection,
                                                     viewSize: bounds.size,
                                                     imageWidth: frozenImage.width,
                                                     imageHeight: frozenImage.height)
        sizeLabelLayer.string = "\(Int(pixels.width)) × \(Int(pixels.height))"
        sizeLabelLayer.isHidden = false
        let textSize = sizeLabelLayer.preferredFrameSize()
        let labelSize = CGSize(width: textSize.width + 12, height: textSize.height + 4)
        // Below the selection, or above it when that would run off the screen; never past the right edge.
        var origin = CGPoint(x: selection.minX, y: selection.minY - 6 - labelSize.height)
        if origin.y < bounds.minY {
            origin.y = selection.maxY + 6
        }
        origin.x = min(origin.x, bounds.maxX - labelSize.width)
        sizeLabelLayer.frame = CGRect(origin: origin, size: labelSize)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
