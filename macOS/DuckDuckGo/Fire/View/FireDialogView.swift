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
        static let footerReservedHeight: CGFloat = 52
    }

    private var tabsSubtitle: String {
        switch viewModel.clearingOption {
        case .currentTab:
            if viewModel.isPinnedTabSelected {
                return UserText.fireDialogPinnedTabWillReload
            }
            return UserText.fireDialogCloseThisTab
        case .currentWindow:
            return UserText.fireDialogCloseThisWindow
        case .allData:
            return UserText.fireDialogCloseAllTabsWindows
        }
    }

    @ObservedObject var viewModel: FireDialogViewModel
    private let featureFlagger: FeatureFlagger
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingSitesOverlay: Bool = false {
        didSet {
            isAnimatingSitesOverlay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAnimatingSitesOverlay = false
            }
        }
    }
    @State private var isAnimatingSitesOverlay: Bool = false

    init(viewModel: FireDialogViewModel, showSitesOverlay: Bool = false, featureFlagger: FeatureFlagger? = nil) {
        self.featureFlagger = featureFlagger ?? Application.appDelegate.featureFlagger
        self.viewModel = viewModel
        self._isShowingSitesOverlay = State(initialValue: showSitesOverlay)
    }

    private var historySubtitle: String {
        let count = viewModel.historyItemsCountForCurrentScope
        guard count > 0 else { return UserText.none }
        switch viewModel.clearingOption {
        case .currentTab:
            return UserText.fireDialogHistoryItemsSubtitleTab(count)
        case .currentWindow:
            return UserText.fireDialogHistoryItemsSubtitleWindow(count)
        case .allData:
            return UserText.fireDialogHistoryItemsSubtitle(count)
        }
    }

    private var cookiesSubtitle: String {
        let count = viewModel.cookiesSitesCountForCurrentScope
        return count == 0 ? UserText.none : UserText.fireDialogCookiesCountSubtitle(count)
    }

    private var isDeleteEnabled: Bool {
        viewModel.includeTabsAndWindows || viewModel.includeHistory || viewModel.includeCookiesAndSiteData
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                VStack(spacing: 16) {
                    headerView
                        .padding(.top, 10) // presenter sheet crops the padding 🤷‍♂️
                    segmentedControlView
                    sectionsView
                    if featureFlagger.isFeatureOn(.fireDialogIndividualSitesLink) {
                        individualSitesLink
                    }
                }
                .padding(.horizontal, 16)

                // Sites Overlay
                if isShowingSitesOverlay {
                    // Scrim fades independently and stays above content
                    Color.black.opacity(0.35)
                        .zIndex(9)

                    // Sliding sheet anchored above footer
                    VStack(spacing: 0) {
                        Spacer(minLength: 62)

                        sitesOverlay

                        // Separator above the footer
                        Color(designSystemColor: .fireDialogSectionBorder)
                            .frame(height: 1)
                    }
                    .zIndex(10)
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: NSAnimationContext.current.duration),
                       value: isAnimatingSitesOverlay)

            footerView
                .zIndex(11)
                .padding(.bottom, 10) // presenter sheet crops the padding 🤷‍♂️
                .background(Color(designSystemColor: .fireDialogBackground))
        }
        .frame(maxWidth: Constants.viewSize.width, maxHeight: .infinity)
        .background(Color(designSystemColor: .fireDialogBackground))
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Color.Size72.fire)
                .padding(.top, 8)

            Text(UserText.fireDialogTitle)
                .multilineText()
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
                set: { viewModel.clearingOption = FireDialogViewModel.ClearingOption(rawValue: $0) ?? .allData }
            ),
            segments: [
                .init(id: FireDialogViewModel.ClearingOption.currentTab.rawValue, title: UserText.fireDialogSegmentTab, image: Image(nsImage: DesignSystemImages.Glyphs.Size24.tabDesktop)),
                .init(id: FireDialogViewModel.ClearingOption.currentWindow.rawValue, title: UserText.fireDialogSegmentWindow, image: Image(nsImage: DesignSystemImages.Glyphs.Size24.window)),
                .init(id: FireDialogViewModel.ClearingOption.allData.rawValue, title: UserText.fireDialogSegmentEverything, image: Image(nsImage: DesignSystemImages.Glyphs.Size24.windowsAndTabs))
            ],
            containerBackground: Color(designSystemColor: .fireDialogPillBackground),
            containerBorder: Color(designSystemColor: .fireDialogPillBorder),
            selectedForeground: Color(designSystemColor: .accentPrimary),
            unselectedForeground: Color(designSystemColor: .buttonsSecondaryFillText),
            selectedIconBackground: Color(designSystemColor: .fireDialogPillSelectedSegmentIconBackground),
            selectedSegmentFill: Color(designSystemColor: .fireDialogPillSelectedSegmentBackground),
            selectedSegmentStroke: Color(designSystemColor: .fireDialogPillSelectedSegmentBorder),
            selectedSegmentShadowColor: Color(designSystemColor: .shadowTertiary),
            selectedSegmentShadowRadius: 0,
            selectedSegmentShadowY: 1,
            selectedSegmentTopStroke: Color(designSystemColor: .fireDialogPillSelectedSegmentTopStroke),
            hoverSegmentBackground: Color(designSystemColor: .fireDialogPillSegmentMouseOver),
            pressedSegmentBackground: Color(designSystemColor: .fireDialogPillSegmentMouseDown),
            hoverOverlay: Color(designSystemColor: .fireDialogPillHoverOverlay)
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
                isOn: $viewModel.includeTabsAndWindows
            )
            sectionDivider()

            // Row 2: History
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.history,
                title: UserText.fireDialogHistoryTitle,
                subtitle: historySubtitle,
                isOn: $viewModel.includeHistory
            )
            sectionDivider()

            // Row 3: Cookies and Site Data
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.cookie,
                title: UserText.cookiesAndSiteDataTitle,
                subtitle: cookiesSubtitle,
                isOn: $viewModel.includeCookiesAndSiteData,
                // don‘t show the ℹ button when there‘s no site data in scope
                infoAction: (viewModel.cookiesSitesCountForCurrentScope > 0) ? { isShowingSitesOverlay = true } : nil,
                // grey-out the ℹ button when the toggle is Off
                infoEnabled: viewModel.includeCookiesAndSiteData
            )
            sectionDivider(padding: 0)

            // Fireproof section
            fireproofSectionView
        }
        .background(
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                .fill(Color(designSystemColor: .fireDialogSectionBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                        .stroke(Color(designSystemColor: .fireDialogSectionBorder), lineWidth: 1)
                )
        )
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func presentManageFireproof() {
        // Use the app's preferences presenter to begin a sheet on the parent window (stacks above the Fire sheet)
        Task { @MainActor in
            Application.appDelegate.dataClearingPreferences.presentManageFireproofSitesDialog()
            viewModel.clearingOption = viewModel.clearingOption // trigger data reload
        }
    }

    private func presentIndividualSites() {
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

    // MARK: - Sites overlay
    private var sitesOverlay: some View {
        VStack(spacing: 0) {
            // Header
            ZStack(alignment: .center) {
                HStack {
                    Button(action: { isShowingSitesOverlay = false }) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(StandardButtonStyle(topPadding: 6, bottomPadding: 6, horizontalPadding: 6))
                    .clipShape(Circle())
                    .keyboardShortcut(.cancelAction)

                    Spacer()
                }

                Text(UserText.fireDialogSitesOverlayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
            .padding(16)

            // Sites table
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(UserText.fireDialogSitesOverlaySubtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .frame(alignment: .leading)
                        .padding(.bottom, 6)

                    ForEach(viewModel.selectable, id: \.domain) { item in
                        HStack(spacing: 6) {
                            FaviconView(url: URL(string: "https://\(item.domain)"), size: 16)
                            Text(item.domain)
                                .font(.system(size: 13))
                                .foregroundColor(Color(designSystemColor: .textPrimary))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(item.domain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 2)

                    // Fireproof sites
                    if !viewModel.fireproofed.isEmpty {
                        Text(UserText.fireproofCookiesAndSiteDataExplanation)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                            .frame(alignment: .leading)
                            .padding(.top, 8)
                            .padding(.bottom, 6)

                        ForEach(viewModel.fireproofed, id: \.domain) { item in
                            HStack(spacing: 6) {
                                FaviconView(url: URL(string: "https://\(item.domain)"), size: 16)
                                Text(item.domain)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(designSystemColor: .textPrimary))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(item.domain)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.bottom, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
        }
        .background(
            CustomRoundedCornersShape(tl: 8, tr: 8, bl: 0, br: 0)
                .fill(Color(designSystemColor: .fireDialogBackground))
        )
    }

    private func sectionRow(icon: NSImage, title: String, subtitle: String, isOn: Binding<Bool>, infoAction: (() -> Void)? = nil, infoEnabled: Bool = true) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 6) {
                Image(nsImage: icon)
                    .padding(.trailing, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(3)
                }

                Spacer()
                if let infoAction {
                    Button(action: infoAction) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size12.info)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!infoEnabled)
                    .opacity(infoEnabled ? 1.0 : 0.4)
                    .padding(.trailing, 4)
                }
                Toggle(isOn: isOn)
                    .toggleStyle(FireToggleStyle(onFill: Color(designSystemColor: .accentPrimary), knobFill: Color(designSystemColor: .fireDialogToggleKnob)))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(width: Constants.viewSize.width - 32, alignment: .leading)
            .contentShape(Rectangle()) // allow hit-test in empty rect areas
        }
        .buttonStyle(RowPressButtonStyle())
    }

    private func sectionDivider(padding: CGFloat = 16) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(designSystemColor: .fireDialogSectionBorder)).frame(height: 1)
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
                    .buttonStyle(StandardButtonStyle(fontSize: 11, topPadding: 3, bottomPadding: 3, horizontalPadding: 12))
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(width: Constants.viewSize.width - 32, alignment: .leading)
        }
        .buttonStyle(RowPressButtonStyle())
    }

    private var individualSitesLink: some View {
        HStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.globeBlocked
                .tinted(with: .linkBlue))
            TextButton(UserText.fireDialogManageIndividualSitesLink, fontSize: 11) {
                presentIndividualSites()
            }

            Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight
                .resized(to: NSSize(width: 12, height: 12))
                .tinted(with: .linkBlue))

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
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(designSystemColor: .buttonsSecondaryFillDefault))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                viewModel.burn()
                dismiss()
            } label: {
                Text(UserText.delete)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(DestructiveActionButtonStyle(enabled: isDeleteEnabled, topPadding: 0, bottomPadding: 0))
            .disabled(!isDeleteEnabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

}
// Full-row press highlight style
private struct RowPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: true, vertical: true)
            .background(configuration.isPressed ? Color.buttonMouseDown : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
private class MockFireproofDomains: FireproofDomains {
    init(domains: [String]) {
        super.init(store: FireproofDomainsStore(context: nil), tld: TLD())
        for domain in domains {
            super.add(domain: domain)
        }
    }
}
@available(macOS 14.0, *)
#Preview("Fire Dialog", traits: FireDialogView.Constants.viewSize.fixedLayout) {
    let tld = TLD()
    let vm = FireDialogViewModel(
        fireViewModel: FireViewModel(tld: tld, visualizeFireAnimationDecider: NSApp.delegateTyped.visualizeFireSettingsDecider),
        tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
        historyCoordinating: Application.appDelegate.historyCoordinator,
        fireproofDomains: Application.appDelegate.fireproofDomains,
        faviconManagement: Application.appDelegate.faviconManager,
        tld: tld,
        onboardingContextualDialogsManager: Application.appDelegate.onboardingContextualDialogsManager
    )

    PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm, featureFlagger: MockFeatureFlagger(featuresStub: [
            MacOSBrowserConfigSubfeature.fireDialogIndividualSitesLink.rawValue: true
        ]))
    }
}

 @available(macOS 14.0, *)
#Preview("Sites Overlay", traits: FireDialogView.Constants.viewSize.fixedLayout) {
    let tld = TLD()
    // Seed history with example domains
    let history = Application.appDelegate.historyCoordinator
    history.loadHistory(onCleanFinished: {})
    _ = history.addVisit(of: URL(string: "https://apple.com/")!, at: Date())
    _ = history.addVisit(of: URL(string: "https://beta.org/")!, at: Date())
    _ = history.addVisit(of: URL(string: "https://gamma.com/")!, at: Date())
    _ = history.addVisit(of: URL(string: "https://cnn.com/")!, at: Date())
    _ = history.addVisit(of: URL(string: "https://dropbox.com/")!, at: Date())
    _ = history.addVisit(of: URL(string: "https://my-test-long-long-long-domain-name-that-is-not-fireproofed.com")!, at: Date())
    _ = history.addVisit(of: URL(string: "https://y-the-very-long-domain-name-for-preview-testing-is-in-the-end.com")!, at: Date())

    // Fireproof a couple of sites for contrast
    let fireproofDomains = MockFireproofDomains(domains: [
        "apple.com",
        "y-the-very-long-domain-name-for-preview-testing-is-in-the-end.com"
    ])

    // Provide simple preview icons from bundled assets (replace names if needed)
    let faviconMock = FaviconManagerMock()
    faviconMock.setImage(NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)!, forHost: "apple.com")
    faviconMock.setImage(NSImage(named: NSImage.bonjourName)!, forHost: "cnn.com")
    faviconMock.setImage(NSImage(named: NSImage.networkName)!, forHost: "dropbox.com")

    let vm = FireDialogViewModel(
        fireViewModel: FireViewModel(tld: tld, visualizeFireAnimationDecider: NSApp.delegateTyped.visualizeFireSettingsDecider),
        tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
        historyCoordinating: history,
        fireproofDomains: fireproofDomains,
        faviconManagement: faviconMock,
        clearingOption: .allData,
        tld: tld,
        onboardingContextualDialogsManager: Application.appDelegate.onboardingContextualDialogsManager
    )

    return PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm, showSitesOverlay: true, featureFlagger: MockFeatureFlagger(featuresStub: [
            MacOSBrowserConfigSubfeature.fireDialogIndividualSitesLink.rawValue: true
        ]))
    }
}
#endif
