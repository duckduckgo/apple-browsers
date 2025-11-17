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
            UserText.mobileCustomizationNoneOptionLong
        case .home:
            UserText.homeTabTitle
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
        case .downloads:
            UserText.downloadsScreenTitle
        }
    }

}

struct AddressBarCustomizationPickerView: View, MobileCustomizationView {

    let isAIChatEnabled: Bool

    @Binding var selectedAddressBarButton: MobileCustomization.Button

    @State var startingOption: MobileCustomization.Button?

    let mobileCustomization: MobileCustomization

    var body: some View {
        let options = MobileCustomization.addressBarButtons.sorted(by: { lhs, rhs in
            // Always put none at the end
            if lhs == .none { return false }
            if rhs == .none { return true }

            // Sort the rest by their localised display name
            return descriptionForOption(lhs, isAIChatEnabled: isAIChatEnabled).localizedCaseInsensitiveCompare(descriptionForOption(rhs, isAIChatEnabled: isAIChatEnabled)) == .orderedAscending
        })

        ListBasedPickerWithHeaderImage(
            title: UserText.mobileCustomizationAddressBarButton,
            headerImage: Image(.customAddressBarButtonPreview),
            options: options,
            defaultOption: MobileCustomization.addressBarDefault,
            selectedOption: $selectedAddressBarButton,
            descriptionForOption: {
                descriptionForOption($0, isAIChatEnabled: isAIChatEnabled)
            },
            iconProvider: buttonIconProvider)
        .onAppear {
            mobileCustomization.fireAddressBarCustomizationStartedPixel()
            startingOption = selectedAddressBarButton
        }
        .onDisappear {
            guard let startingOption else {
                assertionFailure()
                return
            }
            mobileCustomization.fireAddressBarCustomizationSelectedPixel(oldValue: startingOption)
        }
    }

}

struct ToolbarCustomizationPickerView: View, MobileCustomizationView {

    let isAIChatEnabled: Bool

    @Binding var selectedToolbarButton: MobileCustomization.Button

    @State var startingOption: MobileCustomization.Button?

    let mobileCustomization: MobileCustomization

    var body: some View {
        let options = MobileCustomization.toolbarButtons.sorted(by: { lhs, rhs in
            return descriptionForOption(lhs, isAIChatEnabled: isAIChatEnabled).localizedCaseInsensitiveCompare(descriptionForOption(rhs, isAIChatEnabled: isAIChatEnabled)) == .orderedAscending
        })

        ListBasedPickerWithHeaderImage(
            title: UserText.mobileCustomizationToolbarButton,
            headerImage: Image(.customToolbarButtonPreview),
            options: options,
            defaultOption: MobileCustomization.toolbarDefault,
            selectedOption: $selectedToolbarButton,
            descriptionForOption: {
                descriptionForOption($0, isAIChatEnabled: isAIChatEnabled)
            },
            iconProvider: buttonIconProvider)
        .onAppear {
            startingOption = selectedToolbarButton
            mobileCustomization.fireToolbarCustomizationStartedPixel()
        }
        .onDisappear {
            guard let startingOption else {
                assertionFailure()
                return
            }
            mobileCustomization.fireToolbarCustomizationSelectedPixel(oldValue: startingOption)
        }
    }

}

extension UserText {

    public static let mobileCustomizationSectionTitle = NSLocalizedString("mobile.customization.section.title", value: "Customizable Buttons", comment: "The title of the section in settings containing the customizable buttons.")

    public static let mobileCustomizationAddressBarTitle = NSLocalizedString("mobile.customization.addressbar.title", value: "Address Bar", comment: "The title of the Address Bar button.")

    public static let mobileCustomizationAddressBarButton = NSLocalizedString("mobile.customization.addressbar.button", value: "Address Bar Button", comment: "The name of the Address Bar button when referenced in settings.")

    public static let mobileCustomizationToolbarTitle = NSLocalizedString("mobile.customization.toolbar.title", value: "Toolbar", comment: "A label for the access point to customization of the Toolbar.")

    public static let mobileCustomizationToolbarButton = NSLocalizedString("mobile.customization.toolbar.button", value: "Toolbar Button", comment: "The name of the address bar button when referenced in settings.")

    public static let mobileCustomizationNoneOptionShort = NSLocalizedString("mobile.customization.option.none.short", value: "None", comment: "Indicates that no button was selected to be shown in the specified location.")

    public static let mobileCustomizationNoneOptionLong = NSLocalizedString("mobile.customization.option.none.long", value: "Hide This Button", comment: "A title to indicate that if selected the current button will be hidden from the UI")

    public static let mobileCustomizationShowReloadButtonToggleTitle = NSLocalizedString("mobile.customization.show.reload.button.title", value: "Show Reload Button", comment: "The label for the toggle that hides and shows the reload button.")

}
