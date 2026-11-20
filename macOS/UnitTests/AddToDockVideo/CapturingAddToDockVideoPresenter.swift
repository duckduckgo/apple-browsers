//
//  CapturingAddToDockVideoPresenter.swift
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

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class CapturingAddToDockVideoPresenter: AddToDockVideoPresenting {

    private(set) var presentations: [AddToDockVideoAction.Primary] = []
    var presentResult = true
    private var completion: ((AddToDockVideoAction) -> Void)?

    func present(primaryAction: AddToDockVideoAction.Primary, completion: @escaping (AddToDockVideoAction) -> Void) -> Bool {
        presentations.append(primaryAction)
        self.completion = completion
        return presentResult
    }

    func complete(with action: AddToDockVideoAction) {
        let completion = self.completion
        self.completion = nil
        completion?(action)
    }
}
