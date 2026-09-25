//
//  AttachmentPrivacyPixel.swift
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

struct AttachmentPrivacyPixel: PixelKit.Event {
    enum Action: String {
        case shown
        case dismissed
        case learnMoreTapped = "learn_more_tapped"
    }

    enum Kind: String {
        case image
        case file

        init?(attachment: UnifiedToggleInputAttachment) {
            switch attachment {
            case .image: self = .image
            case .file: self = .file
            case .invalidFile: return nil
            }
        }
    }

    let action: Action
    let kind: Kind
    let surface: UnifiedToggleInputPixelSurface

    var name: String { "aichat_unified_input_attachment_privacy_\(kind.rawValue)_\(action.rawValue)" }
    var parameters: [String: String]? { ["surface": surface.rawValue] }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}
