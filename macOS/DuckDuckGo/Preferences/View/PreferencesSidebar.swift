//
//  PreferencesSidebar.swift
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

import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

extension Preferences {

    struct SidebarSectionHeader: View {
        let section: PreferencesSectionIdentifier
        let isSubscriptionRebrandingOn: Bool

        var body: some View {
            Group {
                if let name = section.displayName(isSubscriptionRebrandingOn: isSubscriptionRebrandingOn) {
                    Text(name)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 3)
                        .font(PreferencesUI_macOS.Const.Fonts.sideBarHeader)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                }
            }
        }
    }

    struct PaneSidebarItem: View {
        let pane: PreferencePaneIdentifier
        let isSelected: Bool
        let isEnabled: Bool
        let action: () -> Void
        let settingsIconProvider: SettingsIconsProviding
        let isSubscriptionRebrandingOn: Bool
        let isNew: Bool
        @ObservedObject var protectionStatus: PrivacyProtectionStatus

        init(pane: PreferencePaneIdentifier,
             isSelected: Bool,
             isEnabled: Bool = true,
             status: PrivacyProtectionStatus?,
             settingsIconProvider: SettingsIconsProviding,
             isSubscriptionRebrandingOn: Bool,
             isNew: Bool = false,
             action: @escaping () -> Void) {
            self.pane = pane
            self.isSelected = isSelected
            self.isEnabled = isEnabled
            self.action = action
            self.protectionStatus = status ?? PrivacyProtectionStatus()
            self.settingsIconProvider = settingsIconProvider
            self.isSubscriptionRebrandingOn = isSubscriptionRebrandingOn
            self.isNew = isNew
        }

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: 6) {
                    Image(nsImage: pane.preferenceIconName(for: settingsIconProvider, isSubscriptionRebrandingOn: isSubscriptionRebrandingOn))
                        .frame(width: 16, height: 16)
                        .if(!isEnabled) {
                            $0.grayscale(1.0).opacity(0.5)
                        }

                    Text(pane.displayName(isSubscriptionRebrandingOn: isSubscriptionRebrandingOn)).font(PreferencesUI_macOS.Const.Fonts.sideBarItem)
                        .if(!isEnabled) {
                            $0.opacity(0.5)
                        }

                    if isNew {
                        NewBadgeView()
                    }

                    Spacer()

                    if let status = protectionStatus.status {
                        StatusIndicatorView(status: status)
                            .frame(minWidth: 0, alignment: .trailing)
                            .layoutPriority(-1)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .buttonStyle(SidebarItemButtonStyle(isSelected: isSelected))
            .accessibilityIdentifier("PreferencesSidebar.\(pane.id.rawValue)Button")
            .disabled(!isEnabled)
        }
    }

    struct NewBadgeView: View {
        var body: some View {
            Text(UserText.newBadge.uppercased())
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(designSystemColor: .alertYellow))
                .foregroundColor(.black)
                .cornerRadius(4)
        }
    }

    struct TabSwitcher: View {
        @EnvironmentObject var model: PreferencesSidebarModel

        var body: some View {
            NSPopUpButtonView(selection: $model.selectedTabIndex, viewCreator: {
                let button = NSPopUpButton()
                button.font = PreferencesUI_macOS.Const.Fonts.popUpButton
                button.setButtonType(.momentaryLight)
                button.isBordered = false
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                for (index, type) in model.tabSwitcherTabs.enumerated() {
                    guard let tabTitle = type.title else {
                        assertionFailure("Attempted to display standard tab type in tab switcher")
                        continue
                    }

                    let item = button.menu?.addItem(withTitle: tabTitle, action: nil, keyEquivalent: "")
                    item?.representedObject = index
                }

                return button
            })
            .padding(.horizontal, 3)
            .frame(height: 51)
            .onAppear(perform: model.resetTabSelectionIfNeeded)
        }
    }

    struct Sidebar: View {
        @EnvironmentObject var model: PreferencesSidebarModel

        var body: some View {
            VStack(spacing: 12) {
                TabSwitcher()
                    .environmentObject(model)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.sections) { section in
                            SidebarSectionHeader(section: section.id, isSubscriptionRebrandingOn: model.isSubscriptionRebrandingEnabled)
                            sidebarSection(section, settingsIconProvider: model.settingsIconProvider)
                        }
                    }.padding(.bottom, 16)
                }

            }
            .padding(.top, 18)
            .padding(.horizontal, 10)
            .onAppear {
                model.onAppear()
            }
        }

        @ViewBuilder
        private func sidebarSection(_ section: PreferencesSection,
                                    settingsIconProvider: SettingsIconsProviding) -> some View {
            ForEach(section.panes) { pane in
                PaneSidebarItem(pane: pane,
                                isSelected: model.selectedPane == pane,
                                isEnabled: model.isSidebarItemEnabled(for: pane),
                                status: model.protectionStatus(for: pane),
                                settingsIconProvider: settingsIconProvider,
                                isSubscriptionRebrandingOn: model.isSubscriptionRebrandingEnabled,
                                isNew: model.isPaneNew(pane: pane),
                                action: {
                                    model.selectPane(pane)
                                })
            }
            if section != model.sections.last {
                Color(NSColor.separatorColor)
                    .frame(height: 1)
                    .padding(8)
            }
        }
    }

    private struct SidebarItemButtonStyle: ButtonStyle {

        let isSelected: Bool

        @State private var isHovered: Bool = false

        func makeBody(configuration: Self.Configuration) -> some View {

            let bgColor: Color = {
                if isSelected {
                    return .rowHover
                }
                if isHovered {
                    return .buttonMouseOver
                }
                return Color(NSColor.clear.withAlphaComponent(0.001))
            }()

            configuration.label
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .truncationMode(.tail)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bgColor))
                .onHover { inside in
                    self.isHovered = inside
                }
        }
    }
}
