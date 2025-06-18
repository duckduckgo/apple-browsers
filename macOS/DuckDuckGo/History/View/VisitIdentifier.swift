//
//  VisitIdentifier.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import History

/**
 * This struct is used to identify a single visit in the History View.
 *
 * It implements `LosslessStringConvertible` in order to be exchanged with the web Frontend.
 *
 * Pipe (`|`) is used as components separator in `description` because:
 * - `uuid` field is an actual UUID (see `HistoryEntry`) and it's guaranteed to not contain pipes,
 * - `url` doesn't allow pipe characters (they must be escaped) as per the RFC,
 * - `date`'s time interval is a number.
 */
struct VisitIdentifier: LosslessStringConvertible {
    init?(_ description: String) {
        let components = description.components(separatedBy: "|").filter { !$0.isEmpty }
        guard components.count == 3, let url = components[1].url, let timeInterval = TimeInterval(components[2]) else {
            return nil
        }
        self.init(uuid: components[0], url: url, date: .init(timeIntervalSince1970: timeInterval))
    }

    init(historyEntry: HistoryEntry, date: Date) {
        self.uuid = historyEntry.identifier.uuidString
        self.url = historyEntry.url
        self.date = date
    }

    init(uuid: String, url: URL, date: Date) {
        self.uuid = uuid
        self.url = url
        self.date = date
    }

    var description: String {
        [uuid, url.absoluteString, String(date.timeIntervalSince1970)].joined(separator: "|")
    }

    let uuid: String
    let url: URL
    let date: Date
}
