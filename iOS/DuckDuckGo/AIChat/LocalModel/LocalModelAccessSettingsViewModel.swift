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
import SwiftUI

/// Settings → AI Features → On-Device Model.
@MainActor
final class LocalModelAccessSettingsViewModel: ObservableObject {

    /// The flag is on, and Apple Intelligence is ready or the downloadable model can run instead.
    @Published private(set) var isAvailable = false
    @Published private(set) var isOn = false
    @Published var isConfirmingTurnOn = false
    @Published private(set) var modelName = ""
    /// The downloadable model's install state, or nil when the section shows Apple Intelligence.
    @Published private(set) var downloadableModelState: AIChatLocalModelInstallState?

    private let service: AIChatLocalModelService
    private var cancellable: AnyCancellable?

    init(service: AIChatLocalModelService) {
        self.service = service
        update()
        cancellable = service.changesPublisher
            // A download reports progress for every megabyte; the row doesn't need more than a few updates a second.
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.update() }
    }

    var downloadableModelBytes: Int64 {
        service.installer?.spec.bytes ?? 0
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
                    self.service.select(.duckAI, source: .settings)
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
        service.select(.appleIntelligence, source: .settings)
    }

    func cancelTurnOn() {
        isConfirmingTurnOn = false
    }

    /// Also Try Again after a failed download.
    func installDownloadableModel() {
        service.installDownloadableModel()
    }

    func cancelDownloadableModelInstall() {
        service.cancelDownloadableModelInstall()
    }

    func uninstallDownloadableModel() {
        service.uninstallDownloadableModel()
    }

    private func update() {
        let state = service.currentState
        isAvailable = state != nil && state != .unsupported
        isOn = service.isOptedIn
        modelName = service.model.name
        downloadableModelState = service.activeEngineKind == .llama ? service.installer?.state : nil
    }
}
