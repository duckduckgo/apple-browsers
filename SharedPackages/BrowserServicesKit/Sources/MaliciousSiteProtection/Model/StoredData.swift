//
//  StoredData.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

protocol MaliciousSiteDataKey: Hashable {
    associatedtype EmbeddedDataSet: Decodable
    associatedtype DataSet: IncrementallyUpdatableDataSet, LoadableFromEmbeddedData<EmbeddedDataSet>

    var dataType: DataManager.StoredDataType { get }
    var threatKind: ThreatKind { get }
}

public extension DataManager {
    enum StoredDataType: Hashable, CaseIterable {
        case hashPrefixSet(HashPrefixes)
        case filterSet(FilterSet)

        public enum Kind: String, CaseIterable {
            case hashPrefixSet, filterSet
        }
        // keep to get a compiler error when number of cases changes
        var kind: Kind {
            switch self {
            case .hashPrefixSet: .hashPrefixSet
            case .filterSet: .filterSet
            }
        }

        var dataKey: any MaliciousSiteDataKey {
            switch self {
            case .hashPrefixSet(let key): key
            case .filterSet(let key): key
            }
        }

        public var threatKind: ThreatKind {
            switch self {
            case .hashPrefixSet(let key): key.threatKind
            case .filterSet(let key): key.threatKind
            }
        }

        public static var allCases: [DataManager.StoredDataType] {
            ThreatKind.allCases.map { threatKind in
                Kind.allCases.map { dataKind in
                    switch dataKind {
                    case .hashPrefixSet: .hashPrefixSet(.init(threatKind: threatKind))
                    case .filterSet: .filterSet(.init(threatKind: threatKind))
                    }
                }
            }.flatMap { $0 }
        }

        static func dataTypes(for kind: DataManager.StoredDataType.Kind, supportedThreats: [ThreatKind]) -> [DataManager.StoredDataType] {
            supportedThreats.map { threatKind in
                switch kind {
                case .hashPrefixSet: .hashPrefixSet(.init(threatKind: threatKind))
                case .filterSet: .filterSet(.init(threatKind: threatKind))
                }
            }
        }

    }
}

public extension DataManager.StoredDataType {
    struct HashPrefixes: MaliciousSiteDataKey {
        typealias DataSet = HashPrefixSet

        let threatKind: ThreatKind

        var dataType: DataManager.StoredDataType {
            .hashPrefixSet(self)
        }
    }
}
extension MaliciousSiteDataKey where Self == DataManager.StoredDataType.HashPrefixes {
    static func hashPrefixes(threatKind: ThreatKind) -> Self {
        .init(threatKind: threatKind)
    }
}

public extension DataManager.StoredDataType {
    struct FilterSet: MaliciousSiteDataKey {
        typealias DataSet = FilterDictionary

        let threatKind: ThreatKind

        var dataType: DataManager.StoredDataType {
            .filterSet(self)
        }
    }
}
extension MaliciousSiteDataKey where Self == DataManager.StoredDataType.FilterSet {
    static func filterSet(threatKind: ThreatKind) -> Self {
        .init(threatKind: threatKind)
    }
}
