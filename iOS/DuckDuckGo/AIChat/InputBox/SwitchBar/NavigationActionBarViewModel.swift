//
//  NavigationActionBarViewModel.swift
//  DuckDuckGo
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
import Combine
import SwiftUI

// MARK: - NavigationActionBarViewModel

@MainActor
final class NavigationActionBarViewModel: ObservableObject {

    // MARK: - Published Properties
    @Published var isSearchMode: Bool = true
    @Published var hasText: Bool = false
    @Published var isWebSearchEnabled: Bool = false
    @Published var isVoiceSearchEnabled: Bool = true
    @Published var hasUserInteractedWithText: Bool = false
    @Published var isCurrentTextValidURL: Bool = false

    // MARK: - Dependencies
    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Action Callbacks
    let onMicrophoneTapped: () -> Void
    let onNewLineTapped: () -> Void
    let onSearchTapped: () -> Void

    // MARK: - Initialization
    init(switchBarHandler: SwitchBarHandling,
         onMicrophoneTapped: @escaping () -> Void = {},
         onNewLineTapped: @escaping () -> Void = {},
         onSearchTapped: @escaping () -> Void = {}) {

        self.switchBarHandler = switchBarHandler
        self.onMicrophoneTapped = onMicrophoneTapped
        self.onNewLineTapped = onNewLineTapped
        self.onSearchTapped = onSearchTapped

        setupBindings()
        updateInitialState()
    }

    // MARK: - Private Methods
    private func setupBindings() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] toggleState in
                self?.isSearchMode = toggleState == .search
            }
            .store(in: &cancellables)

        switchBarHandler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (text: String) in
                let hasText = !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                self?.hasText = hasText
            }
            .store(in: &cancellables)

        switchBarHandler.forceWebSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] forceWebSearch in
                self?.isWebSearchEnabled = forceWebSearch
            }
            .store(in: &cancellables)

        switchBarHandler.hasUserInteractedWithTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasUserInteractedWithText in
                self?.hasUserInteractedWithText = hasUserInteractedWithText
            }
            .store(in: &cancellables)

        switchBarHandler.isCurrentTextValidURLPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isValidURL in
                self?.isCurrentTextValidURL = isValidURL
            }
            .store(in: &cancellables)
    }

    private func updateInitialState() {
        isSearchMode = switchBarHandler.currentToggleState == .search
        hasText = !switchBarHandler.currentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        isWebSearchEnabled = switchBarHandler.forceWebSearch
        isVoiceSearchEnabled = switchBarHandler.isVoiceSearchEnabled
        hasUserInteractedWithText = false
        isCurrentTextValidURL = switchBarHandler.isCurrentTextValidURL
    }

    // MARK: - Public Methods
    func handleWebSearchToggle() {
        switchBarHandler.toggleForceWebSearch()
    }

    var shouldShowMicButton: Bool {
        /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210777323867681?focus=true
        guard isVoiceSearchEnabled else { return false }

        if !hasText {
            return true
        }

        if hasText && hasUserInteractedWithText {
            return false
        }

        return true
    }
}
