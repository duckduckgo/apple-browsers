//
//  AIChatScreenshotWindowPicker.swift
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

import AIChat
import AppKit
import os.log
import ScreenCaptureKit

/// Select Window or Display through the system's content-sharing picker.
@available(macOS 14.0, *)
final class AIChatScreenshotWindowPicker: NSObject, SCContentSharingPickerObserver {

    enum Outcome {
        case captured(image: CGImage, kind: AIChatScreenshotKind)
        case cancelled
        case failed(AIChatScreenshotFailureReason)
    }

    private enum Pick {
        case picked(SCContentFilter)
        case cancelled
        case failed
    }

    private var continuation: CheckedContinuation<Pick, Never>?

    /// The pick doesn't authorize `SCScreenshotManager`: without Screen Recording the capture fails
    /// with `SCStreamError.userDeclined`, so callers check the permission first.
    @MainActor
    func capture(excludingWindowIDs windowIDs: [Int]) async -> Outcome {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedWindowIDs = windowIDs
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        defer {
            picker.isActive = false
            picker.remove(self)
        }

        let pick = await withCheckedContinuation { continuation in
            self.continuation = continuation
            picker.present()
        }
        switch pick {
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed(.unavailable)
        case .picked(let filter):
            return await capture(filter)
        }
    }

    @MainActor
    private func capture(_ filter: SCContentFilter) async -> Outcome {
        let kind: AIChatScreenshotKind
        switch filter.style {
        case .window: kind = .window
        case .display: kind = .screen
        default: return .failed(.failed)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return .captured(image: image, kind: kind)
        } catch {
            let error = error as NSError
            Logger.aiChat.error("Duck.ai screenshot capture failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            return .failed(.failed)
        }
    }

    // MARK: - SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        finish(.picked(filter))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(.cancelled)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        let error = error as NSError
        Logger.aiChat.error("Duck.ai screenshot picker failed to start: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        finish(.failed)
    }

    /// The observer is called off the main thread; the continuation resumes once.
    private func finish(_ outcome: Pick) {
        DispatchQueue.main.async { [weak self] in
            self?.continuation?.resume(returning: outcome)
            self?.continuation = nil
        }
    }
}
