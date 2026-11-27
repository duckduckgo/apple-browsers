//
//  TranslateOfferPromptView.swift
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

import DesignResourcesKitIcons
import SwiftUI

struct TranslateOfferPromptView: View {

    let pageLanguageName: String
    let userLanguageName: String
    let answer: (_ translate: Bool) -> Void

    // shortcut: not stored or read yet, a later change wires it to excluded languages.
    @State private var dontAskAgain = false
    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.translateOfferTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: themeManager.designColorPalette))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("TranslateOfferPrompt.title")

                Text(UserText.translateOfferDetail(userLanguage: userLanguageName))
                    .font(.system(size: 12))
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: themeManager.designColorPalette))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(UserText.translateOfferDontAskAgain(pageLanguage: pageLanguageName), isOn: $dontAskAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: themeManager.designColorPalette))
                .accessibilityIdentifier("TranslateOfferPrompt.dontAskAgain")

            HStack(spacing: 12) {
                PromptDecisionButton(title: UserText.translateOfferNoThanks, accessibilityID: "TranslateOfferPrompt.noThanks") { answer(false) }
                PromptDecisionButton(title: UserText.translateOfferTranslate, icon: DesignSystemImages.Glyphs.Size16.aiChat, shortcutHint: "⌘↵",
                                     accessibilityID: "TranslateOfferPrompt.translate") { answer(true) }
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }
}
