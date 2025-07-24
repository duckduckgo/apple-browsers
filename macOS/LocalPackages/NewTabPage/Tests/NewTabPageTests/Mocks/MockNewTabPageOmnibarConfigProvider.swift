//
//  MockNewTabPageOmnibarConfigProvider.swift
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

import Combine
import NewTabPage

final class MockNewTabPageOmnibarConfigProvider: NewTabPageOmnibarConfigProviding {
    @MainActor
    var mode: NewTabPageDataModel.OmnibarMode = .search

    @Published var isAIChatShortcutEnabled: Bool = true

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        $isAIChatShortcutEnabled.dropFirst().eraseToAnyPublisher()
    }

    @Published var isAIChatSettingVisible: Bool = true

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        $isAIChatSettingVisible.dropFirst().eraseToAnyPublisher()
    }
}
