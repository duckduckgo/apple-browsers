//
//  Visit.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

final public class Visit {

    public enum SavingState {
        case initialized
        case saved
    }

    public var savingState = SavingState.initialized

    public typealias ID = URL

    public init(date: Date, identifier: ID? = nil, historyEntry: HistoryEntry? = nil) {
        self.date = date
        self.identifier = identifier
        self.historyEntry = historyEntry
    }

    public let date: Date
    public var identifier: ID?
    public weak var historyEntry: HistoryEntry?

}

extension Visit: Hashable {

    public static func == (lhs: Visit, rhs: Visit) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

}

extension Visit: NSCopying {

    public func copy(with zone: NSZone? = nil) -> Any {
        let visit = Visit(date: date,
                          identifier: identifier,
                          historyEntry: nil)
        visit.savingState = savingState
        return visit
    }

}
