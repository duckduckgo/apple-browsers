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

/// The one entry point for Duck.ai screenshots on every surface. One capture at a time, app-wide;
/// captures stay in memory and never reach disk or the pasteboard.
@MainActor
final class AIChatScreenshotCaptureService {

    static let shared = AIChatScreenshotCaptureService()

    private(set) var isCapturing = false
    private let permission: AIChatScreenRecordingPermission

    init(permission: AIChatScreenRecordingPermission = AIChatScreenRecordingPermission()) {
        self.permission = permission
    }

    /// - Parameters:
    ///   - windows: our own windows kept out of the picker and the frozen frame.
    ///   - focusWindow: made key again once the capture ends.
    func capture(mode: AIChatScreenshotMode,
                 excluding windows: [NSWindow],
                 returningFocusTo focusWindow: NSWindow?) async -> AIChatScreenshotCaptureResult {
        // A second request while one is up (a double pick, or the NTP and the omnibar at once) is dropped.
        guard !isCapturing else { return .cancelled }

        isCapturing = true
        defer {
            isCapturing = false
            restoreFocus(to: focusWindow)
        }

        // Our own picker lists every window, so both modes need Screen Recording.
        guard permission.isGranted() else { return .permissionDenied }

        let windowIDs = windows.map { CGWindowID($0.windowNumber) }
        switch mode {
        case .selectWindowOrDisplay:
            switch await AIChatScreenshotSourcePicker(excludingWindowIDs: windowIDs).capture() {
            case .cancelled:
                return .cancelled
            case .failed(let reason):
                return .failed(reason)
            case .captured(let image, let kind):
                return await process(image, kind: kind)
            }

        case .dragToSelect:
            switch await AIChatScreenshotRegionCapturer().capture(excludingWindowIDs: windowIDs) {
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
