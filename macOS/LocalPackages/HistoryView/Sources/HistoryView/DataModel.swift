//
//  DataModel.swift
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

public enum DataModel {

    public struct HistoryItemsBatch: Codable, Equatable {
        public let finished: Bool
        public let visits: [HistoryItem]

        public init(finished: Bool, visits: [HistoryItem]) {
            self.finished = finished
            self.visits = visits
        }
    }

    public enum DeleteDialogResponse: String, Codable {
        case delete, domainSearch = "domain-search", noAction = "none"
    }

    public enum HistoryRange: String, Codable {
        case all
        case today
        case yesterday
        case sunday
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
        case older
        case allSites = "sites"
    }

    public struct HistoryRangeWithCount: Codable, Equatable {
        public let id: HistoryRange
        public let count: Int

        public init(id: HistoryRange, count: Int) {
            self.id = id
            self.count = count
        }
    }

    public enum HistoryQueryKind: Codable, Equatable {
        case searchTerm(String)
        case domainFilter(Set<String>)
        case rangeFilter(HistoryRange)
        case dateFilter(Date)
        case visits([VisitIdentifier])

        enum CodingKeys: CodingKey {
            case term, range, domain
        }

        public var historyRange: HistoryRange? {
            guard case .rangeFilter(let range) = self else { return nil }
            return range
        }

        public init(from decoder: any Decoder) throws {
            if let singleValueContainer = try? decoder.singleValueContainer(),
               let value = try? singleValueContainer.decode(Date.self) {
                self = .dateFilter(value)
                return
            } else if var unkeyedContainer = try? decoder.unkeyedContainer(),
                      let value = try? unkeyedContainer.decode([VisitIdentifier].self) {
                self = .visits(value)
                return
            }

            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            if let term = try container.decodeIfPresent(String.self, forKey: CodingKeys.term) {
                self = .searchTerm(term)
            } else if let domain = try? container.decodeIfPresent(String.self, forKey: CodingKeys.domain) {
                self = .domainFilter([domain])
            } else if let domains = try container.decodeIfPresent([String].self, forKey: CodingKeys.domain) {
                self = .domainFilter(Set(domains))
            } else if let range = try container.decodeIfPresent(HistoryRange.self, forKey: CodingKeys.range) {
                self = .rangeFilter(range)
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unkown query kind"))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            lazy var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .searchTerm(let searchTerm):
                try container.encode(searchTerm, forKey: CodingKeys.term)
            case .domainFilter(let domains) where domains.count == 1:
                try container.encode(domains.first!, forKey: CodingKeys.domain)
            case .domainFilter(let domains):
                try container.encode(domains, forKey: CodingKeys.domain)
            case .rangeFilter(let range):
                try container.encode(range, forKey: CodingKeys.range)
            case .dateFilter(let date):
                var container = encoder.singleValueContainer()
                try container.encode(date)
            case .visits(let visits):
                var container = encoder.unkeyedContainer()
                try container.encode(visits)
            }
        }
    }

    public enum HistoryQuerySource: String, Codable {
        case initial, user, auto
    }

    public struct HistoryQuery: Codable, Equatable {
        let query: HistoryQueryKind
        let source: HistoryQuerySource
        let limit: Int
        let offset: Int

        public init(query: HistoryQueryKind, source: HistoryQuerySource, limit: Int, offset: Int) {
            self.query = query
            self.source = source
            self.limit = limit
            self.offset = offset
        }
    }

    public struct HistoryItem: Codable, Equatable {
        public let id: String
        public let url: String
        public let title: String

        public let domain: String
        public let etldPlusOne: String?

        public let dateRelativeDay: String
        public let dateShort: String
        public let dateTimeOfDay: String
        public let favicon: Favicon?

        public init(id: String, url: String, title: String, domain: String, etldPlusOne: String?, dateRelativeDay: String, dateShort: String, dateTimeOfDay: String, favicon: Favicon?) {
            self.id = id
            self.url = url
            self.title = title
            self.domain = domain
            self.etldPlusOne = etldPlusOne
            self.dateRelativeDay = dateRelativeDay
            self.dateShort = dateShort
            self.dateTimeOfDay = dateTimeOfDay
            self.favicon = favicon
        }
    }

    public struct Favicon: Codable, Equatable {
        public let maxAvailableSize: Int
        public let src: String

        public init(maxAvailableSize: Int, src: String) {
            self.maxAvailableSize = maxAvailableSize
            self.src = src
        }
    }
}

extension DataModel {

    struct Configuration: Encodable {
        var env: String
        var locale: String
        var platform: Platform
        var theme: String
        var themeVariant: String

        struct Platform: Encodable, Equatable {
            var name: String
        }
    }

    struct ThemeUpdate: Encodable {
        var theme: String
        var themeVariant: String
    }

    struct Exception: Codable, Equatable {
        let message: String
    }

    struct GetRangesResponse: Codable, Equatable {
        let ranges: [HistoryRangeWithCount]
    }

    struct DeleteDomainRequest: Codable, Equatable {
        let domain: String
    }

    struct DeleteRangeRequest: Codable, Equatable {
        let range: HistoryRange
    }

    struct DeleteTermRequest: Codable, Equatable {
        let term: String
    }

    struct DeleteTermResponse: Codable, Equatable {
        let action: DeleteDialogResponse
    }

    struct DeleteRangeResponse: Codable, Equatable {
        let action: DeleteDialogResponse
    }

    struct EntriesMenuRequest: Codable, Equatable {
        let ids: [String]
    }

    struct EntriesMenuResponse: Codable, Equatable {
        let action: DeleteDialogResponse
    }

    struct HistoryQueryInfo: Codable, Equatable {
        let finished: Bool
        let query: HistoryQueryKind
    }

    struct HistoryQueryResponse: Codable, Equatable {
        let info: HistoryQueryInfo
        let value: [HistoryItem]
    }

    struct HistoryOpenAction: Codable {
        let url: String
    }
}
