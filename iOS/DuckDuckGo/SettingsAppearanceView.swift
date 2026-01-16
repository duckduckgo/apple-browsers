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

    @State var showAddressBarSettings = false
    @State var showToolbarSettings = false

    @State var deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection?

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

    func navigateToSubPageIfNeeded() {
        deepLinkTarget = viewModel.deepLinkTarget

        DispatchQueue.main.async {
            switch deepLinkTarget {
            case .customizeToolbarButton:
                showToolbarSettings = true
            case .customizeAddressBarButton:
                showAddressBarSettings = true
            default: break
            }
        }
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
                SettingsPickerCellView(label: UserText.settingsTheme,
                                       options: ThemeStyle.allCases,
                                       selectedOption: viewModel.themeStyleBinding)
            }

            // AddressBar specific settings
            Section {
                addressBarPositionSetting()

                showFullSiteAddressSetting()

                showReloadButtonSetting()

            } header: {
                Text(UserText.addressBar)
            }

            // Customizable buttons specific settings.
            if viewModel.mobileCustomization.isEnabled {
                Section {
                    addressBarButtonSetting()
                    toolbarButtonSetting()
                } header: {
                    Text(UserText.mobileCustomizationSectionTitle)
                }
                .onFirstAppear {
                    navigateToSubPageIfNeeded()
                }
            }

            if viewModel.browsingMenuSheetCapability.isSettingsOptionVisible {
                Section {
                    SettingsCellView(label: UserText.settingsExperimentalMenu,
                                     accessory: .toggle(isOn: viewModel.showMenuInSheetBinding))
                }
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
    func accessoryImage(_ image: UIImage) -> AnyView {
        AnyView(Image(uiImage: image).tint(
            Color(designSystemColor: .iconsSecondary)
        ))
    }

    @ViewBuilder
    func addressBarButtonSetting() -> some View {

        let destination = AddressBarCustomizationPickerView(isAIChatEnabled: viewModel.isAIChatEnabled,
                                                            selectedAddressBarButton: viewModel.selectedAddressBarButton,
                                                            mobileCustomization: viewModel.mobileCustomization)
            .applySettingsListModifiers(title: "", displayMode: .inline, viewModel: viewModel)

        NavigationLink(destination: destination, isActive: $showAddressBarSettings) {

            if let image = viewModel.selectedAddressBarButton.wrappedValue.smallIcon {
                SettingsCellView(label: UserText.mobileCustomizationAddressBarTitle, accessory: .custom(accessoryImage(image)))
            } else if viewModel.selectedAddressBarButton.wrappedValue == .none {
                SettingsCellView(label: UserText.mobileCustomizationAddressBarTitle, accessory: .rightDetail(UserText.mobileCustomizationNoneOptionShort))
            } else {
                FailedAssertionView("Unexpected state")
            }

        }
        .listRowBackground(Color(designSystemColor: .surface))

    }

    @ViewBuilder
    func toolbarButtonSetting() -> some View {
        let destination = ToolbarCustomizationPickerView(isAIChatEnabled: viewModel.isAIChatEnabled,
                                                         selectedToolbarButton: viewModel.selectedToolbarButton,
                                                         mobileCustomization: viewModel.mobileCustomization)
            .applySettingsListModifiers(title: "", displayMode: .inline, viewModel: viewModel)

        NavigationLink(destination: destination, isActive: $showToolbarSettings) {

            if let image = viewModel.selectedToolbarButton.wrappedValue.smallIcon {
                SettingsCellView(label: UserText.mobileCustomizationToolbarTitle, accessory: .custom(accessoryImage(image)))
            } else {
                FailedAssertionView("Expected image for selection")
                SettingsCellView(label: UserText.mobileCustomizationToolbarTitle, accessory: .rightDetail(UserText.mobileCustomizationNoneOptionShort))
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))

    }

    @ViewBuilder
    func showReloadButtonSetting() -> some View {
        SettingsCellView(label: UserText.mobileCustomizationShowReloadButtonToggleTitle,
                         accessory: .toggle(isOn: showReloadButton))
    }

    @ViewBuilder
    func showFullSiteAddressSetting() -> some View {
        SettingsCellView(label: UserText.settingsFullURL,
                         accessory: .toggle(isOn: viewModel.addressBarShowsFullURL))
    }

    @ViewBuilder
    func addressBarPositionSetting() -> some View {
        if viewModel.state.addressBar.enabled {
            SettingsPickerCellView(label: UserText.settingsAddressBarPosition,
                                   options: AddressBarPosition.allCases,
                                   selectedOption: viewModel.addressBarPositionBinding)
        }
    }

}
