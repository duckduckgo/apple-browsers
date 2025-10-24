//
//  SettingsAppearanceView.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Core
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct SettingsAppearanceView: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    @State var selectedToolbarButton: MobileCustomization.Button = MobileCustomization.toolbarButtons[0]
    @State var selectedAddressBarButton: MobileCustomization.Button = MobileCustomization.addressBarButtons[0]!
    @State var showReloadButton: Bool = true

    var body: some View {
        List {
            Section {
                // App Icon
                let image = Image(uiImage: viewModel.state.appIcon.smallImage)
                SettingsCellView(label: UserText.settingsIcon,
                                 action: { viewModel.presentLegacyView(.appIcon ) },
                                 accessory: .image(image),
                                 disclosureIndicator: true,
                                 isButton: true)

                // Theme
                SettingsPickerCellView(useImprovedPicker: viewModel.useImprovedPicker,
                                       label: UserText.settingsTheme,
                                       options: ThemeStyle.allCases,
                                       selectedOption: viewModel.themeStyleBinding)
            }


            if viewModel.state.mobileCustomization.isEnabled {
                customizableSettings()
            } else {
                legacySettings()
            }

        }
        .applySettingsListModifiers(title: UserText.settingsAppearanceSection,
                                    displayMode: .inline,
                                    viewModel: viewModel)
        .onFirstAppear {
            Pixel.fire(pixel: .settingsAppearanceOpen)
        }
    }

    @ViewBuilder
    func customizableSettings() -> some View {
        Section {
            addressBarPositionSetting()

            showFullSiteAddressSetting()

            showReloadButtonSetting()

            addressBarButtonSetting()
        } header: {
            Text(UserText.addressBar)
        } footer: {
            Text(verbatim: "Note that the reload button and customizable button are none-functional at this time.")
        }

        Section {
            toolbarButtonSetting()
        } header: {
            Text(verbatim: "Toolbar")
        } footer: {
            Text(verbatim: "Note that customizable button is none-functional at this time.")
        }
    }

    func buttonIconProvider(_ button: MobileCustomization.Button) -> Image? {

        let image: UIImage? =
        switch button {
        case .share:
            DesignSystemImages.Glyphs.Size16.shareApple
        case .addRemoveBookmark:
            DesignSystemImages.Glyphs.Size16.bookmark
        case .addRemoveFavorite:
            DesignSystemImages.Glyphs.Size16.favorite
        case .zoom:
            DesignSystemImages.Glyphs.Size16.typeSize
        case .none:
            nil
        case .home:
            DesignSystemImages.Glyphs.Size16.home
        case .newTab:
            DesignSystemImages.Glyphs.Size16.add
        case .bookmarks:
            DesignSystemImages.Glyphs.Size16.bookmarks
        case .duckAi:
            DesignSystemImages.Glyphs.Size16.aiChat
        case .fire:
            DesignSystemImages.Glyphs.Size16.fire
        case .vpn:
            DesignSystemImages.Glyphs.Size16.vpnOn
        case .passwords:
            DesignSystemImages.Glyphs.Size16.keyLogin
        case .voiceSearch:
            DesignSystemImages.Glyphs.Size16.microphone
        }

        if let image {
            return Image(uiImage: image)
        }

        return nil
    }

    @ViewBuilder
    func addressBarButtonSetting() -> some View {

        SettingsPickerCellView(
            useImprovedPicker: true,
            label: "Customizable Button",
            options: MobileCustomization.addressBarButtons,
            selectedOption: $selectedAddressBarButton,
            iconProvider: buttonIconProvider)

    }

    @ViewBuilder
    func toolbarButtonSetting() -> some View {

        SettingsPickerCellView(
            
            useImprovedPicker: true,
            label: "Customizable Button",
            options: MobileCustomization.toolbarButtons,
            selectedOption: $selectedToolbarButton,
            iconProvider: buttonIconProvider)

    }

    @ViewBuilder
    func showReloadButtonSetting() -> some View {
        SettingsCellView(label: "Show Reload Button",
                         accessory: .toggle(isOn: $showReloadButton))
    }

    @ViewBuilder
    func legacySettings() -> some View {
        Section(header: Text(UserText.addressBar)) {
            addressBarPositionSetting()

            // Refresh Button Position
            SettingsPickerCellView(useImprovedPicker: viewModel.useImprovedPicker,
                                   label: UserText.settingsRefreshButtonPositionTitle,
                                   options: RefreshButtonPosition.allCases,
                                   selectedOption: viewModel.refreshButtonPositionBinding)

            showFullSiteAddressSetting()
        }
    }

    @ViewBuilder
    func showFullSiteAddressSetting() -> some View {
        SettingsCellView(label: UserText.settingsFullURL,
                         accessory: .toggle(isOn: viewModel.addressBarShowsFullURL))
    }

    @ViewBuilder
    func addressBarPositionSetting() -> some View {
        if viewModel.state.addressBar.enabled {
            SettingsPickerCellView(useImprovedPicker: viewModel.useImprovedPicker,
                                   label: UserText.settingsAddressBar,
                                   options: AddressBarPosition.allCases,
                                   selectedOption: viewModel.addressBarPositionBinding)
        }
    }

}
