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
        public static let embeddedDataETag = "\"c46ecc17e4142325b86f3b93648d6842\""
        public static let embeddedDataSHA = "24aa4e5af167f48175bb591880f4397ebd4d9854e5f3d2303ce138c313448053"
    }

#if DEBUG || REVIEW
    public enum EnvironmentKeys {
        /// Used for automated testing to allow overriding Privacy Config with a local file
        public static let testPrivacyConfigPath = "TEST_PRIVACY_CONFIG_PATH"
    }
#endif

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
