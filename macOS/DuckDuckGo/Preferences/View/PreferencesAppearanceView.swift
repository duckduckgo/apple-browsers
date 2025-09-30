//
//  PreferencesAppearanceView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Bookmarks
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit

extension Preferences {

    // MARK: - Legacy: Superseded by `ThemeAppearanceViewV2`
    //
    struct ThemeAppearanceButton: View {
        let title: String
        let imageName: String
        @Binding var isSelected: Bool

        var body: some View {
            VStack {
                Button(action: { isSelected.toggle() }) {
                    VStack(spacing: 2) {
                        Image(imageName)
                            .padding(2)
                            .background(selectionBackground)
                        Text(title)
                    }
                }
                .padding(.horizontal, 2)
                .buttonStyle(.plain)
            }
        }

        @ViewBuilder
        private var selectionBackground: some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.linkBlue), lineWidth: 2)
            }
        }

    }

    // MARK: - Legacy: Superseded by `ThemeAppearancePickerV2`
    //
    struct ThemeAppearancePicker: View {
        @EnvironmentObject var model: AppearancePreferences

        var body: some View {
            HStack(spacing: 24) {
                ForEach(ThemeAppearance.allCases, id: \.self) { theme in
                    ThemeAppearanceButton(
                        title: theme.displayName,
                        imageName: theme.imageName,
                        isSelected: isThemeSelected(theme)
                    )
                }
            }
        }

        private func isThemeSelected(_ theme: ThemeAppearance) -> Binding<Bool> {
            .init(
                get: {
                    model.themeAppearance == theme
                },
                set: { isSelected in
                    if isSelected {
                        model.themeAppearance = theme
                    }
                }
            )
        }
    }

    // MARK: - Appearance View (Light / Dark / System)
    //
    struct ThemeAppearanceViewV2: View {
        var appearance: ThemeAppearance

        var body: some View {
            HStack(spacing: 6) {
                Image(systemNamed: appearance.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Text(appearance.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }
            .frame(width: 139, height: 32)
        }
    }

    // MARK: - Picker: Appearance (Light / Dark / System)
    //
    struct ThemeAppearancePickerV2: View {
        @EnvironmentObject var model: AppearancePreferences

        var body: some View {
            SlidingPickerView(settings: .appearancePickerSettings, allValues: ThemeAppearance.allCases, selectedValue: $model.themeAppearance) { appearance in
                AnyView(
                    ThemeAppearanceViewV2(appearance: appearance)
                )
            }
            .frame(height: 32)
        }
    }

    struct AppearanceView: View {
        @ObservedObject var model: AppearancePreferences
        @ObservedObject var aiChatModel: AIChatPreferences
        var isThemeSwitcherEnabled: Bool = false

        var body: some View {
            PreferencePane(UserText.appearance) {

                // SECTION 1: Theme
                PreferencePaneSection(UserText.theme) {

                    if isThemeSwitcherEnabled {
                        ThemeAppearancePickerV2()
                            .environmentObject(model)

                    } else {
                        ThemeAppearancePicker()
                            .environmentObject(model)
                    }
                }

                // SECTION 2: Address Bar
                PreferencePaneSection(UserText.addressBar) {
                    ToggleMenuItem(UserText.showFullWebsiteAddress, isOn: $model.showFullURL)
                }

                // SECTION 3: New Tab Page
                PreferencePaneSection(UserText.newTabBottomPopoverTitle) {

                    PreferencePaneSubSection {
                        if model.isOmnibarAvailable {
                            ToggleMenuItem(UserText.newTabOmnibarSectionTitle, isOn: $model.isOmnibarVisible)
                                .accessibilityIdentifier("Preferences.AppearanceView.showOmnibarToggle")
                            ToggleMenuItem(UserText.newTabAIChatSectionTitle, isOn: $aiChatModel.showShortcutOnNewTabPage)
                                .accessibilityIdentifier("Preferences.AppearanceView.showAIChatToggle")
                                .padding(.leading, 19)
                                .disabled(!model.isOmnibarVisible)
                                .visibility(aiChatModel.isAIFeaturesEnabled ? .visible : .gone)
                        }
                        ToggleMenuItem(UserText.newTabFavoriteSectionTitle, isOn: $model.isFavoriteVisible).accessibilityIdentifier("Preferences.AppearanceView.showFavoritesToggle")
                        ToggleMenuItem(UserText.newTabProtectionsReportSectionTitle, isOn: $model.isProtectionsReportVisible)
                    }

                    PreferencePaneSubSection {

                        Button {
                            model.openNewTabPageBackgroundCustomizationSettings()
                        } label: {
                            HStack {
                                Text(UserText.customizeBackground)
                                Image(.externalAppScheme)
                            }
                            .foregroundColor(Color.linkBlue)
                            .cursor(.pointingHand)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // SECTION 4: Bookmarks Bar
                PreferencePaneSection(UserText.showBookmarksBar) {
                    HStack {
                        ToggleMenuItem(UserText.showBookmarksBarPreference, isOn: $model.showBookmarksBar)
                            .accessibilityIdentifier("Preferences.AppearanceView.showBookmarksBarPreferenceToggle")
                        NSPopUpButtonView(selection: $model.bookmarksBarAppearance) {
                            let button = NSPopUpButton()
                            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                            button.setAccessibilityIdentifier("Preferences.AppearanceView.showBookmarksBarPopUp")

                            let alwaysOn = button.menu?.addItem(withTitle: UserText.showBookmarksBarAlways, action: nil, keyEquivalent: "")
                            alwaysOn?.representedObject = BookmarksBarAppearance.alwaysOn
                            alwaysOn?.setAccessibilityIdentifier("Preferences.AppearanceView.showBookmarksBarAlways")

                            let newTabOnly = button.menu?.addItem(withTitle: UserText.showBookmarksBarNewTabOnly, action: nil, keyEquivalent: "")
                            newTabOnly?.representedObject = BookmarksBarAppearance.newTabOnly
                            newTabOnly?.setAccessibilityIdentifier("Preferences.AppearanceView.showBookmarksBarNewTabOnly")

                            return button
                        }
                        .disabled(!model.showBookmarksBar)
                    }

                    HStack {
                        Text(UserText.preferencesBookmarksCenterAlignBookmarksBarTitle)
                        NSPopUpButtonView(selection: $model.centerAlignedBookmarksBarBool) {
                            let button = NSPopUpButton()
                            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

                            let leftAligned = button.menu?.addItem(withTitle: UserText.preferencesBookmarksLeftAlignBookmarksBare, action: nil, keyEquivalent: "")
                            leftAligned?.representedObject = false

                            let centerAligned = button.menu?.addItem(withTitle: UserText.preferencesBookmarksCenterAlignBookmarksBar, action: nil, keyEquivalent: "")
                            centerAligned?.representedObject = true

                            return button
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ThemeAppearance Helpers
//
private extension ThemeAppearance {

    var icon: Image.SystemImageName {
        switch self {
        case .light:
            .sunMax
        case .dark:
            .moon
        case .systemDefault:
            .circleLeftHalfFilled
        }
    }
}

// MARK: - SlidingPickerSettings Helpers
//
private extension SlidingPickerSettings {

    static var appearancePickerSettings: SlidingPickerSettings {
        SlidingPickerSettings(
            backgroundColor: Color(designSystemColor: .surfacePrimary),
            borderColor: Color(designSystemColor: .containerDecorationSecondary),
            selectionBackgroundColor: Color(designSystemColor: .surfaceTertiary),
            selectionBorderColor: Color(designSystemColor: .containerDecorationSecondary),
            dividerSize: CGSize(width: 1, height: 16))
    }
}
