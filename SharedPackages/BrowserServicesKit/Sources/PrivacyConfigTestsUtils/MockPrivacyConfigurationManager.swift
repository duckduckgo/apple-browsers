//
//  MockPrivacyConfigurationManager.swift
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

import Combine
import Foundation
import PrivacyConfig

public class MockPrivacyConfigurationManager: PrivacyConfigurationManaging {
    public var currentConfigString: String = ""
    public var currentConfig: Data {
        currentConfigString.data(using: .utf8)!
    }
    public var updatesSubject = PassthroughSubject<Void, Never>()
    public let updatesPublisher: AnyPublisher<Void, Never>
    public var privacyConfig: PrivacyConfiguration
    public let internalUserDecider: InternalUserDecider
    public func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }

    public init(privacyConfig: PrivacyConfiguration = MockPrivacyConfiguration(), internalUserDecider: InternalUserDecider = MockInternalUserDecider()) {
        self.updatesPublisher = updatesSubject.eraseToAnyPublisher()
        self.privacyConfig = privacyConfig
        self.internalUserDecider = internalUserDecider
    }
}
