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
                SettingsPickerCellView(useImprovedPicker: viewModel.useImprovedPicker,
                                       label: UserText.settingsTheme,
                                       options: ThemeStyle.allCases,
                                       selectedOption: viewModel.themeStyleBinding)
            }


            if viewModel.state.mobileCustomization.isEnabled {
                customizableSettings()
                    .onFirstAppear {
                        navigateToSubPageIfNeeded()
                    }
            } else {
                legacySettings()
            }

            if viewModel.browsingMenuSheetCapability.isAvailable {
                Section {
                    SettingsCellView(label: "Sheet menu presentation",
                                     accessory: .toggle(isOn: viewModel.showMenuInSheetBinding))

                    if viewModel.isInternalUser {
                        SettingsPickerCellView(useImprovedPicker: viewModel.useImprovedPicker,
                                               label: "Menu variant",
                                               options: BrowsingMenuClusteringVariant.allCases,
                                               selectedOption: viewModel.sheetBrowsingMenuVariantBinding)
                    }
                } footer: {
                    if viewModel.isInternalUser {
                        Text(verbatim: "This setting is experimental and available only for internal users")
                    }
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
    func customizableSettings() -> some View {
        Section {
            addressBarPositionSetting()

            showFullSiteAddressSetting()

            showReloadButtonSetting()

        } header: {
            Text(UserText.addressBar)
        }

        Section {
            addressBarButtonSetting()
            toolbarButtonSetting()
        } header: {
            Text(UserText.mobileCustomizationSectionTitle)
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
                                   label: UserText.settingsAddressBarPosition,
                                   options: AddressBarPosition.allCases,
                                   selectedOption: viewModel.addressBarPositionBinding)
        }
    }

}
