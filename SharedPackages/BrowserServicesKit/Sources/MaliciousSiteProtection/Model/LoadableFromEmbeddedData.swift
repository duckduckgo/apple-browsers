//
//  LoadableFromEmbeddedData.swift
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

public protocol LoadableFromEmbeddedData<EmbeddedDataSet> {
    /// Set Element Type (Hash Prefix or Filter)
    associatedtype Element
    /// Decoded data type stored in the embedded json file
    associatedtype EmbeddedDataSet: Decodable, Sequence where EmbeddedDataSet.Element == Self.Element

    init(revision: Int, items: some Sequence<Element>)
}

extension HashPrefixSet: LoadableFromEmbeddedData {
    public typealias EmbeddedDataSet = [String]
}

extension FilterDictionary: LoadableFromEmbeddedData {
    public typealias EmbeddedDataSet = [Filter]
}
