//
//  Configuration.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public protocol ConfigurationURLProviding {

    func url(for configuration: Configuration) -> URL

}

public enum Configuration: String, CaseIterable, Sendable {

    case bloomFilterBinary
    case bloomFilterSpec
    case bloomFilterExcludedDomains
    case privacyConfiguration
    case surrogates
    case trackerDataSet
    case remoteMessagingConfig

    private static var urlProvider: ConfigurationURLProviding?
    public static func setURLProvider(_ urlProvider: ConfigurationURLProviding) {
        self.urlProvider = urlProvider
    }

    var url: URL {
        guard let urlProvider = Self.urlProvider else { fatalError("Please set the urlProvider before accessing url.") }
        return urlProvider.url(for: self)
    }

}
