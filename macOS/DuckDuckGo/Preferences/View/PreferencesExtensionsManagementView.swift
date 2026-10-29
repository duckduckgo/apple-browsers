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
import DesignResourcesKitIcons
import PreferencesUI_macOS
import PrivacyConfig
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
            static let moreExtensionsBottomPadding: CGFloat = 42
        }

        @StateObject private var model: ExtensionsManagementPreferences
        @State private var imageLoader: RemoteMessagingImageLoading = RemoteMessagingImageLoader(dataProvider: RemoteMessagingImageLoader.defaultDataProvider,
                                                                                                 cache: RemoteMessagingImageLoader.defaultCache)

        @Environment(\.designSystemPalette) private var palette

        init(configurationManager: PrivacyConfigurationManaging,
             webExtensionManager: WebExtensionManaging?,
             windowControllersManager: WindowControllersManagerProtocol) {
            _model = StateObject(wrappedValue: ExtensionsManagementPreferences(configurationManager: configurationManager,
                                                                               webExtensionManager: webExtensionManager,
                                                                               windowControllersManager: windowControllersManager))
        }

        var body: some View {
            if let entry = model.detailsEntry {
                ExtensionDetailsView(entry: entry,
                                     onBack: model.hideDetails,
                                     onRemove: { model.remove(entry) })
            } else {
                overview
            }
        }

        private var overview: some View {
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

                extensionsList
            }
        }

        private var extensionsList: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !model.installedExtensions.isEmpty {
                    installedExtensionsView

                    if !model.uninstalledPasswordManagers.isEmpty {
                        moreExtensionsHeader
                    }
                }

                if !model.uninstalledPasswordManagers.isEmpty {
                    uninstalledExtensionsView
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
        }

        private var installedExtensionsView: some View {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(UserText.extensionsSettingsAddedHeader)
                ForEach(model.installedExtensions) { entry in
                    installedRow(for: entry)
                }
            }
        }

        private func installedRow(for entry: ExtensionsManagementPreferences.InstalledExtensionEntry) -> some View {
            InstalledExtensionRow(item: entry.listing,
                                  imageLoader: imageLoader,
                                  isEnabled: Binding(get: { entry.isEnabled },
                                                     set: { model.setEnabled($0, for: entry) }),
                                  isLocked: entry.isRemotelyDisabled,
                                  onDetails: { model.showDetails(for: entry) },
                                  onRemove: { model.remove(entry) })
        }

        private var moreExtensionsHeader: some View {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.top, Const.dividerTopPadding)
                    .padding(.bottom, Const.dividerBottomPadding)
                sectionTitle(UserText.extensionsSettingsMoreExtensionsHeader)
                    .padding(.bottom, Const.moreExtensionsBottomPadding)
            }
        }

        private var uninstalledExtensionsView: some View {
            VStack(alignment: .leading, spacing: 12) {
                TextMenuItemHeader(UserText.extensionsSettingsPasswordManagersHeader)
                ForEach(model.uninstalledPasswordManagers) { item in
                    UninstalledExtensionRow(item: item, imageLoader: imageLoader) {
                        model.openStorePage(for: item)
                    }
                }
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
                model.openLearnMore()
                return .handled
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

    private struct UninstalledExtensionRow: View {

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
        let onGet: () -> Void

        @Environment(\.designSystemPalette) private var palette

        var body: some View {
            HStack(spacing: 16) {
                ExtensionSummary(item: item,
                                 imageLoader: imageLoader,
                                 tileSize: Const.iconTileSize,
                                 tileCornerRadius: Const.iconTileCornerRadius,
                                 iconSize: Const.iconSize)

                Spacer(minLength: 0)

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
            .padding(.horizontal, Const.padding)
            .frame(maxWidth: Const.maxWidth)
            .frame(height: Const.height)
            .background(Color(designSystemColor: .containerFillSecondary, palette: palette))
            .clipShape(RoundedRectangle(cornerRadius: Const.cornerRadius, style: .continuous))
            .accessibilityIdentifier("Preferences.Extensions.\(item.id)")
        }
    }

    private struct InstalledExtensionRow: View {

        private enum Const {
            static let maxWidth: CGFloat = 560
            static let height: CGFloat = 80
            static let cornerRadius: CGFloat = 16
            static let leadingPadding: CGFloat = 16
            static let trailingPadding: CGFloat = 24
            static let iconTileSize: CGFloat = 48
            static let iconTileCornerRadius: CGFloat = 8
            static let iconSize: CGFloat = 24
            static let optionsToSwitchSpacing: CGFloat = 16
        }

        let item: ChromeWebStoreListing
        let imageLoader: RemoteMessagingImageLoading
        @Binding var isEnabled: Bool
        let isLocked: Bool
        let onDetails: () -> Void
        let onRemove: () -> Void

        @Environment(\.designSystemPalette) private var palette

        var body: some View {
            HStack(spacing: 16) {
                ExtensionSummary(item: item,
                                 imageLoader: imageLoader,
                                 tileSize: Const.iconTileSize,
                                 tileCornerRadius: Const.iconTileCornerRadius,
                                 iconSize: Const.iconSize)

                Spacer(minLength: 0)

                HStack(spacing: Const.optionsToSwitchSpacing) {
                    Menu {
                        Button(UserText.extensionsSettingsDetailsMenuItem, action: onDetails)
                        Divider()
                        Button(UserText.webExtensionRemoveMenuItem, action: onRemove)
                    } label: {
                        Image(nsImage: DesignSystemImages.Glyphs.Size16.menuDots)
                            .renderingMode(.template)
                            .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(UserText.extensionsSettingsMoreOptions)

                    Toggle(isOn: $isEnabled) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(isLocked)
                }
            }
            .padding(.leading, Const.leadingPadding)
            .padding(.trailing, Const.trailingPadding)
            .frame(maxWidth: Const.maxWidth)
            .frame(height: Const.height)
            .background(Color(designSystemColor: .containerFillSecondary, palette: palette))
            .clipShape(RoundedRectangle(cornerRadius: Const.cornerRadius, style: .continuous))
            .accessibilityIdentifier("Preferences.Extensions.\(item.id)")
        }
    }

    @available(macOS 15.4, *)
    private struct ExtensionDetailsView: View {

        private enum Const {
            static let backButtonSize: CGFloat = 32
            static let backButtonCornerRadius: CGFloat = 6
            static let chevronSize: CGFloat = 18
            static let headerSpacing: CGFloat = 4
            static let cardTopPadding: CGFloat = 24
            static let cardWidth: CGFloat = 512
            static let cardCornerRadius: CGFloat = 12
            static let rowHeight: CGFloat = 58
            static let rowHorizontalPadding: CGFloat = 10
            static let titleFontSize: CGFloat = 13
            static let detailsFontSize: CGFloat = 11
            static let removeButtonTopPadding: CGFloat = 56
            static let removeButtonHeight: CGFloat = 24
            static let removeButtonHorizontalPadding: CGFloat = 8
        }

        let entry: ExtensionsManagementPreferences.InstalledExtensionEntry
        let onBack: () -> Void
        let onRemove: () -> Void

        @Environment(\.designSystemPalette) private var palette

        var body: some View {
            PreferencePane(nil, spacing: 0) {
                header
                card
                    .padding(.top, Const.cardTopPadding)
                removeButton
                    .padding(.top, Const.removeButtonTopPadding)
            }
            .accessibilityIdentifier("Preferences.Extensions.Details.\(entry.listing.id)")
        }

        private var header: some View {
            HStack(alignment: .top, spacing: Const.headerSpacing) {
                Button(action: onBack) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size24.chevronLeft)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Const.chevronSize, height: Const.chevronSize)
                        .foregroundColor(Color(designSystemColor: .iconsPrimary, palette: palette))
                        .frame(width: Const.backButtonSize, height: Const.backButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverHighlightButtonStyle(cornerRadius: Const.backButtonCornerRadius))
                .accessibilityLabel(UserText.extensionsSettingsBack)

                VStack(alignment: .leading, spacing: Const.headerSpacing) {
                    TextMenuTitle(entry.listing.name)
                    StatusIndicatorView(status: entry.isEnabled ? .on : .off, isLarge: true)
                }
            }
        }

        private var card: some View {
            let rows = [
                entry.record.version.map { (UserText.extensionsSettingsVersion, $0) },
                // Settings only lists extensions installed from the Chrome Web Store.
                (UserText.extensionsSettingsSource, UserText.extensionsSettingsChromeWebStore),
                entry.permissionsSummary.map { (UserText.extensionsSettingsPermissions, $0) }
            ].compactMap { $0 }

            return VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    detailRow(title: row.0, details: row.1)
                }
            }
            .padding(.horizontal, Const.rowHorizontalPadding)
            .frame(width: Const.cardWidth)
            .background(Color(designSystemColor: .containerFillSecondary, palette: palette))
            .clipShape(RoundedRectangle(cornerRadius: Const.cardCornerRadius, style: .continuous))
        }

        private func detailRow(title: String, details: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: Const.titleFontSize))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                Text(details)
                    .font(.system(size: Const.detailsFontSize))
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: Const.rowHeight, alignment: .leading)
        }

        private var removeButton: some View {
            Button(action: onRemove) {
                Text(UserText.extensionsSettingsRemoveButton)
                    .padding(.horizontal, Const.removeButtonHorizontalPadding)
                    .frame(height: Const.removeButtonHeight)
            }
            .buttonStyle(DismissActionButtonStyle(textColor: Color(designSystemColor: .destructiveTextPrimary, palette: palette),
                                                  topPadding: 0,
                                                  bottomPadding: 0,
                                                  showsBorder: true,
                                                  stateColors: .themedDismissButton))
            .fixedSize()
        }
    }

    private struct ExtensionSummary: View {

        let item: ChromeWebStoreListing
        let imageLoader: RemoteMessagingImageLoading
        let tileSize: CGFloat
        let tileCornerRadius: CGFloat
        let iconSize: CGFloat

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
                            .frame(width: iconSize, height: iconSize)
                    }
                }
                .frame(width: tileSize, height: tileSize)
                .background(Color(designSystemColor: .containerFillTertiary, palette: palette))
                .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
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
            }
        }
    }
}
