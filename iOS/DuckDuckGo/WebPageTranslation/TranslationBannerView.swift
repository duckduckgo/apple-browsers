//
//  TranslationBannerView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI
import WebPageTranslation

/// The "Translate this page?" card offered when a page is in a language the user probably can't read.
struct TranslationBannerView: View {

    private let subtitle: String
    private let onTranslate: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(offer: TranslationOffer, locale: Locale = .current, onTranslate: @escaping () -> Void) {
        self.subtitle = Self.subtitle(for: offer, locale: locale)
        self.onTranslate = onTranslate
    }

    /// "Spanish to English", with names in the user's language; an unknown code shows as is.
    static func subtitle(for offer: TranslationOffer, locale: Locale) -> String {
        func name(_ code: String) -> String {
            locale.localizedString(forLanguageCode: code) ?? code
        }
        return UserText.translationBannerSubtitle(source: name(offer.source), target: name(offer.target))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(uiImage: DesignSystemImages.Color.Size56.translate)
                .resizable()
                .frame(width: 32, height: 32)
                .padding(.vertical, 4)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(UserText.translationBannerTitle)
                    .daxSubheadSemibold()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                Text(subtitle)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(UserText.translationBannerTranslateButton, action: onTranslate)
                .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: false))
                .fixedSize()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background { background }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        // Solid like the Figma card, so the page behind never shows through the text.
        let card = shape.fill(Color(designSystemColor: .surfaceTertiary))
        if #available(iOS 26.0, *), !reduceTransparency {
            card.glassEffect(.regular, in: shape)
        } else {
            card
                .overlay { shape.strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: 0.5) }
                .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 8, y: 4)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        TranslationBannerView(offer: TranslationOffer(source: "es", target: "en"), onTranslate: {})
        TranslationBannerView(offer: TranslationOffer(source: "pt", target: "en"), onTranslate: {})
            .dynamicTypeSize(.xxxLarge)
    }
    .padding(.horizontal, 24)
}
