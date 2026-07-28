//
//  DuckAIPromptSurface.swift
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

import Foundation

/// The surface a Duck.ai prompt input is presented on. Shared prompt components branch on this
/// so every address-bar/Prompt-Bar difference lives in one table.
enum DuckAIPromptSurface: Equatable, CaseIterable {

    /// The Duck.ai panel that drops out of a browser window's address bar.
    case addressBar

    /// The system-wide floating Prompt Bar, opened by global shortcut or menu bar icon.
    case promptBar
}

extension DuckAIPromptSurface {

    /// "Add Page Content" in the attach menu and `@`-mention tab attach. The Prompt Bar has no
    /// originating tab to scope the picker to, nor an active tab for the payload's discriminator.
    var supportsPageContext: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// The Customize Responses row in the tools menu. Its modal fights the Prompt Bar's
    /// dismiss-on-resign-key policy.
    var supportsCustomizeResponses: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// The autocomplete/history suggestions list below the prompt editor.
    var supportsSuggestions: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// The "Try for free"/"Upgrade" tag and confirmation dialog on tier-gated model and reasoning
    /// rows. Gated rows stay dimmed and non-interactive either way — the Prompt Bar is a system
    /// utility, so it doesn't sell subscriptions.
    var supportsSubscriptionUpsell: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// Whether the host paints its own background and shadow. The address bar's prompt panel draws
    /// an address-bar-shaped fill, border, top clip mask and external shadow view; the Prompt Bar
    /// panel supplies a vibrancy backdrop instead, so the shared views must not paint over it.
    var drawsOwnChrome: Bool {
        switch self {
        case .addressBar: false
        case .promptBar: true
        }
    }

    /// Whether submitting is routed by the host rather than opened directly. The address bar has the
    /// tab the user typed in and reuses it; the Prompt Bar has no window at all, so its host resolves
    /// one first. Also covers the voice button, which needs the same window.
    var routesSubmissionThroughHost: Bool {
        switch self {
        case .addressBar: false
        case .promptBar: true
        }
    }
}
