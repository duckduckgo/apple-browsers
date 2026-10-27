//
//  PreferencesExtensionsManagementView.swift
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
import PreferencesUI_macOS
import RemoteMessaging
import SwiftUI
import SwiftUIExtensions
import WebExtensions

extension Preferences {

    @available(macOS 15.4, *)
    struct ExtensionsManagementView: View {

        private enum Const {
            static let footerSpacing: CGFloat = 4
            static let dividerTopPadding: CGFloat = 32
            static let dividerBottomPadding: CGFloat = 28
            static let moreExtensionsBottomPadding: CGFloat = 48
        }

        @ObservedObject var model: ExtensionsManagementPreferences

        @Environment(\.designSystemPalette) private var palette

        var body: some View {
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: Const.footerSpacing) {
                    content
                    disclaimer
                }
                VStack(alignment: .leading, spacing: Const.footerSpacing) {
                    ScrollView(.vertical) {
                        content
                    }
                    disclaimer
                }
            }
            .containerRelativeFrame(.vertical, alignment: .top) { length, _ in
                length - 2 * Preferences.Const.panePaddingVertical
            }
        }

        private var content: some View {
            PreferencePane(UserText.extensionsSettingsTitle, spacing: 4) {

                PreferencePaneSection {
                    description
                }

                VStack(alignment: .leading, spacing: 0) {
                    if !model.installedExtensions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle(UserText.extensionsSettingsAddedHeader)
                            ForEach(model.installedExtensions) { item in
                                ExtensionsManagementRow(item: item, imageLoader: model.imageLoader, onGet: nil)
                            }
                        }

                        // Only needed to tell the uninstalled extensions apart from the Added ones.
                        if !model.uninstalledPasswordManagers.isEmpty {
                            Divider()
                                .padding(.top, Const.dividerTopPadding)
                                .padding(.bottom, Const.dividerBottomPadding)
                            sectionTitle(UserText.extensionsSettingsMoreExtensionsHeader)
                                .padding(.bottom, Const.moreExtensionsBottomPadding)
                        }
                    }

                    if !model.uninstalledPasswordManagers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            TextMenuItemHeader(UserText.extensionsSettingsPasswordManagersHeader)
                            ForEach(model.uninstalledPasswordManagers) { item in
                                ExtensionsManagementRow(item: item, imageLoader: model.imageLoader) {
                                    model.openStorePage(for: item)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
        }

        private func sectionTitle(_ title: String) -> some View {
            Text(title)
                .font(.callout)
                .foregroundColor(Color(designSystemColor: .textTertiary, palette: palette))
        }

        private var description: some View {
            TextMenuItemCaption(
                String(format: UserText.extensionsSettingsDescription,
                       "[\(UserText.extensionsSettingsLearnMore)](\(URL.settingsPane(.extensions)))")
            )
            .tint(Color.rebrandableLink(palette: palette))
            .environment(\.openURL, OpenURLAction { _ in
                // Placeholder until the Learn more page exists.
                .handled
            })
        }

        private var disclaimer: some View {
            VStack(alignment: .leading, spacing: 16) {
                Divider()
                Text(UserText.extensionsSettingsDisclaimer)
                    .font(PreferencesUI_macOS.Const.Fonts.preferencePaneDisclaimer)
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                    .fixMultilineScrollableText()
            }
        }
    }

    private struct ExtensionsManagementRow: View {

        private enum Const {
            /// Narrower windows shrink the box, truncating its text, rather than overflowing the pane.
            static let maxWidth: CGFloat = 560
            static let height: CGFloat = 120
            static let cornerRadius: CGFloat = 16
            static let padding: CGFloat = 24
            static let iconTileSize: CGFloat = 72
            static let iconTileCornerRadius: CGFloat = 12
            static let iconSize: CGFloat = 40
            static let buttonHorizontalPadding: CGFloat = 8
            /// Minimum label size, so the button measures at least 80 x 24pt once padded.
            static let buttonLabelMinWidth: CGFloat = 80 - 2 * buttonHorizontalPadding
            static let buttonMinHeight: CGFloat = 24
            static let buttonCornerRadius: CGFloat = 8
        }

        let item: ChromeWebStoreListing
        let imageLoader: RemoteMessagingImageLoading
        /// `nil` hides the Get button, as for installed extensions.
        let onGet: (() -> Void)?

        @Environment(\.designSystemPalette) private var palette
        @State private var remoteIcon: NSImage?

        /// Downloaded, else cached; `nil` leaves the gray tile empty.
        private var icon: NSImage? {
            remoteIcon ?? item.iconURL.flatMap(imageLoader.cachedImage(for:))
        }

        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Const.iconSize, height: Const.iconSize)
                    }
                }
                .frame(width: Const.iconTileSize, height: Const.iconTileSize)
                .background(Color(designSystemColor: .containerFillTertiary, palette: palette))
                .clipShape(RoundedRectangle(cornerRadius: Const.iconTileCornerRadius, style: .continuous))
                .task(id: item.iconURL) {
                    guard let iconURL = item.iconURL else { return }
                    remoteIcon = try? await imageLoader.loadImage(from: iconURL)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    Text(item.publisher)
                        .foregroundColor(Color.rebrandableLink(palette: palette))
                }
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer(minLength: 0)

                if let onGet {
                    Button(action: onGet) {
                        Text(UserText.extensionsSettingsGetButton)
                            .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                            .frame(minWidth: Const.buttonLabelMinWidth, minHeight: Const.buttonMinHeight)
                    }
                    .buttonStyle(StandardButtonStyle(topPadding: 0,
                                                     bottomPadding: 0,
                                                     horizontalPadding: Const.buttonHorizontalPadding,
                                                     backgroundColor: Color(designSystemColor: .controlsFillPrimary, palette: palette),
                                                     backgroundPressedColor: Color(designSystemColor: .controlsFillSecondary, palette: palette),
                                                     cornerRadius: Const.buttonCornerRadius))
                    .fixedSize()
                }
            }
            .padding(.horizontal, Const.padding)
            .frame(maxWidth: Const.maxWidth)
            .frame(height: Const.height)
            .background(Color(designSystemColor: .controlsSubtleFillSecondary, palette: palette))
            .clipShape(RoundedRectangle(cornerRadius: Const.cornerRadius, style: .continuous))
            .accessibilityIdentifier("Preferences.Extensions.\(item.id)")
        }
    }
}
