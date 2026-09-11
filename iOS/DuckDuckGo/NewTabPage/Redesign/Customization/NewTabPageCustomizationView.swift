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
    }

    @ObservedObject var model: NewTabPageCustomizationModel

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                sectionsSection
                keyboardSection
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

            NewTabPageCustomizationRow(title: UserText.newTabPageCustomizationMessages,
                                       image: DesignSystemImages.Glyphs.Size24.chat,
                                       control: .toggle($model.isMessagesSectionVisible))
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
                                       control: .button { model.onAllSettingsSelected?() })
        }
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
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let image {
                Image(uiImage: image)
                    .foregroundColor(Color(designSystemColor: .icons))
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

#Preview {
    NewTabPageCustomizationView(model: NewTabPageCustomizationModel(), onClose: {})
}
