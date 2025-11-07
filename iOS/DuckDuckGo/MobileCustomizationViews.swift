//
//  MobileCustomizationViews.swift
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

import SwiftUI
import DesignResourcesKitIcons

protocol MobileCustomizationView { }

extension MobileCustomizationView {

    func buttonIconProvider(_ button: MobileCustomization.Button) -> Image? {
        if button == .none {
            return Image(uiImage: DesignSystemImages.Glyphs.Size16.eyeClosed)
        }
        guard let icon = button.smallIcon else { return nil }
        return Image(uiImage: icon)
    }

    func descriptionForOption(_ button: MobileCustomization.Button, isAIChatEnabled: Bool) -> String {
        switch button {
        case .share:
            UserText.actionShare
        case .addEditBookmark:
            UserText.keyCommandAddBookmark
        case .addEditFavorite:
            UserText.keyCommandAddFavorite
        case .zoom:
            UserText.textZoomMenuItem
        case .none:
            "Hide This Button"
        case .home:
            "Home"
        case .newTab:
            UserText.keyCommandNewTab
        case .bookmarks:
            UserText.actionOpenBookmarks
        case .fire:
            isAIChatEnabled ? UserText.settingsAutoClearTabsAndDataWithAIChat :  UserText.settingsAutoClearTabsAndData
        case .vpn:
            UserText.actionVPN
        case .passwords:
            UserText.actionOpenPasswords
        case .voiceSearch:
            "Voice Search"
        case .downloads:
            UserText.downloadsScreenTitle
        }
    }

}

struct AddressBarCustomizationPickerView: View, MobileCustomizationView {

    let isAIChatEnabled: Bool
    @Binding var selectedAddressBarButton: MobileCustomization.Button

    var body: some View {
        let options = MobileCustomization.addressBarButtons.sorted(by: { lhs, rhs in
            // Always put none at the end
            if lhs == .none { return false }
            if rhs == .none { return true }

            // Sort the rest by their localised display name
            return descriptionForOption(lhs, isAIChatEnabled: isAIChatEnabled).localizedCaseInsensitiveCompare(descriptionForOption(rhs, isAIChatEnabled: isAIChatEnabled)) == .orderedAscending
        })

        ListBasedPickerWithHeaderImage(
            title: "Address Bar Button",
            headerImage: Image(.customAddressBarButtonPreview),
            options: options,
            defaultOption: MobileCustomization.addressBarDefault,
            selectedOption: $selectedAddressBarButton,
            descriptionForOption: {
                descriptionForOption($0, isAIChatEnabled: isAIChatEnabled)
            },
            iconProvider: buttonIconProvider)
    }

}

struct ToolbarCustomizationPickerView: View, MobileCustomizationView {

    let isAIChatEnabled: Bool
    @Binding var selectedToolbarButton: MobileCustomization.Button

    var body: some View {
        let options = MobileCustomization.toolbarButtons.sorted(by: { lhs, rhs in
            return descriptionForOption(lhs, isAIChatEnabled: isAIChatEnabled).localizedCaseInsensitiveCompare(descriptionForOption(rhs, isAIChatEnabled: isAIChatEnabled)) == .orderedAscending
        })

        ListBasedPickerWithHeaderImage(
            title: "Toolbar Button",
            headerImage: Image(.customToolbarButtonPreview),
            options: options,
            defaultOption: MobileCustomization.toolbarDefault,
            selectedOption: $selectedToolbarButton,
            descriptionForOption: {
                descriptionForOption($0, isAIChatEnabled: isAIChatEnabled)
            },
            iconProvider: buttonIconProvider)
    }

}
