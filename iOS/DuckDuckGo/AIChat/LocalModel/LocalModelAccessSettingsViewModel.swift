//
//  LocalModelAccessSettingsViewModel.swift
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

import AIChat
import Combine
import Core
import SwiftUI

/// Settings → AI Features → Local Model Access.
@MainActor
final class LocalModelAccessSettingsViewModel: ObservableObject {

    /// The flag is on and Apple Intelligence is ready on this device.
    @Published private(set) var isAvailable = false
    @Published private(set) var isOn = false
    @Published var isConfirmingTurnOn = false

    let modelName: String

    private let service: AIChatLocalModelService
    private let openURL: (URL) -> Void
    private var cancellable: AnyCancellable?

    init(service: AIChatLocalModelService, openURL: @escaping (URL) -> Void) {
        self.service = service
        self.openURL = openURL
        self.modelName = service.model.name
        update()
        cancellable = service.changesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.update() }
    }

    /// Stays on while the confirmation is up, so Cancel visibly flips it back.
    var isOnBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return false }
                return self.isOn || self.isConfirmingTurnOn
            },
            set: { [weak self] isOn in
                guard let self else { return }
                if isOn {
                    self.isConfirmingTurnOn = true
                } else {
                    self.service.optOut()
                }
            }
        )
    }

    /// Apple Intelligence can be turned on or off in iOS Settings while the app is away.
    func refresh() {
        service.refreshAvailability()
        update()
    }

    func confirmTurnOn() {
        isConfirmingTurnOn = false
        service.optIn()
    }

    func cancelTurnOn() {
        isConfirmingTurnOn = false
    }

    func openLearnMore() {
        openURL(URL.aiChatHelpPages)
    }

    private func update() {
        isAvailable = service.isFeatureEnabled && service.availability.isAvailable
        isOn = service.isOptedIn
    }
}
