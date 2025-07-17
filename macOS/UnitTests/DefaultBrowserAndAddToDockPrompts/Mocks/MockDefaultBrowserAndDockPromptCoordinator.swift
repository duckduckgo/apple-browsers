//
//  MockDefaultBrowserAndDockPromptCoordinator.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class MockDefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {
    var getPromptTypeResult: DefaultBrowserAndDockPromptPresentationType?
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType?

    private(set) var wasPromptConfirmationCalled = false
    private(set) var wasDismissPromptCalled = false
    private(set) var capturedConfirmationPrompt: DefaultBrowserAndDockPromptPresentationType?
    private(set) var capturedDismissAction: DefaultBrowserAndDockPromptDismissAction?

    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType? {
        getPromptTypeResult
    }

    func confirmAction(for prompt: DefaultBrowserAndDockPromptPresentationType) {
        wasPromptConfirmationCalled = true
        capturedConfirmationPrompt = prompt
    }

    func dismissAction(_ action: DefaultBrowserAndDockPromptDismissAction) {
        wasDismissPromptCalled = true
        capturedDismissAction = action
    }
}
