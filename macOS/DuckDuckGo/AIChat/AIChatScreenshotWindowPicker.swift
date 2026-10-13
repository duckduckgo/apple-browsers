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

import AppKit
import ScreenCaptureKit

/// Select Window or Display through the system's content-sharing picker.
@available(macOS 14.0, *)
final class AIChatScreenshotWindowPicker: NSObject, SCContentSharingPickerObserver {

    enum Outcome {
        case picked(SCContentFilter)
        case cancelled
        case failed
    }

    private var continuation: CheckedContinuation<Outcome, Never>?

    @MainActor
    func pick(excludingWindowIDs windowIDs: [Int]) async -> Outcome {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedWindowIDs = windowIDs
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true

        let outcome = await withCheckedContinuation { continuation in
            self.continuation = continuation
            picker.present()
        }

        picker.isActive = false
        picker.remove(self)
        return outcome
    }

    @MainActor
    func capture(_ filter: SCContentFilter) async -> (image: CGImage, kind: AIChatScreenshotKind)? {
        let kind: AIChatScreenshotKind
        switch filter.style {
        case .window: kind = .window
        case .display: kind = .screen
        default: return nil
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return nil }
        return (image, kind)
    }

    // MARK: - SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        finish(.picked(filter))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(.cancelled)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(.failed)
    }

    /// The observer is called off the main thread; the continuation resumes once.
    private func finish(_ outcome: Outcome) {
        DispatchQueue.main.async { [weak self] in
            self?.continuation?.resume(returning: outcome)
            self?.continuation = nil
        }
    }
}
