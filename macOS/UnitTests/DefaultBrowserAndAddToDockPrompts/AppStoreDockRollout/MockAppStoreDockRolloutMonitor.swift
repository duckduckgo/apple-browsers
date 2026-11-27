//
//  MockAppStoreDockRolloutMonitor.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

final class MockAppStoreDockRolloutMonitor: AppStoreDockRolloutMonitoring {

    struct ShownPrompt: Equatable {
        let type: DefaultBrowserAndDockPromptType
        let promptID: String
    }

    private(set) var shownPrompts: [ShownPrompt] = []
    private(set) var setAsDefaultRequestedCallCount = 0

    func promptShown(_ type: DefaultBrowserAndDockPromptType, promptID: String) {
        shownPrompts.append(ShownPrompt(type: type, promptID: promptID))
    }

    func setAsDefaultRequested() {
        setAsDefaultRequestedCallCount += 1
    }
}
