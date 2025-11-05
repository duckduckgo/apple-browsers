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

    /// Once the feature is rolled out move this to view model
    var showReloadButton: Binding<Bool> {
        Binding<Bool>(
            get: {
                viewModel.refreshButtonPositionBinding.wrappedValue == .addressBar
            },
            set: {
                viewModel.refreshButtonPositionBinding.wrappedValue = $0 ? .addressBar : .menu
            }
        )
    }

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

        } header: {
            Text(UserText.addressBar)
        } footer: {
            Text(verbatim: "Note: Reload button should work as expected. Address button state is persisted but NOT applied to the UI.")
        }

        Section {
            addressBarButtonSetting()
            toolbarButtonSetting()
        } header: {
            Text(verbatim: "Customizable Buttons")
        }
    }

    func buttonIconProvider(_ button: MobileCustomization.Button) -> Image? {
        guard let icon = button.smallIcon else { return nil }
        return Image(uiImage: icon)
    }

    @ViewBuilder
    func addressBarButtonSetting() -> some View {

        NavigationLink(destination: PickerWithHeaderView(
            title: "Address Bar Button",
            headerImage: Image(.customAddressBarButtonPreview),
            options: MobileCustomization.addressBarButtons,
            defaultOption: MobileCustomization.addressBarDefault,
            selectedOption: viewModel.selectedAddressBarButton,
            iconProvider: buttonIconProvider)) {

            SettingsCellView(label: "Address Bar",
                             accessory: .rightDetail(viewModel.selectedAddressBarButton.wrappedValue.description))
        }
        .listRowBackground(Color(designSystemColor: .surface))

    }

    @ViewBuilder
    func toolbarButtonSetting() -> some View {

        NavigationLink(destination: PickerWithHeaderView(
            title: "Toolbar Button",
            headerImage: Image(.customToolbarButtonPreview),
            options: MobileCustomization.toolbarButtons,
            defaultOption: MobileCustomization.toolbarDefault,
            selectedOption: viewModel.selectedToolbarButton,
            iconProvider: buttonIconProvider)) {

            SettingsCellView(label: "Toolbar",
                             accessory: .rightDetail(viewModel.selectedToolbarButton.wrappedValue.description))
        }
        .listRowBackground(Color(designSystemColor: .surface))

    }

    @ViewBuilder
    func showReloadButtonSetting() -> some View {
        SettingsCellView(label: "Show Reload Button",
                         accessory: .toggle(isOn: showReloadButton))
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

private struct PickerWithHeaderView<T: Hashable & CustomStringConvertible>: View {

    let title: String
    let headerImage: Image
    let options: [T]
    let defaultOption: T
    @Binding var selectedOption: T
    let iconProvider: ((T) -> Image?)?

    init(title: String, headerImage: Image, options: [T], defaultOption: T, selectedOption: Binding<T>, iconProvider: ((T) -> Image?)?) {
        self.title = title
        self.headerImage = headerImage
        self.options = options
        self.defaultOption = defaultOption
        self._selectedOption = selectedOption
        self.iconProvider = iconProvider
    }

    var body: some View {
        List(selection: Binding<T?>(get: {
            nil
        }, set: {
            selectedOption = $0 ?? options[0]
        })) {
            Section {
                ForEach(options, id: \.self) { option in
                    HStack {
                        iconProvider?(option)
                        Text(option.description)
                        if selectedOption == option {
                            Spacer()
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSmall)
                                .foregroundStyle(Color(designSystemColor: .accent))
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                }
                .navigationTitle(Text(title))
            } header: {
                HStack {
                    Spacer()
                    headerImage
                    Spacer()
                }
            }
        }
    }

}

