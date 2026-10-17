//
//  NewTabPageWelcomeModel.swift
//  DuckDuckGo
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

import Combine
import Foundation

@MainActor
final class NewTabPageWelcomeModel: ObservableObject {

    @Published private(set) var greeting = ""

    let contextChanges: AnyPublisher<Void, Never>

    private var hasSelectedGreeting = false
    private let greetingProvider: DaxGreetingProviding
    private let updateAppearance: (DaxGreetingContext.Appearance) -> Void

    init(greetingProvider: DaxGreetingProviding,
         contextChanges: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher(),
         updateAppearance: @escaping (DaxGreetingContext.Appearance) -> Void) {
        self.greetingProvider = greetingProvider
        self.contextChanges = contextChanges
        self.updateAppearance = updateAppearance
    }

    func refresh(appearance: DaxGreetingContext.Appearance) {
        updateAppearance(appearance)
        if hasSelectedGreeting {
            greeting = greetingProvider.getGreeting()
        } else {
            greeting = greetingProvider.getNewGreeting()
            hasSelectedGreeting = true
        }
    }
}
