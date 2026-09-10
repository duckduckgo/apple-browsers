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
        static let headerHeight: CGFloat = 68
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
            .applyInsetGroupedListStyle()
        }
        .background(Color(designSystemColor: .background))
    }

    private var header: some View {
        ZStack {
            Text(UserText.newTabPageCustomizationTitle)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                        .padding(Metrics.closeButtonIconPadding)
                }
                .buttonStyle(CloseButtonStyle())
                .accessibilityLabel(UserText.keyCommandClose)
            }
            .padding(.horizontal, Metrics.contentInset - CloseButtonStyle.Constant.padding)
        }
        .frame(height: Metrics.headerHeight)
    }

    private var sectionsSection: some View {
        Section {
            SettingsCellView(label: UserText.sectionTitleFavorites,
                             image: Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmarkFavorite),
                             accessory: .toggle(isOn: $model.isFavoritesSectionVisible))

            SettingsCellView(label: UserText.newTabPageCustomizationMessages,
                             image: Image(uiImage: DesignSystemImages.Glyphs.Size24.chat),
                             accessory: .toggle(isOn: $model.isMessagesSectionVisible))
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }

    private var keyboardSection: some View {
        Section {
            SettingsCellView(label: UserText.newTabPageCustomizationAlwaysShowKeyboard,
                             accessory: .toggle(isOn: $model.isKeyboardShownOnNewTab))
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }

    private var allSettingsSection: some View {
        Section {
            SettingsCellView(label: UserText.newTabPageCustomizationAllSettings,
                             image: Image(uiImage: DesignSystemImages.Glyphs.Size24.settings),
                             action: { model.onAllSettingsSelected?() },
                             webLinkIndicator: true,
                             isButton: true)
        }
        .listRowBackground(Color(singleUseColor: .groupedListContentBackground))
    }
}

#Preview {
    NewTabPageCustomizationView(model: NewTabPageCustomizationModel(), onClose: {})
}
