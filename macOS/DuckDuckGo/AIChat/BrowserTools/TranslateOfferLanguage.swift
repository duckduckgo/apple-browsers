//
//  TranslateOfferLanguage.swift
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

/// Which `<html lang>` values earn a translation offer (R2).
enum TranslateOfferLanguage {

    /// The page's primary language code when it isn't the user's and `locale` can name it, or nil.
    static func foreignLanguageCode(pageLanguage: String?, preferredLanguage: String?, locale: Locale = .current) -> String? {
        guard let code = primarySubtag(of: pageLanguage),
              let preferred = primarySubtag(of: preferredLanguage),
              code != preferred,
              name(of: code, in: locale) != nil else { return nil }
        return code
    }

    /// The name of a language tag's primary language, such as Spanish for `es-MX`.
    static func name(of languageTag: String?, in locale: Locale = .current) -> String? {
        // Locale names these codes, but none is a language to translate from.
        guard let languageCode = primarySubtag(of: languageTag),
              !["und", "mul", "mis", "zxx"].contains(languageCode),
              let name = locale.localizedString(forLanguageCode: languageCode),
              name.lowercased() != languageCode else { return nil }
        return name
    }

    private static func primarySubtag(of tag: String?) -> String? {
        guard let subtag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "-" || $0 == "_" }).first else { return nil }
        return subtag.lowercased()
    }
}
