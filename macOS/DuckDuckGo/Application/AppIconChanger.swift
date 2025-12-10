//
//  AppIconChanger.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Cocoa
import Combine
import BrowserServicesKit

final class AppIconChanger {

    private var cancellables = Set<AnyCancellable>()
    private var isInternalUser: Bool = false
    private weak var appearancePreferences: AppearancePreferences?

    init(internalUserDecider: InternalUserDecider, appearancePreferences: AppearancePreferences) {
        self.appearancePreferences = appearancePreferences
        subscribeToIsInternal(internalUserDecider)
        subscribeToThemeChanges(appearancePreferences)
        subscribeToIconSyncPreferenceChanges(appearancePreferences)
    }

    func updateIcon(isInternalChannel: Bool, themeName: ThemeName? = nil, forceSyncCheck: Bool = true) {
        self.isInternalUser = isInternalChannel

        let shouldApplyThemeIcon = if forceSyncCheck {
            themeName != nil && appearancePreferences?.syncAppIconWithTheme == true
        } else {
            themeName != nil
        }

        if shouldApplyThemeIcon,
           let themeName = themeName,
           let themeIcon = icon(for: themeName) {
            NSApplication.shared.applicationIconImage = themeIcon
            return
        }

        // Fall back to internal user logic
        let icon: NSImage?
        if isInternalChannel {
#if DEBUG
            icon = .internalChannelIconDebug
#elseif REVIEW
            icon = .internalChannelIconReview
#elseif ALPHA
            icon = nil // Don't override icon for alpha builds
#else
            icon = .internalChannelIcon
#endif
        } else {
            icon = nil
        }

        NSApplication.shared.applicationIconImage = icon
    }

    private func subscribeToIsInternal(_ internalUserDecider: InternalUserDecider) {
        internalUserDecider.isInternalUserPublisher
            .sink { [weak self] isInternal in
                self?.updateIcon(isInternalChannel: isInternal)
            }
            .store(in: &cancellables)
    }

    private func subscribeToThemeChanges(_ appearancePreferences: AppearancePreferences) {
        appearancePreferences.$themeName
            .sink { [weak self] themeName in
                guard let self = self else { return }
                self.updateIcon(isInternalChannel: self.isInternalUser, themeName: themeName)
            }
            .store(in: &cancellables)
    }

    private func subscribeToIconSyncPreferenceChanges(_ appearancePreferences: AppearancePreferences) {
        appearancePreferences.$syncAppIconWithTheme
            .sink { [weak self] isSyncEnabled in
                guard let self = self else { return }
                let themeName = isSyncEnabled ? appearancePreferences.themeName : nil
                self.updateIcon(isInternalChannel: self.isInternalUser, themeName: themeName, forceSyncCheck: false)
            }
            .store(in: &cancellables)
    }

    private func icon(for themeName: ThemeName) -> NSImage? {
        let iconName: String

        switch themeName {
        case .default:
            iconName = "Browser-Theme-Default"
        case .coolGray:
            iconName = "Browser-Theme-CoolGray"
        case .desert:
            iconName = "Browser-Theme-Desert"
        case .green:
            iconName = "Browser-Theme-Green"
        case .orange:
            iconName = "Browser-Theme-Orange"
        case .rose:
            iconName = "Browser-Theme-Rose"
        case .slateBlue:
            iconName = "Browser-Theme-SlateBlue"
        case .violet:
            iconName = "Browser-Theme-Violet"
        }

        return NSImage(named: iconName)
    }

}
