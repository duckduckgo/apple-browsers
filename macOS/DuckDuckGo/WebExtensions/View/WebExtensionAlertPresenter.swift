//
//  WebExtensionAlertPresenter.swift
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

import AppKit

@MainActor
protocol WebExtensionAlertPresenterProtocol {
    func present(_ configuration: WebExtensionAlert.Configuration) async -> WebExtensionAlert.Response
}

@MainActor
final class WebExtensionAlertPresenter: WebExtensionAlertPresenterProtocol {
    private let windowProvider: () -> NSWindow?
    private let themeManager: ThemeManager

    init(windowProvider: @escaping () -> NSWindow?, themeManager: ThemeManager) {
        self.windowProvider = windowProvider
        self.themeManager = themeManager
    }

    func present(_ configuration: WebExtensionAlert.Configuration) async -> WebExtensionAlert.Response {
        guard let window = windowProvider(), window.attachedSheet == nil else { return .cancelled }
        return await WebExtensionAlert.present(configuration, themeManager: themeManager, in: window)
    }
}
