//
//  PageTranslationSession.swift
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
import os.log
import WebPageTranslation

protocol PageTranslating: Sendable {
    func translate(_ units: [PageTranslationUnit], pairID: String) async throws -> [PageTranslationUpdate]
}

extension PageTranslator: PageTranslating {}

/// Translates one tab's page: extracts its text, translates it and writes it back.
/// The bridge stops a translation when the page changes, by failing its requests with `CancellationError`.
@MainActor
final class PageTranslationSession {

    private let bridge: PageTranslationBridging
    private let translator: PageTranslating
    private(set) var isTranslating = false

    init(bridge: PageTranslationBridging, translator: PageTranslating) {
        self.bridge = bridge
        self.translator = translator
    }

    /// Ignored while a translation is running.
    func start(_ offer: TranslationOffer) {
        guard !isTranslating else { return }
        isTranslating = true
        Task {
            await translate(offer)
            isTranslating = false
        }
    }

    private func translate(_ offer: TranslationOffer) async {
        do {
            let (units, documentID) = try await bridge.extract()
            let updates = try await translator.translate(units, pairID: offer.pairID)
            let count = try await bridge.apply(updates, from: offer.source, to: offer.target, in: documentID)
            Logger.webPageTranslation.info("Page translation: applied \(count, privacy: .public) of \(units.count, privacy: .public) units")
        } catch is CancellationError {
            Logger.webPageTranslation.info("Page translation cancelled")
        } catch {
            // TranslateKit's errors aren't LocalizedError, so the reason is only in the description; it may quote the page.
            Logger.webPageTranslation.error("""
                Page translation failed: \(error.localizedDescription, privacy: .public) \
                \(String(describing: error), privacy: .private)
                """)
        }
    }
}
