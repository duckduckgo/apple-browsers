//
//  NewTabPageSearchInputModel.swift
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
import Foundation

@MainActor
final class NewTabPageSearchInputModel: ObservableObject {

    struct Settings: Equatable {
        var isModeToggleShown: Bool
        var isAIChatEnabled: Bool
        var isVoiceSearchEnabled: Bool
        var defaultTextEntryMode: TextEntryMode
    }

    @Published private(set) var settings: Settings
    @Published var textEntryMode: TextEntryMode

    private let readSettings: () -> Settings
    private var cancellables = Set<AnyCancellable>()

    init(notificationCenter: NotificationCenter = .default, readSettings: @escaping () -> Settings) {
        self.readSettings = readSettings
        let settings = readSettings()
        self.settings = settings
        textEntryMode = settings.defaultTextEntryMode.displayed(isAIChatSearchInputEnabled: settings.isModeToggleShown)

        notificationCenter.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.settings = self.readSettings()
                self.textEntryMode = self.settings.defaultTextEntryMode.displayed(
                    isAIChatSearchInputEnabled: self.settings.isModeToggleShown)
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: .speechRecognizerDidChangeAvailability)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.settings.isVoiceSearchEnabled = self.readSettings().isVoiceSearchEnabled
            }
            .store(in: &cancellables)
    }
}
