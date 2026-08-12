//
//  KeyboardPresenter.swift
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
import Core

@MainActor
protocol KeyboardPresenting {

    func showKeyboardOnLaunch(lastBackgroundDate: Date?)

}

final class KeyboardPresenter: KeyboardPresenting {

    private static let showKeyboardOnLaunchThreshold = TimeInterval(20)
    private let isKeyboardOnAppLaunchEnabled: () -> Bool
    private let scheduleKeyboardPresentation: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let enterSearch: @MainActor () -> Void

    init(mainViewController: MainViewController) {
        self.isKeyboardOnAppLaunchEnabled = { KeyboardSettings().onAppLaunch }
        self.scheduleKeyboardPresentation = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
        self.enterSearch = { mainViewController.enterSearch() }
    }

    init(
        isKeyboardOnAppLaunchEnabled: @escaping () -> Bool,
        scheduleKeyboardPresentation: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
        enterSearch: @escaping @MainActor () -> Void
    ) {
        self.isKeyboardOnAppLaunchEnabled = isKeyboardOnAppLaunchEnabled
        self.scheduleKeyboardPresentation = scheduleKeyboardPresentation
        self.enterSearch = enterSearch
    }

    func showKeyboardOnLaunch(lastBackgroundDate: Date? = nil) {
        guard isKeyboardOnAppLaunchEnabled() && shouldShowKeyboardOnLaunch(lastBackgroundDate: lastBackgroundDate) else { return }
        
        DailyPixel.fireDailyAndCount(pixel: .keyboardOnAppLaunchUsedDaily)
        
        scheduleKeyboardPresentation(0.1) {
            self.enterSearch()
        }
    }

    private func shouldShowKeyboardOnLaunch(lastBackgroundDate: Date? = nil) -> Bool {
        guard let lastBackgroundDate else { return true }
        return Date().timeIntervalSince(lastBackgroundDate) > Self.showKeyboardOnLaunchThreshold
    }

}
