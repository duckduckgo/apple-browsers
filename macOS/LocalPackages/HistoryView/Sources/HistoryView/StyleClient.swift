//
//  StyleClient.swift
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

import AppKit
import Combine
import Common
import os.log
import UserScriptActionsManager
import WebKit

public protocol StyleProviding: AnyObject {
    var themeAppearance: String { get }
    var themeName: String { get }
    var themeStylePublisher: AnyPublisher<(appearance: String, themeName: String), Never> { get }
}

public final class StyleClient: HistoryViewUserScriptClient {

    private let styleProviding: StyleProviding
    private var cancellables: Set<AnyCancellable> = []

    public init(styleProviding: StyleProviding) {
        self.styleProviding = styleProviding
        super.init()

        styleProviding.themeStylePublisher
            .sink { [weak self] appearance, themeName in
                Task { @MainActor in
                    self?.notifyThemeStyle(appearance: appearance, themeName: themeName)
                }
            }
            .store(in: &cancellables)
    }

    enum MessageName: String, CaseIterable {
        case onThemeUpdate
    }

    public override func registerMessageHandlers(for userScript: HistoryViewUserScript) {
        // NO-OP
    }

    @MainActor
    private func notifyThemeStyle(appearance: String, themeName: String) {
        let payload = DataModel.ThemeUpdate(theme: appearance, themeVariant: themeName)
        pushMessage(named: MessageName.onThemeUpdate.rawValue, params: payload)
    }
}
