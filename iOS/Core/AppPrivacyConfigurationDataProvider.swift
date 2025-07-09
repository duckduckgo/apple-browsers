//
//  AppPrivacyConfigurationDataProvider.swift
//  Core
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
import BrowserServicesKit

final public class AppPrivacyConfigurationDataProvider: EmbeddedDataProvider {

    public struct Constants {
        public static let embeddedDataETag = "\"6efcf15957019fd1fecee36321d2f008\""
        public static let embeddedDataSHA = "b5d6b878543cd018f42b679c966d88715b678c177a3a070599b396f9184199ed"
    }

    public var embeddedDataEtag: String {
        return Constants.embeddedDataETag
    }

    public var embeddedData: Data {
        return Self.loadEmbeddedAsData()
    }

    static var embeddedUrl: URL {
        if let url = Bundle.main.url(forResource: "ios-config", withExtension: "json") {
            return url
        }

        return Bundle(for: self).url(forResource: "ios-config", withExtension: "json")!
    }

    static func loadEmbeddedAsData() -> Data {
        let json = try? Data(contentsOf: embeddedUrl)
        return json!
    }
}
