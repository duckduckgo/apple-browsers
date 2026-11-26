//
//  TranslationOffer.swift
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

/// A translation to offer, as the manifest pair spells its languages.
public struct TranslationOffer: Equatable, Sendable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public enum TranslationOfferDecision: Equatable, Sendable {
    case banner(TranslationOffer)
    /// The page is in one of the user's languages, but not the first: no banner, translation stays in the menu.
    case menuOnly(TranslationOffer)
    case noOffer(Reason)

    public enum Reason: Equatable, Sendable {
        /// CLD2 couldn't tell the language reliably.
        case unreliable
        /// The page is in the user's first language.
        case firstDeviceLanguage
        /// No pair from the page's language to another of the user's languages.
        case missingLanguage
    }
}

extension TranslationManifest {

    /// What to offer for a page in `detectedLanguage` (nil when detection was unreliable),
    /// given the user's languages in order of preference.
    public func offerDecision(detectedLanguage: String?,
                              deviceLanguages: [String]) -> TranslationOfferDecision {
        guard let detectedLanguage else {
            return .noOffer(.unreliable)
        }

        let source = Self.primaryLanguage(detectedLanguage)
        let targets = deviceLanguages.map(Self.primaryLanguage)
        guard targets.first != source else {
            return .noOffer(.firstDeviceLanguage)
        }

        // Return first match, since device languages are ordered by preference
        for target in targets where target != source {
            if let pair = pair(from: source, to: target) {
                let offer = TranslationOffer(source: pair.sourceLanguage, target: pair.targetLanguage)
                // The user reads the page's language, just not as their first: offer it in the menu. Otherwise, show the banner.
                return targets.contains(source) ? .menuOnly(offer) : .banner(offer)
            }
        }
        return .noOffer(.missingLanguage)
    }

    /// The manifest pair between two primary language codes, however the manifest spells them.
    private func pair(from source: String, to target: String) -> Pair? {
        models.values.first { pair in
            Self.primaryLanguage(pair.sourceLanguage) == source && Self.primaryLanguage(pair.targetLanguage) == target
        }
    }

    /// CLD2 still reports some languages by their pre-ISO 639 codes.
    private static let legacyCodes = ["iw": "he", "no": "nb", "in": "id", "ji": "yi"]

    /// `en-GB` and `en_US` are both `en`.
    private static func primaryLanguage(_ code: String) -> String {
        let primary = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return legacyCodes[primary] ?? primary
    }
}
