//
//  MockCustomConfigurationURLStore.swift
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

#if !RELEASE
import Foundation

final class MockCustomConfigurationURLStore: CustomConfigurationURLStoring {
    var customBloomFilterSpecURL: URL?
    var customBloomFilterBinaryURL: URL?
    var customBloomFilterExcludedDomainsURL: URL?
    var customPrivacyConfigurationURL: URL?
    var customTrackerDataSetURL: URL?
    var customSurrogatesURL: URL?
    var customRemoteMessagingConfigURL: URL?
}
#endif
