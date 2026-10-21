//
//  AIChatScreenshotCaptureService.swift
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
import Combine

/// The one entry point for Duck.ai screenshots on every surface. `AppDelegate` owns the instance every surface
/// uses, so there is one capture at a time, app-wide; captures stay in memory and never reach disk or the pasteboard.
@MainActor
final class AIChatScreenshotCaptureService {

    private(set) var isCapturing = false
    private let permission: AIChatScreenRecordingPermission
    private let instrumentation: AIChatScreenshotPermissionInstrumentation
    private var contextObservation: AnyCancellable?
    private var dismissCapture: (() -> Void)?

    init(permission: AIChatScreenRecordingPermission = AIChatScreenRecordingPermission(),
         instrumentation: AIChatScreenshotPermissionInstrumentation = DefaultAIChatScreenshotPermissionInstrumentation()) {
        self.permission = permission
        self.instrumentation = instrumentation
    }

    /// Shown for `.permissionDenied`, the same on every surface. macOS shows its own prompt only the first
    /// time it's asked, so from then on the alert opens System Settings instead.
    func presentPermissionAlert(on window: NSWindow?) {
        guard let window, window.attachedSheet == nil else { return }
        let asksMacOS = !permission.hasAskedMacOS
        AIChatScreenRecordingPermissionDialog(asksMacOS: asksMacOS) { [weak self] in
            // Once the sheet has closed: closing it orders the browser window front, over macOS's prompt,
            // which is a normal window of another app.
            DispatchQueue.main.async {
                self?.acceptPermissionAlert(asksMacOS: asksMacOS)
            }
        }.show(in: window)
    }

    /// The alert's Continue, or Open System Settings once macOS has been asked.
    func acceptPermissionAlert(asksMacOS: Bool) {
        instrumentation.permissionAlertAccepted()
        if asksMacOS {
            permission.askMacOS()
        } else {
            permission.openSystemSettings()
        }
    }

    /// - Parameters:
    ///   - windows: our own windows kept out of the picker and the frozen frame.
    ///   - focusWindow: made key again once the capture ends. Closing it cancels the capture.
    ///   - contextEnded: also cancels the capture, for when the tab that asked goes away.
    func capture(mode: AIChatScreenshotMode,
                 excluding windows: [NSWindow],
                 returningFocusTo focusWindow: NSWindow?,
                 cancellingOn contextEnded: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()) async -> AIChatScreenshotCaptureResult {
        // A second request while one is up (a double pick, or the NTP and the omnibar at once) is dropped.
        guard !isCapturing else { return .cancelled }

        isCapturing = true
        defer {
            isCapturing = false
            contextObservation = nil
            dismissCapture = nil
            restoreFocus(to: focusWindow)
        }

        // Our own picker lists every window, so both modes need Screen Recording.
        guard permission.isGranted() else {
            instrumentation.permissionNeeded()
            return .permissionDenied
        }

        // The picker and the overlay are windows of their own, so nothing else closes them with the context.
        var hasContextEnded = false
        let windowClosed = focusWindow.map {
            NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: $0).map { _ in () }.eraseToAnyPublisher()
        } ?? Empty().eraseToAnyPublisher()
        contextObservation = windowClosed.merge(with: contextEnded).first().sink { [weak self] in
            hasContextEnded = true
            self?.dismissCapture?()
        }

        let result = await captureImage(mode: mode,
                                        excludingWindowIDs: windows.map { CGWindowID($0.windowNumber) },
                                        presentingOn: focusWindow)
        guard !hasContextEnded else { return .cancelled }
        if case .image = result {
            instrumentation.captureSucceeded()
        }
        return result
    }

    private func captureImage(mode: AIChatScreenshotMode,
                              excludingWindowIDs windowIDs: [CGWindowID],
                              presentingOn focusWindow: NSWindow?) async -> AIChatScreenshotCaptureResult {
        switch mode {
        case .selectWindowOrDisplay:
            // A browser window gets the picker as a sheet, like a native dialog; the prompt bar floats over
            // other apps, and so does its picker.
            let sheetParent = focusWindow.flatMap { $0.styleMask.contains(.nonactivatingPanel) ? nil : $0 }
            let picker = AIChatScreenshotSourcePicker(excludingWindowIDs: windowIDs, sheetParent: sheetParent)
            dismissCapture = picker.cancel
            switch await picker.capture() {
            case .cancelled:
                return .cancelled
            case .failed(let reason):
                return .failed(reason)
            case .captured(let image, let kind):
                return await process(image, kind: kind)
            }

        case .dragToSelect:
            let capturer = AIChatScreenshotRegionCapturer()
            dismissCapture = capturer.cancel
            switch await capturer.capture(excludingWindowIDs: windowIDs) {
            case .cancelled:
                return .cancelled
            case .failed(let reason):
                return .failed(reason)
            case .selected(let image):
                return await process(image, kind: .selection)
            }
        }
    }

    private func process(_ image: CGImage, kind: AIChatScreenshotKind) async -> AIChatScreenshotCaptureResult {
        let processed = await Task.detached(priority: .userInitiated) {
            AIChatScreenshotImageProcessor.process(image, kind: kind)
        }.value
        guard let processed else { return .failed(.failed) }
        return .image(processed)
    }

    /// A capture can leave the app inactive. A non-activating panel (the prompt bar) takes
    /// key without activating, so the app stays where the user left it.
    private func restoreFocus(to window: NSWindow?) {
        guard let window, window.isVisible else { return }
        if !window.styleMask.contains(.nonactivatingPanel), !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKey()
    }
}
