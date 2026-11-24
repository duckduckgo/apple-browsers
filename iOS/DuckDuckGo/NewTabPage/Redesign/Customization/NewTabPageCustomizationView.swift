//
//  NewTabPageCustomizationView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

struct NewTabPageCustomizationView: View {

    private enum Metrics {
        static let contentInset: CGFloat = 16
        static let headerMinHeight: CGFloat = 56
        static let headerTopPadding: CGFloat = 16
        static let closeButtonIconPadding: CGFloat = 4
        static let themeTileSpacing: CGFloat = 12
        static let themeRowInset: CGFloat = 8
    }

    @ObservedObject var model: NewTabPageCustomizationModel

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                sectionsSection
                keyboardSection
                if model.isIdleReturnSettingsVisible {
                    afterInactivitySection
                }
                themeSection
                allSettingsSection
            }
            .compactSectionSpacingIfAvailable()
            .applyInsetGroupedListStyle()
        }
        .background(Color(designSystemColor: .background))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            closeButton
                .hidden()

            Text(UserText.newTabPageCustomizationTitle)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            closeButton
        }
        .padding(.horizontal, Metrics.contentInset - CloseButtonStyle.Constant.padding)
        .padding(.top, Metrics.headerTopPadding)
        .frame(minHeight: Metrics.headerMinHeight)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                .padding(Metrics.closeButtonIconPadding)
        }
        .buttonStyle(CloseButtonStyle())
        .fixedSize()
        .accessibilityLabel(UserText.keyCommandClose)
    }

    private var sectionsSection: some View {
        Section {
            NewTabPageCustomizationRow(title: UserText.sectionTitleFavorites,
                                       image: DesignSystemImages.Glyphs.Size24.bookmarkFavorite,
                                       control: .toggle($model.isFavoritesSectionVisible))
            if model.isIdleReturnSettingsVisible {
                NewTabPageCustomizationRow(title: UserText.settingsReturnToShortcutLabel,
                                           image: DesignSystemImages.Glyphs.Size16.returnTo,
                                           control: .toggle($model.isReturnToLastTabEnabled))
            }
        }
    }

    private var afterInactivitySection: some View {
        Section(footer: Text(model.afterInactivityFooterText)) {
            SettingsPickerCellView(label: UserText.settingsAfterInactivityLabel,
                                   options: AfterInactivityOption.allCases,
                                   selectedOption: $model.afterInactivityOption)

            if model.afterInactivityOption == .newTab {
                SettingsPickerCellView(label: UserText.settingsAfterInactivityIntervalLabel,
                                       options: AfterInactivityIdleInterval.allCases,
                                       selectedOption: $model.afterInactivityIdleInterval)
            }
        }
    }

    private var themeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.themeTileSpacing) {
                    ForEach(NewTabPageTheme.allCases, id: \.self) { theme in
                        NewTabPageThemeTile(theme: theme, isSelected: model.theme == theme) {
                            model.theme = theme
                        }
                    }
                }
                .padding(Metrics.themeRowInset)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var keyboardSection: some View {
        Section {
            NewTabPageCustomizationRow(title: UserText.newTabPageCustomizationAlwaysShowKeyboard,
                                       control: .toggle($model.isKeyboardShownOnNewTab))
        }
    }

    private var allSettingsSection: some View {
        Section {
            NewTabPageCustomizationRow(title: UserText.newTabPageCustomizationAllSettings,
                                       image: DesignSystemImages.Glyphs.Size24.settings,
                                       control: .button { model.selectAllSettings() })
        }
    }
}

private struct NewTabPageThemeTile: View {

    private enum Metrics {
        static let tileSize = CGSize(width: 96, height: 160)
        static let cornerRadius: CGFloat = 8
        static let selectionBorderWidth: CGFloat = 3
        static let selectionBorderGap: CGFloat = 3
    }

    let theme: NewTabPageTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(uiImage: theme.tileImage)
                .resizable()
                .frame(width: Metrics.tileSize.width, height: Metrics.tileSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius))
                .padding(Metrics.selectionBorderGap + Metrics.selectionBorderWidth)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius + Metrics.selectionBorderGap + Metrics.selectionBorderWidth)
                        .strokeBorder(Color(designSystemColor: .accentPrimary), lineWidth: Metrics.selectionBorderWidth)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NewTabPageCustomizationRow: View {

    enum Control {
        case toggle(Binding<Bool>)
        case button(() -> Void)
    }

    let title: String
    var image: UIImage?
    let control: Control

    var body: some View {
        Group {
            switch control {
            case .toggle(let isOn):
                Toggle(isOn: isOn) {
                    label
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accentPrimary)))
            case .button(let action):
                Button(action: action) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        label
                        Spacer(minLength: 8)
                        Image(uiImage: DesignSystemImages.Glyphs.Size16.openIn)
                            .foregroundColor(Color(designSystemColor: .iconsSecondary))
                            .alignmentGuide(.firstTextBaseline, computeValue: iconBaseline)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listRowBackground(Color(designSystemColor: .surfaceTertiary))
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let image {
                Image(uiImage: image)
                    .foregroundColor(Color(designSystemColor: .icons))
                    .frame(width: 24)
                    .alignmentGuide(.firstTextBaseline, computeValue: iconBaseline)
                    .accessibilityHidden(true)
            }
            Text(title)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconBaseline(_ dimensions: ViewDimensions) -> CGFloat {
        // Center each glyph on the first line's capital letters as text size changes.
        dimensions[VerticalAlignment.center] + UIFont.daxBodyRegular().capHeight / 2
    }
}
