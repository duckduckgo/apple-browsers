//
//  RebrandedAppIconPickerViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SwiftUI

@MainActor
final class RebrandedAppIconPickerViewModel: ObservableObject {

    struct RebrandedDisplayModel {
        let icon: AppIcon
        let isSelected: Bool

        var color: Color { icon.color }
    }

    @Published private(set) var items: [RebrandedDisplayModel] = []

    private let appIconManager: AppIconManaging

    init(appIconManager: AppIconManaging = AppIconManager.shared) {
        self.appIconManager = appIconManager
        items = makeDisplayModels()
    }

    func changeApp(icon: AppIcon) {
        appIconManager.changeAppIcon(icon) { [weak self] error in
            guard let self, error == nil else { return }
            DispatchQueue.main.async {
                self.items = self.makeDisplayModels()
            }
        }
    }

    var selectedIcon: AppIcon {
        appIconManager.appIcon
    }

    private func makeDisplayModels() -> [RebrandedDisplayModel] {
        AppIcon.allCases.map { appIcon in
            RebrandedDisplayModel(icon: appIcon,
                                  isSelected: appIconManager.appIcon == appIcon)
        }
    }
}
