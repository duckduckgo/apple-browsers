//
//  PageLanguageDetectorTests.swift
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
import Testing
import WebPageTranslation

@Suite
struct PageLanguageDetectorTests {

    private static let english = """
        The weather was mild this morning, so we walked along the river before breakfast. \
        Several shops in the old town had already opened their doors. \
        We bought fresh bread and sat on a bench to watch the boats go by.
        """

    private static let french = """
        Le temps était doux ce matin, alors nous avons marché le long de la rivière avant le petit déjeuner. \
        Plusieurs boutiques de la vieille ville avaient déjà ouvert leurs portes. \
        Nous avons acheté du pain frais et nous nous sommes assis sur un banc pour regarder passer les bateaux.
        """

    private let detector = PageLanguageDetector()

    @available(iOS 16, macOS 13, *)
    @Test("detects English", .timeLimit(.minutes(1)))
    func detectsEnglish() async {
        #expect(await detector.detectLanguage(of: Self.english) == "en")
    }

    @available(iOS 16, macOS 13, *)
    @Test("detects French", .timeLimit(.minutes(1)))
    func detectsFrench() async {
        #expect(await detector.detectLanguage(of: Self.french) == "fr")
    }

    @available(iOS 16, macOS 13, *)
    @Test("empty text has no language", .timeLimit(.minutes(1)))
    func emptyTextIsNil() async {
        #expect(await detector.detectLanguage(of: "") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("a language CLD2 isn't sure of is no language", .timeLimit(.minutes(1)))
    func unreliableLanguageIsNil() async {
        // CLD2 picks "es" for this four-way mix but marks it unreliable.
        let mixed = "Le chien court vite dans le pré vert et aboie fort. Il cane corre veloce sul prato verde e abbaia forte. "
            + "El perro corre rápido por el prado verde y ladra fuerte. O cão corre rápido pelo prado verde e late alto. "
        #expect(await detector.detectLanguage(of: mixed) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("concurrent calls are safe", .timeLimit(.minutes(1)))
    func concurrentCallsAreSafe() async {
        let detector = detector
        let results = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { await detector.detectLanguage(of: Self.english) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results == Array(repeating: "en", count: 20))
    }
}
