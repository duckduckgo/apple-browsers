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

        // This just needs to be longer than the deep link logic in the View Model which uses a timer 🙄
        //  otherwise this immediately gets popped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
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
        if button == .none {
            return Image(uiImage: DesignSystemImages.Glyphs.Size16.eyeClosed)
        }
        guard let icon = button.smallIcon else { return nil }
        return Image(uiImage: icon)
    }

    func descriptionForOption(_ button: MobileCustomization.Button) -> String {
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
            viewModel.isAIChatEnabled ? UserText.settingsAutoClearTabsAndDataWithAIChat :  UserText.settingsAutoClearTabsAndData
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

    @ViewBuilder
    func addressBarButtonSetting() -> some View {

        let options = MobileCustomization.addressBarButtons.sorted(by: descriptionComparison)

        NavigationLink(destination: PickerWithHeaderView(
            title: "Address Bar Button",
            headerImage: Image(.customAddressBarButtonPreview),
            options: options,
            defaultOption: MobileCustomization.addressBarDefault,
            selectedOption: viewModel.selectedAddressBarButton,
            descriptionForOption: descriptionForOption,
            iconProvider: buttonIconProvider)

            .applySettingsListModifiers(title: UserText.settingsAppearanceSection,
                                                 displayMode: .inline,
                                                 viewModel: viewModel)

                       , isActive: $showAddressBarSettings) {

            if let image = viewModel.selectedAddressBarButton.wrappedValue.smallIcon {
                SettingsCellView(label: "Address Bar", accessory: .image(Image(uiImage: image)))
            } else if viewModel.selectedAddressBarButton.wrappedValue == .none {
                SettingsCellView(label: "Address Bar", accessory: .rightDetail("None"))
            } else {
                FailedAssertionView("Unexpected state")
            }

        }
        .listRowBackground(Color(designSystemColor: .surface))

    }

    @ViewBuilder
    func toolbarButtonSetting() -> some View {

        let options = MobileCustomization.toolbarButtons.sorted(by: descriptionComparison)
        NavigationLink(destination: PickerWithHeaderView(
            title: "Toolbar Button",
            headerImage: Image(.customToolbarButtonPreview),
            options: options,
            defaultOption: MobileCustomization.toolbarDefault,
            selectedOption: viewModel.selectedToolbarButton,
            descriptionForOption: descriptionForOption,
            iconProvider: buttonIconProvider)

            .applySettingsListModifiers(title: UserText.settingsAppearanceSection,
                                                 displayMode: .inline,
                                                 viewModel: viewModel)

                       , isActive: $showToolbarSettings) {

            if let image = viewModel.selectedToolbarButton.wrappedValue.smallIcon {
                SettingsCellView(label: "Toolbar", accessory: .image(Image(uiImage: image)))
            } else {
                FailedAssertionView("Expected image for selection")
                SettingsCellView(label: "Toolbar", accessory: .rightDetail("None"))
            }
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

    func descriptionComparison(lhs: MobileCustomization.Button, rhs: MobileCustomization.Button) -> Bool {
        if lhs == .none { return false } // Always put none at the end
        return descriptionForOption(lhs).localizedCaseInsensitiveCompare(descriptionForOption(rhs)) == .orderedAscending
    }

}

private struct PickerWithHeaderView<T: Hashable>: View {

    let title: String
    let headerImage: Image
    let options: [T]
    let defaultOption: T
    @Binding var selectedOption: T
    let descriptionForOption: (T) -> String
    let iconProvider: ((T) -> Image?)?

    init(title: String,
         headerImage: Image,
         options: [T],
         defaultOption: T,
         selectedOption: Binding<T>,
         descriptionForOption: @escaping (T) -> String,
         iconProvider: ((T) -> Image?)?) {
        self.title = title
        self.headerImage = headerImage
        self.options = options
        self.defaultOption = defaultOption
        self._selectedOption = selectedOption
        self.iconProvider = iconProvider
        self.descriptionForOption = descriptionForOption
    }

    var body: some View {
        List(selection: Binding<T?>(get: {
            nil
        }, set: {
            selectedOption = $0 ?? options[0]
        })) {
            Section {
                HStack {
                    Spacer()
                    headerImage
                    Spacer()
                }
                .listRowBackground(Color(designSystemColor: .surface))

                ForEach(options, id: \.self) { option in
                    HStack {
                        iconProvider?(option)

                        Text(verbatim: descriptionForOption(option))
                            .lineLimit(2)
                            .layoutPriority(1)

                        if selectedOption == option {
                            Spacer()
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSmall)
                                .foregroundStyle(Color(designSystemColor: .accent))
                        } else {
                            Spacer(minLength: 24)
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                }
                .navigationTitle(Text(title))
            }
        }
    }

}
