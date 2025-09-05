//
//  FireDialogView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import BrowserServicesKit
import Common
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

@MainActor
struct FireDialogView: ModalView {

    fileprivate enum Constants {
        static let viewSize = CGSize(width: 440, height: 592)
    }

    private var tabsSubtitle: String {
        switch viewModel.clearingOption {
        case .currentTab:
            return UserText.fireDialogCloseThisTab
        case .currentWindow:
            return UserText.fireDialogCloseThisWindow
        case .allData:
            return UserText.fireDialogCloseAllTabsWindows
        }
    }

    @ObservedObject var viewModel: FirePopoverViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var includeTabsAndWindows: Bool = true
    @State private var includeHistory: Bool = true
    @State private var includeCookiesAndSiteData: Bool = true

    private var historySubtitle: String {
        let count = viewModel.historyItemsCountForCurrentScope
        return count == 0 ? UserText.none : UserText.fireDialogHistoryItemsSubtitle(count)
    }

    private var cookiesSubtitle: String {
        let count = viewModel.cookiesSitesCountForCurrentScope
        return count == 0 ? UserText.none : UserText.fireDialogCookiesCountSubtitle(count)
    }

    private var isDeleteEnabled: Bool {
        includeTabsAndWindows || includeHistory || includeCookiesAndSiteData
    }

    var body: some View {
        VStack(spacing: 16) {
            headerView
            segmentedControlView
            sectionsView
            if Application.appDelegate.featureFlagger.isFeatureOn(.fireDialogIndividualSitesLink) {
                individualSitesLink
            }
            footerView
        }
        .padding(.horizontal, 16)
        .frame(width: 440)
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Color.Size24.fire.resized(to: NSSize(width: 64, height: 64)))
                .padding(.top, 8)

            Text(UserText.fireDialogTitle)
                .multilineTextAlignment(.center)
                .font(.system(size: 15).weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .padding(.vertical, 16)
    }

    private var segmentedControlView: some View {
        PillSegmentedControl(
            selection: Binding(
                get: { viewModel.clearingOption.rawValue },
                set: { viewModel.clearingOption = FirePopoverViewModel.ClearingOption(rawValue: $0) ?? .allData }
            ),
            segments: [
                .init(id: FirePopoverViewModel.ClearingOption.currentTab.rawValue, title: UserText.fireDialogSegmentTab, image: Image(nsImage: DesignSystemImages.Glyphs.Size16.tabDesktop.resized(to: NSSize(width: 24, height: 24)))),
                .init(id: FirePopoverViewModel.ClearingOption.currentWindow.rawValue, title: UserText.fireDialogSegmentWindow, image: Image(nsImage: DesignSystemImages.Glyphs.Size24.window)),
                .init(id: FirePopoverViewModel.ClearingOption.allData.rawValue, title: UserText.fireDialogSegmentEverything, image: Image(nsImage: DesignSystemImages.Glyphs.Size16.windowsAndTabs.resized(to: NSSize(width: 24, height: 24))))
            ],
            selectedBackground: Color(designSystemColor: .accent),
            unselectedBackground: Color(designSystemColor: .buttonsSecondaryFillDefault),
            selectedForeground: Color(designSystemColor: .accentContentPrimary),
            unselectedForeground: Color(designSystemColor: .buttonsSecondaryFillText),
            selectedIconForeground: Color(designSystemColor: .accent),
            selectedLabelForeground: Color(designSystemColor: .textPrimary),
            containerBorder: Color(designSystemColor: .border),
            selectedIconBackground: Color(designSystemColor: .accent).opacity(0.12)
        )
        .frame(height: 84)
    }

    private var sectionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Tabs and Windows
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.windowsAndTabs,
                title: UserText.fireDialogTabsAndWindows,
                subtitle: tabsSubtitle,
                isOn: $includeTabsAndWindows
            )
            sectionDivider()

            // Row 2: History
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.history,
                title: UserText.fireDialogHistoryTitle,
                subtitle: historySubtitle,
                isOn: $includeHistory
            )
            sectionDivider()

            // Row 3: Cookies and Site Data
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.cookie,
                title: UserText.cookiesAndSiteDataTitle,
                subtitle: cookiesSubtitle,
                isOn: $includeCookiesAndSiteData
            )
            sectionDivider(padding: 0)

            // Fireproof section
            fireproofSectionView
        }
        .background(
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                .fill(Color(designSystemColor: .surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                        .stroke(Color(designSystemColor: .border), lineWidth: 1)
                )
        )
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func presentManageFireproof() {
        // Use the app's preferences presenter to begin a sheet on the parent window (stacks above the Fire sheet)
        Application.appDelegate.dataClearingPreferences.presentManageFireproofSitesDialog()
    }

    // Full-row press highlight style (material-like)
    private struct RowPressButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(Color.black.opacity(configuration.isPressed ? 0.06 : 0))
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    private func sectionRow(icon: NSImage, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(alignment: .center, spacing: 6) {
                Image(nsImage: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13).weight(.semibold))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(isOn: isOn)
                    .toggleStyle(FireToggleStyle())
            }
            .contentShape(Rectangle())
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(RowPressButtonStyle())
    }

    private func sectionDivider(padding: CGFloat = 16) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(designSystemColor: .border)).frame(height: 1)
                .padding(.horizontal, padding)
        }
    }

    private var fireproofSectionView: some View {
        Button(action: { presentManageFireproof() }) {
            HStack(alignment: .center, spacing: 0) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.fireproof)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))

                Text(UserText.fireproofCookiesAndSiteDataExplanation)
                    .font(.system(size: 11))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 6)

                Spacer(minLength: 4)

                Button(UserText.fireDialogFireproofSitesManage) { presentManageFireproof() }
                    .buttonStyle(StandardButtonStyle())
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(RowPressButtonStyle())
    }

    private var individualSitesLink: some View {
        HStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.globeBlocked.tinted(with: NSColor(designSystemColor: .textLink)))
            Button(UserText.fireDialogManageIndividualSitesLink) {
                // Close the dialog and open History->Sites management
                if let window = NSApp.mainWindow {
                    window.endSheet(window.attachedSheet ?? window)
                }
                Application.appDelegate.windowControllersManager
                    .lastKeyMainWindowController?
                    .mainViewController
                    .browserTabViewController
                    .openNewTab(with: .history)
            }
            .buttonStyle(.link)
            Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight.resized(to: NSSize(width: 12, height: 12)).tinted(with: NSColor(designSystemColor: .textLink)))
        }
    }

    private var footerView: some View {
        // Buttons
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Text(UserText.cancel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(designSystemColor: .buttonsSecondaryFillDefault))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                viewModel.burn(includeHistory: includeHistory,
                               includeTabsAndWindows: includeTabsAndWindows,
                               includeCookiesAndSiteData: includeCookiesAndSiteData)
                dismiss()
            } label: {
                Text(UserText.delete)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(DestructiveActionButtonStyle(enabled: isDeleteEnabled, topPadding: 0, bottomPadding: 0))
            .disabled(!isDeleteEnabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

}

#if DEBUG
@available(macOS 14.0, *)
#Preview(traits: FireDialogView.Constants.viewSize.fixedLayout) {
    let tld = TLD()
    let vm = FirePopoverViewModel(
        fireViewModel: FireViewModel(tld: tld, visualizeFireAnimationDecider: NSApp.delegateTyped.visualizeFireSettingsDecider),
        tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
        historyCoordinating: Application.appDelegate.historyCoordinator,
        fireproofDomains: Application.appDelegate.fireproofDomains,
        faviconManagement: Application.appDelegate.faviconManager,
        initialClearingOption: .allData,
        tld: tld,
        onboardingContextualDialogsManager: Application.appDelegate.onboardingContextualDialogsManager
    )

    PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm)
    }
}
#endif
