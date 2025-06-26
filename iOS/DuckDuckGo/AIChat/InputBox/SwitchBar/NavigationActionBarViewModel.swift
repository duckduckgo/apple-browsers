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
                self?.hasText = !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            }
            .store(in: &cancellables)
        
        switchBarHandler.forceWebSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] forceWebSearch in
                self?.isWebSearchEnabled = forceWebSearch
            }
            .store(in: &cancellables)
    }
    
    private func updateInitialState() {
        isSearchMode = switchBarHandler.currentToggleState == .search
        hasText = !switchBarHandler.currentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        isWebSearchEnabled = switchBarHandler.forceWebSearch
        isVoiceSearchEnabled = switchBarHandler.isVoiceSearchEnabled
    }
    
    // MARK: - Public Methods
    
    func handleWebSearchToggle() {
        switchBarHandler.toggleForceWebSearch()
    }

    var shouldShowMicButton: Bool {
        isVoiceSearchEnabled
    }
}
