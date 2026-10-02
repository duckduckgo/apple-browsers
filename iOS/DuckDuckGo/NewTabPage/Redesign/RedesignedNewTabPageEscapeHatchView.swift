//
//  RedesignedNewTabPageEscapeHatchView.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

/// Renders the same eligible return-to-tab model as the production resting page.
struct RedesignedNewTabPageEscapeHatchView: View {
    @ObservedObject var pageModel: NewTabPageViewModel

    var body: some View {
        if let escapeHatch = pageModel.escapeHatch {
            RedesignedEscapeHatchView(model: escapeHatch)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.horizontalPadding)
        }
    }
}

/// Adapts the live tab model to the value-based redesigned module.
struct RedesignedEscapeHatchView: View {
    @ObservedObject var model: EscapeHatchModel
    @State private var menuFrameInWindow: CGRect = .zero

    var body: some View {
        Group {
            if model.isReturnToTabCardVisible {
                RedesignedEscapeHatchModuleView(
                    title: model.title,
                    domain: model.subtitle.isEmpty ? nil : model.subtitle,
                    lastVisitedText: lastVisitedText,
                    thumbnail: model.thumbnail,
                    favicon: specialTabIcon,
                    faviconDomain: model.domain,
                    onMenuFrameChange: { menuFrameInWindow = $0 },
                    swipeActionLabel: model.primarySwipeAction.label,
                    onSwipeCommit: model.performPrimarySwipeAction,
                    onTap: model.onCardTap,
                    onFireTap: model.burnFromButton,
                    onShowAllTap: model.onTabSwitcherTap) {
                        menuContent
                    }
            } else {
                EscapeHatchView(model: model, usesMaterialBackground: true)
            }
        }
        .animation(.easeInOut(duration: Metrics.collapseDuration), value: model.isReturnToTabCardVisible)
        .id(model.targetTab.uid)
    }

    private var lastVisitedText: String? {
        guard !model.isFireTab, let lastViewedDate = model.targetTab.lastViewedDate else { return nil }
        return lastViewedDate.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private var specialTabIcon: UIImage? {
        switch model.tabType {
        case .fire:
            return DesignSystemImages.Color.Size96.fireTab
        case .aiChat:
            return DesignSystemImages.Color.Size16.duckAI
        case .regular:
            return nil
        }
    }

    private var menuContent: some View {
        Section {
            menuButton(UserText.escapeHatchMenuReturnToTab,
                       icon: DesignSystemImages.Glyphs.Size16.goBackCircle,
                       action: model.returnToTabFromMenu)
            if !model.isFireTab {
                menuButton(UserText.escapeHatchMenuCloseTab,
                           icon: DesignSystemImages.Glyphs.Size16.closeOutline,
                           role: .destructive,
                           action: model.closeTabFromMenu)
            }
            menuButton(UserText.escapeHatchMenuDeleteTab,
                       icon: DesignSystemImages.Glyphs.Size16.fire,
                       role: .destructive,
                       action: deleteTab)
            Section {
                Picker(selection: model.afterInactivityOptionBinding) {
                    ForEach(AfterInactivityOption.allCases, id: \.self) { option in
                        Text(option.description).tag(option)
                    }
                } label: {
                    Text(UserText.settingsAfterInactivityLabel)
                    Text(model.afterInactivityOptionBinding.wrappedValue.description)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .daxSubheadRegular()
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.settings)
                        .foregroundColor(Color(designSystemColor: .icons))
                }
                .pickerStyle(.menu)
                menuButton(UserText.escapeHatchMenuHideTheseShortcuts,
                           icon: DesignSystemImages.Glyphs.Size16.eyeClosed,
                           action: model.hideShortcut)
            }
        }
        .onAppear { model.menuDidAppear() }
    }

    private func menuButton(_ text: String, icon: UIImage, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label {
                Text(text)
            } icon: {
                Image(uiImage: icon)
                    .foregroundColor(role == nil ? Color(designSystemColor: .icons) : nil)
            }
        }
    }

    private func deleteTab() {
        if model.isFireTab {
            model.burnImmediatelyFromMenu()
        } else {
            model.burnWithConfirmationFromMenu(menuFrameInWindow)
        }
    }
}

private enum Metrics {
    static let horizontalPadding: CGFloat = 16
    static let collapseDuration: Double = 0.25
}
