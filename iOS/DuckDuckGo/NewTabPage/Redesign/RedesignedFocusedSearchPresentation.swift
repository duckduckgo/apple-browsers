//
//  RedesignedFocusedSearchPresentation.swift
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

/// Observes existing input facts only while a redesigned focused layout is installed.
/// This state does not participate in the shared content resolver or suggestion fetching.
@MainActor
final class RedesignedFocusedSearchPresentation: ObservableObject {
    @Published private(set) var showsSearchModules = false
    private var cancellable: AnyCancellable?

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         dismissPublisher: AnyPublisher<UnifiedSuggestionsViewModel.DismissBehavior, Never>,
         fireTabPublisher: AnyPublisher<Bool, Never>) {
        cancellable = Publishers.CombineLatest3(inputsPublisher, dismissPublisher, fireTabPublisher)
            .sink { [weak self] inputs, dismissBehavior, isFireTab in
                guard let self, dismissBehavior == .none else { return }
                let showsSearchModules = inputs.mode == .search && !inputs.isTyping && !isFireTab
                    && (inputs.hasFavorites || inputs.hasMessages)
                guard self.showsSearchModules != showsSearchModules else { return }
                self.showsSearchModules = showsSearchModules
            }
    }
}
