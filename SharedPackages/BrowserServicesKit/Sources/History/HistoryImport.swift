//
//  HistoryImport.swift
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

public enum HistoryImport {
    public struct Visit: Equatable, Sendable {
        public let url: URL
        public let title: String?
        public let date: Date

        public init(url: URL, title: String?, date: Date) {
            self.url = url
            self.title = title
            self.date = date
        }
    }

    public struct ParseResult: Equatable, Sendable {
        public let visits: [Visit]
        /// Rows the browser reader could not turn into a visit, such as redirects, failed loads and non-web URLs.
        public let skipped: Int

        public init(visits: [Visit], skipped: Int) {
            self.visits = visits
            self.skipped = skipped
        }
    }

    public struct Summary: Equatable, Sendable {
        public var imported = 0
        public var alreadyInHistory = 0
        /// Older than the history retention window, so they would be deleted on the next cleanup.
        public var tooOld = 0
        public var skipped = 0

        public init(imported: Int = 0, alreadyInHistory: Int = 0, tooOld: Int = 0, skipped: Int = 0) {
            self.imported = imported
            self.alreadyInHistory = alreadyInHistory
            self.tooOld = tooOld
            self.skipped = skipped
        }
    }

    public enum Error: Swift.Error {
        case historyNotLoaded
        case importInProgress
    }
}
