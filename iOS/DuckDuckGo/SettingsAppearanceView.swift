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
                SettingsPickerCellView(label: UserText.settingsTheme,
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
        Section(header: Text(UserText.addressBar)) {
            addressBarPositionSetting()

            showFullSiteAddressSetting()

            showReloadButtonSetting()
        }

        Section(header: Text(verbatim: "Customizable Buttons")) {
            addressBarButtonSetting()

            toolbarButtonSetting()
        }
    }

    func buttonIconProvider(_ button: MobileCustomization.Button) -> Image? {
        return Image(uiImage: DesignSystemImages.Glyphs.Size16.favorite)
    }

    @ViewBuilder
    func addressBarButtonSetting() -> some View {

        SettingsPickerCellView(
            useImprovedPicker: true,
            label: "Address Bar button",
            options: MobileCustomization.addressBarButtons,
            selectedOption: $selectedAddressBarButton,
            iconProvider: buttonIconProvider)

    }

    @ViewBuilder
    func toolbarButtonSetting() -> some View {

        SettingsPickerCellView(
            useImprovedPicker: true,
            label: "Toolbar button",
            options: MobileCustomization.toolbarButtons,
            selectedOption: $selectedToolbarButton)

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
            SettingsPickerCellView(label: UserText.settingsRefreshButtonPositionTitle,
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
            SettingsPickerCellView(label: UserText.settingsAddressBar,
                                   options: AddressBarPosition.allCases,
                                   selectedOption: viewModel.addressBarPositionBinding)
        }
    }

}
