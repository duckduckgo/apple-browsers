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
import PrivacyConfig

final public class AppPrivacyConfigurationDataProvider: EmbeddedDataProvider {

    public struct Constants {
        public static let embeddedDataETag = "\"59e7c44193b9eff2f5a6a2fd68a10b1e\""
        public static let embeddedDataSHA = "4673551f36463ce1270375c519c4cdca2f04c35d4e898928b0dcf6482daeebbe"
    }

#if DEBUG || ALPHA
    public enum EnvironmentKeys {
        /// Used for automated testing to allow overriding Privacy Config with a local file
        public static let testPrivacyConfigPath = "TEST_PRIVACY_CONFIG_PATH"
    }
#endif

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
        do {
            return try Data(contentsOf: embeddedUrl)
        } catch {
            fatalError("Failed to load embedded privacy config: \(error.localizedDescription)")
        }
    }

    public init() {}
}
