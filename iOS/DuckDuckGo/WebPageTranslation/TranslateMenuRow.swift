//
//  TranslateMenuRow.swift
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
import WebPageTranslation

/// What the browsing menu's translate row says, and whether it can be tapped, for the page's translation state.
enum TranslateMenuRow {

    struct Content: Equatable {
        let name: String
        let isEnabled: Bool
    }

    static func content(for offer: TranslationOffer, state: PageTranslationSession.State, locale: Locale) -> Content {
        switch state {
        case .idle:
            let language = locale.localizedString(forLanguageCode: offer.target) ?? offer.target
            return Content(name: UserText.translationMenuTranslate(language: language), isEnabled: true)
        case .translating:
            return Content(name: UserText.translationMenuTranslating, isEnabled: false)
        case .partiallyTranslated, .fullyTranslated:
            return Content(name: UserText.translationMenuShowOriginal, isEnabled: true)
        }
    }
}
