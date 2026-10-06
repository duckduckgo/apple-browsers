//
//  OnboardingRichTextMessageRenderer.swift
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

import Foundation
import DesignResourcesKitIcons
import Core

enum OnboardingRichTextMessageRenderer {

    private static let fireButtonCopy = "Fire Button"

    static func render(_ message: String) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: applyChatIconReplacement(to: message))
        applyFireButtonBold(to: mutable)
        return mutable
    }

    private static func applyChatIconReplacement(to message: String) -> NSAttributedString {
        message.attributedString(
            withPlaceholder: UserText.Onboarding.ContextualOnboarding.onboardingChatIconToken,
            replacedByImage: DesignSystemImages.Glyphs.Size16.aiChatOnboarding,
            verticalOffset: -2
        ) ?? NSAttributedString(string: message)
    }

    private static func applyFireButtonBold(to attributed: NSMutableAttributedString) {
        let nsRange = (attributed.string as NSString).range(of: fireButtonCopy)
        guard nsRange.location != NSNotFound else { return }

        var fragment = AttributedString(attributed.attributedSubstring(from: nsRange))
        fragment.inlinePresentationIntent = .stronglyEmphasized
        attributed.replaceCharacters(in: nsRange, with: NSAttributedString(fragment))
    }

}
