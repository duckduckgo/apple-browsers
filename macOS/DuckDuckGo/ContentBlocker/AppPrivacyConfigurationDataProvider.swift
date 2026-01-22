//
//  AppPrivacyConfigurationDataProvider.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import PrivacyConfig

final class AppPrivacyConfigurationDataProvider: EmbeddedDataProvider {

    public struct Constants {
        public static let embeddedDataETag = "\"0708a404967ad674a0a669b75607500b\""
        public static let embeddedDataSHA = "fc7533f1799eb3a027ff3b55253a7ee1c097ed3962975f7c67bbb16234123851"
    }

    var embeddedDataEtag: String {
        return Constants.embeddedDataETag
    }

    var embeddedData: Data {
        return Self.loadEmbeddedAsData()
    }

    static var embeddedUrl: URL {
        return Bundle.main.url(forResource: "macos-config", withExtension: "json")!
    }

    static func loadEmbeddedAsData() -> Data {
        let json = try? Data(contentsOf: embeddedUrl)
        return json!
    }
}
