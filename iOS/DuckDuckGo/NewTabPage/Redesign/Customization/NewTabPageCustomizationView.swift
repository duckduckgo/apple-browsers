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
        static let groupSpacing: CGFloat = 24
        static let groupCornerRadius: CGFloat = 12
        static let rowHeight: CGFloat = 52
        static let rowSpacing: CGFloat = 12
        static let headerHeight: CGFloat = 68
        static let closeButtonIconPadding: CGFloat = 4
    }

    @ObservedObject var model: NewTabPageCustomizationModel

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Metrics.groupSpacing) {
                    sectionsGroup
                    keyboardGroup
                    allSettingsGroup
                }
                .padding(.horizontal, Metrics.contentInset)
                .padding(.bottom, Metrics.groupSpacing)
            }
        }
        .background(Color(designSystemColor: .backgroundSheets))
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

    private var sectionsGroup: some View {
        group {
            toggleRow(icon: DesignSystemImages.Glyphs.Size24.bookmarkFavorite,
                      title: UserText.sectionTitleFavorites,
                      isOn: $model.isFavoritesSectionVisible)

            Divider().padding(.leading, Metrics.contentInset)

            toggleRow(icon: DesignSystemImages.Glyphs.Size24.chat,
                      title: UserText.newTabPageCustomizationMessages,
                      isOn: $model.isMessagesSectionVisible)
        }
    }

    private var keyboardGroup: some View {
        group {
            toggleRow(icon: nil,
                      title: UserText.newTabPageCustomizationAlwaysShowKeyboard,
                      isOn: $model.isKeyboardShownOnNewTab)
        }
    }

    private var allSettingsGroup: some View {
        group {
            Button {
                model.onAllSettingsSelected?()
            } label: {
                HStack(spacing: Metrics.rowSpacing) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.settings)
                        .foregroundColor(Color(designSystemColor: .icons))

                    Text(UserText.newTabPageCustomizationAllSettings)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))

                    Spacer()

                    Image(uiImage: DesignSystemImages.Glyphs.Size24.openIn)
                        .foregroundColor(Color(designSystemColor: .iconsSecondary))
                }
                .padding(.horizontal, Metrics.contentInset)
                .frame(height: Metrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRow(icon: UIImage?, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Metrics.rowSpacing) {
            if let icon {
                Image(uiImage: icon)
                    .foregroundColor(Color(designSystemColor: .icons))
            }

            Toggle(isOn: isOn) {
                Text(title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accentPrimary)))
        }
        .padding(.horizontal, Metrics.contentInset)
        .frame(height: Metrics.rowHeight)
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: Metrics.groupCornerRadius)
                .fill(Color(designSystemColor: .surface))
        )
    }
}

#Preview {
    NewTabPageCustomizationView(model: NewTabPageCustomizationModel(), onClose: {})
}
