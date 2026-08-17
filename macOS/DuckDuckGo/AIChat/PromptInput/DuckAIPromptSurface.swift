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
    case addressBar
    case promptBar
}

extension DuckAIPromptSurface {

    /// "Add Page Content" and `@`-mention tab attach, both of which need an originating tab.
    var supportsPageContext: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// Its modal fights the Prompt Bar's dismiss-on-resign-key policy.
    var supportsCustomizeResponses: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    var supportsSuggestions: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// Only the tag and dialog: gated rows stay dimmed and non-interactive either way.
    var supportsSubscriptionUpsell: Bool {
        switch self {
        case .addressBar: true
        case .promptBar: false
        }
    }

    /// When set, the shared views skip their address-bar fill, border, clip mask and shadow so the
    /// host's own backdrop shows through.
    var drawsOwnChrome: Bool {
        switch self {
        case .addressBar: false
        case .promptBar: true
        }
    }

    var showsDuckAILogo: Bool {
        switch self {
        case .addressBar: false
        case .promptBar: true
        }
    }

    /// Set for surfaces with no window of their own, whose host has to resolve one first. Covers the
    /// voice button too.
    var routesSubmissionThroughHost: Bool {
        switch self {
        case .addressBar: false
        case .promptBar: true
        }
    }
}
