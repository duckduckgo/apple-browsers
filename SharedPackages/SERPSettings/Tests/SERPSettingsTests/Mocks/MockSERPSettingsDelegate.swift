//
//  MockSERPSettingsDelegate.swift
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
@testable import SERPSettings

final class MockSERPSettingsDelegate: SERPSettingsUserScriptDelegate {

    var closeTabCallCount = 0
    var openAIFeaturesSettingsCallCount = 0

    func serpSettingsUserScriptDidRequestToCloseTab(_ userScript: SERPSettings.SERPSettingsUserScript) {
        closeTabCallCount += 1
    }

    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript) {
        openAIFeaturesSettingsCallCount += 1
    }

    func reset() {
        closeTabCallCount = 0
        openAIFeaturesSettingsCallCount = 0
    }
}
