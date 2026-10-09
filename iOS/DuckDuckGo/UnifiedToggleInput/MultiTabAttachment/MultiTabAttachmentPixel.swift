//
//  MultiTabAttachmentPixel.swift
//  DuckDuckGo
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

import PixelKit

struct MultiTabAttachmentPixel: PixelKit.Event {
    enum Action: String {
        case pickerShown = "tab_picker_shown"
        case pickerCanceled = "tab_picker_canceled"
        case attached = "tab_attached"
        case removed = "tab_removed"
    }

    let action: Action
    let source: TabAttachmentOrigin
    let surface: UnifiedToggleInputPixelSurface

    var name: String { "aichat_unified_input_\(action.rawValue)" }
    var parameters: [String: String]? { ["surface": surface.rawValue, "source": source.pixelValue] }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

private extension TabAttachmentOrigin {
    var pixelValue: String {
        switch self {
        case .recentTabs: return "recent_tabs"
        case .tabPicker: return "tab_picker"
        case .mention: return "mention"
        }
    }
}

struct MultiTabSentPixel: PixelKit.Event {
    let count: Int
    let surface: UnifiedToggleInputPixelSurface

    var name: String { "aichat_unified_input_tabs_sent" }
    var parameters: [String: String]? {
        ["surface": surface.rawValue, "payload_tab_count": count == 1 ? "one" : count < 4 ? "some" : "many"]
    }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

struct MultiTabSubmissionIncompletePixel: PixelKit.Event {
    enum Outcome: String {
        case partial
        case all
    }

    let outcome: Outcome
    let surface: UnifiedToggleInputPixelSurface

    var name: String { "aichat_unified_input_tabs_submission_incomplete" }
    var parameters: [String: String]? { ["surface": surface.rawValue, "outcome": outcome.rawValue] }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// One visible picker session, independent of filtering updates and duplicate dismissal callbacks.
/// Both events use the surface captured when the picker becomes visible.
@MainActor
final class MultiTabPickerPixelSession {
    private let surfaceProvider: () -> UnifiedToggleInputPixelSurface?
    private let report: (MultiTabAttachmentPixel.Action, UnifiedToggleInputPixelSurface) -> Void
    private var isShown = false
    private var surface: UnifiedToggleInputPixelSurface?

    init(surfaceProvider: @escaping () -> UnifiedToggleInputPixelSurface?,
         report: @escaping (MultiTabAttachmentPixel.Action, UnifiedToggleInputPixelSurface) -> Void) {
        self.surfaceProvider = surfaceProvider
        self.report = report
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        surface = surfaceProvider()
        if let surface {
            report(.pickerShown, surface)
        }
    }

    func finish(didChoose: Bool = false) {
        guard isShown else { return }
        isShown = false
        let shownSurface = surface
        surface = nil
        if !didChoose, let shownSurface {
            report(.pickerCanceled, shownSurface)
        }
    }
}
