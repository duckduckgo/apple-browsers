//
//  PageTranslationBatches.swift
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

/// Splits a page's units into batches the way the translation contract sets out.
public enum PageTranslationBatches {

    /// Visible units first, then the rest, each in page order. Plain and HTML units fill separate batches,
    /// so a page that alternates them doesn't make tiny ones; batches come out in the order of their first unit.
    public static func make(_ units: [PageTranslationUnit], characterLimit: Int) -> [[PageTranslationUnit]] {
        let ordered = units.filter(\.isVisible) + units.filter { !$0.isVisible }

        let plain = chunk(ordered.filter { !$0.html }, characterLimit: characterLimit)
        let html = chunk(ordered.filter(\.html), characterLimit: characterLimit)

        return sortedByFirstUnit(plain + html, in: ordered)
    }

    /// Puts batches in the order their first unit appears in `units`, so plain and HTML batches interleave
    /// as they do on the page instead of all plain batches coming first.
    private static func sortedByFirstUnit(_ batches: [[PageTranslationUnit]], in units: [PageTranslationUnit]) -> [[PageTranslationUnit]] {
        // Each unit's index in `units`, by id.
        let indexByID = Dictionary(units.enumerated().map { index, unit in (unit.id, index) },
                                   uniquingKeysWith: { first, _ in first })

        // `chunk` never makes an empty batch, so every batch has a first unit, and every unit is in `indexByID`.
        return batches.sorted { first, second in
            indexByID[first[0].id, default: 0] < indexByID[second[0].id, default: 0]
        }
    }

    /// Adds units to a batch until the next one would pass the limit; a longer unit goes alone, never split.
    private static func chunk(_ units: [PageTranslationUnit], characterLimit: Int) -> [[PageTranslationUnit]] {
        var batches: [[PageTranslationUnit]] = []
        var current: [PageTranslationUnit] = []
        var characters = 0
        for unit in units {
            let count = characterCount(of: unit)
            if !current.isEmpty && characters + count > characterLimit {
                batches.append(current)
                current = []
                characters = 0
            }
            current.append(unit)
            characters += count
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    /// What the engine translates: an HTML unit's text without its tags.
    static func characterCount(of unit: PageTranslationUnit) -> Int {
        guard unit.html else { return unit.text.count }
        return unit.text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression).count
    }
}
