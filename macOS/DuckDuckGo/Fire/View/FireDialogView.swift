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
import Common
import DesignResourcesKit
import DesignResourcesKitIcons
import History
import SwiftUI
import SwiftUIExtensions
import BrowserServicesKit
import Combine

// Result returned by FireDialogView when using onConfirm callback
struct FireDialogResult {
    let clearingOption: FireDialogViewModel.ClearingOption
    let includeHistory: Bool
    let includeTabsAndWindows: Bool
    let includeCookiesAndSiteData: Bool
    let includeChatHistory: Bool
    /// Optional selection of cookie domains (eTLD+1). When provided, cookie/site data clearing is limited to this set.
    var selectedCookieDomains: Set<String>?
    /// Optional explicit visits selection for history flows
    var selectedVisits: [Visit]?
    /// Burn all windows in case we are burning visits for today (respecting closeWindows flag)
    var isToday: Bool = false
}

@MainActor
struct FireDialogView: ModalView {

    enum Response {
        case noAction
        case burn(options: FireDialogResult?)
    }

    fileprivate enum Constants {
        static let viewSize = CGSize(width: 440, height: 592)
        static let footerReservedHeight: CGFloat = 52
    }

    @State private var viewHeight: CGFloat = Constants.viewSize.height

    private var tabsSubtitle: String {
        // Get base message based on scope
        let baseMessage: String
        switch viewModel.clearingOption {
        case .currentTab:
            baseMessage = UserText.fireDialogCloseThisTab
        case .currentWindow:
            baseMessage = UserText.fireDialogCloseThisWindow
        case .allData:
            baseMessage = UserText.fireDialogCloseAllTabsWindows
        }

        // Append pinned tabs message if applicable
        if let pinnedMessage = viewModel.pinnedTabsReloadMessage {
            switch viewModel.clearingOption {
            case .currentTab:
                return pinnedMessage
            case .currentWindow, .allData:
                return "\(baseMessage) \(pinnedMessage)"
            }
        }
        return baseMessage
    }

    @ObservedObject var viewModel: FireDialogViewModel
    private let showIndividualSitesLink: Bool
    private let onConfirm: ((FireDialogView.Response) -> Void)?
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

    init(viewModel: FireDialogViewModel,
         showSitesOverlay: Bool = false, // for Previews - @State flag to show "sites to be removed" overlay
         showIndividualSitesLink: Bool,
         onConfirm: ((FireDialogView.Response) -> Void)? = nil) {
        self.viewModel = viewModel
        self._isShowingSitesOverlay = State(initialValue: showSitesOverlay)
        self.showIndividualSitesLink = showIndividualSitesLink
        self.onConfirm = onConfirm
    }

    private var isIncludeHistoryEnabled: Bool {
        viewModel.historyItemsCountForCurrentScope > 0
    }

    private var isIncludeCookiesAndSiteDataEnabled: Bool {
        viewModel.cookiesSitesCountForCurrentScope > 0
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
        (viewModel.mode.shouldShowCloseTabsToggle && viewModel.includeTabsAndWindows)
        || (viewModel.includeHistory && isIncludeHistoryEnabled)
        || (viewModel.includeCookiesAndSiteData && isIncludeCookiesAndSiteDataEnabled)
        || viewModel.includeChatHistory
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                VStack(spacing: 16) {
                    headerView
                        .padding(.top, 10) // presenter sheet crops the padding 🤷‍♂️
                        .accessibilityHidden(isShowingSitesOverlay)
                    if viewModel.mode.shouldShowSegmentedControl {
                        segmentedControlView
                            .accessibilityHidden(isShowingSitesOverlay)
                    }
                    sectionsView
                    if showIndividualSitesLink {
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
        .readSize { size in
            // Set exact content height to avoid content shifting and animation jumping when sheet resizes
            viewHeight = size.height
        }
        .frame(width: Constants.viewSize.width, height: viewHeight, alignment: .top)
        .background(Color(designSystemColor: .fireDialogBackground))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(viewModel.mode.dialogTitle)
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Color.Size72.fire)
                .padding(.top, 8)

            Text(viewModel.mode.dialogTitle)
                .multilineText()
                .multilineTextAlignment(.center)
                .font(.system(size: 15).weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .accessibilityIdentifier("FireDialogView.title")
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
        .accessibilityIdentifier("FireDialogView.segmentedControl")
    }

    private var sectionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.mode.shouldShowCloseTabsToggle {
                sectionRow(
                    icon: DesignSystemImages.Glyphs.Size16.windowsAndTabs,
                    title: UserText.fireDialogTabsAndWindows,
                    subtitle: tabsSubtitle,
                    isOn: $viewModel.includeTabsAndWindows,
                    cornerRadius: .top,
                    toggleId: "FireDialogView.tabsToggle"
                )
                .accessibilityHidden(isShowingSitesOverlay)
                sectionDivider()
            }

            // Row 2: History
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.history,
                title: UserText.fireDialogHistoryTitle,
                subtitle: historySubtitle,
                isOn: Binding {
                    viewModel.includeHistory && isIncludeHistoryEnabled
                } set: {
                    viewModel.includeHistory = $0
                },
                isEnabled: isIncludeHistoryEnabled,
                cornerRadius: viewModel.mode.shouldShowCloseTabsToggle ? .none : .top,
                toggleId: "FireDialogView.historyToggle"
            )
            .accessibilityHidden(isShowingSitesOverlay)
            sectionDivider()

            // Row 3: Cookies and Site Data
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.cookie,
                title: UserText.cookiesAndSiteDataTitle,
                subtitle: cookiesSubtitle,
                isOn: Binding { viewModel.includeCookiesAndSiteData && isIncludeCookiesAndSiteDataEnabled } set: { viewModel.includeCookiesAndSiteData = $0 },
                // don‘t show the ℹ button when there‘s no site data in scope
                infoAction: isIncludeCookiesAndSiteDataEnabled ? { isShowingSitesOverlay = true } : nil,
                // grey-out the ℹ button when the toggle is Off
                infoEnabled: viewModel.includeCookiesAndSiteData,
                isEnabled: isIncludeCookiesAndSiteDataEnabled,
                cornerRadius: viewModel.mode.shouldShowFireproofSection ? .none : .bottom,
                toggleId: "FireDialogView.cookiesToggle"
            )
            .disabled(!isIncludeCookiesAndSiteDataEnabled)
            .accessibilityHidden(isShowingSitesOverlay)

            if viewModel.shouldShowChatHistoryToggle {
                sectionDivider()

            // Row 4: Chat History
                sectionRow(
                    icon: DesignSystemImages.Glyphs.Size16.aiChat,
                    title: UserText.fireDialogChatHistoryTitle,
                    subtitle: UserText.fireDialogChatHistorySubtitle,
                    isOn: $viewModel.includeChatHistorySetting,
                    toggleId: "FireDialogView.chatsToggle"
                )
                .accessibilityHidden(isShowingSitesOverlay)
            }
            sectionDivider(padding: 0)

            // Fireproof section
            if viewModel.mode.shouldShowFireproofSection {
                fireproofSectionView
                    .accessibilityHidden(isShowingSitesOverlay)
            }
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func presentManageFireproof() {
        // Use the app's preferences presenter to begin a sheet on the parent window (stacks above the Fire sheet)
        Task { @MainActor in
            // await for the dialog to complete and trigger data reload
            await Application.appDelegate.dataClearingPreferences.presentManageFireproofSitesDialog()
            viewModel.clearingOption = viewModel.clearingOption
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
            .openNewTab(with: .history(pane: .allSites))
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
                    .accessibilityLabel(UserText.close)
                    .accessibilityIdentifier("FireDialogView.sitesOverlayCloseButton")
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

    private func sectionRow(icon: NSImage, title: String, subtitle: String, isOn: Binding<Bool>, infoAction: (() -> Void)? = nil, infoEnabled: Bool = true, isEnabled: Bool = true, cornerRadius: RowCornerRadius = .none, toggleId: String) -> some View {
        RowWithPressEffect(cornerRadius: cornerRadius, isEnabled: isEnabled) {
            guard isEnabled else { return }
            isOn.wrappedValue.toggle()
        } content: {
            HStack(spacing: 6) {
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
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .accessibilityValue(subtitle)
                .accessibilityAddTraits(.updatesFrequently)

                Spacer()

                if let infoAction {
                    Button(action: infoAction) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size12.info)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(UserText.fireDialogSitesOverlayTitle)
                    .accessibilityIdentifier("FireDialogView.cookiesInfoButton")
                    .disabled(!infoEnabled)
                    .opacity(infoEnabled ? 1.0 : 0.4)
                    .padding(.trailing, 4)
                }

                Group {
                    Toggle(isOn: isOn)
                        .toggleStyle(FireToggleStyle(onFill: Color(designSystemColor: .accentPrimary), knobFill: Color(designSystemColor: .fireDialogToggleKnob)))
                        .accessibilityLabel(title)
                        .accessibilityIdentifier(toggleId)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(width: Constants.viewSize.width - 32, alignment: .leading)
        }
    }

    private func sectionDivider(padding: CGFloat = 16) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(designSystemColor: .fireDialogSectionBorder)).frame(height: 1)
                .padding(.horizontal, padding)
        }
    }

    private var fireproofSectionView: some View {
        RowWithPressEffect(cornerRadius: .bottom, isEnabled: true) {
            presentManageFireproof()
        } content: {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 6) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.fireproof)
                        .foregroundColor(Color(designSystemColor: .iconsSecondary))

                    Text(UserText.fireproofCookiesAndSiteDataExplanation)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(UserText.fireproofCookiesAndSiteDataExplanation)
                .accessibilityAddTraits(.isStaticText)

                Spacer(minLength: 4)

                Button(UserText.fireDialogFireproofSitesManage) { presentManageFireproof() }
                    .buttonStyle(StandardButtonStyle(fontSize: 11, topPadding: 3, bottomPadding: 3, horizontalPadding: 12))
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(alignment: .trailing)
                    .accessibilityLabel(UserText.manageFireproofSites)
                    .accessibilityIdentifier("FireDialogView.manageFireproofButton")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(width: Constants.viewSize.width - 32, alignment: .leading)
        }
    }

    private var individualSitesLink: some View {
        HStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.globeBlocked
                .tinted(with: .linkBlue))
                .accessibilityHidden(true)
            TextButton(UserText.fireDialogManageIndividualSitesLink, fontSize: 11) {
                presentIndividualSites()
            }
            .accessibilityIdentifier("FireDialogView.individualSitesLink")
            .accessibilityHidden(isShowingSitesOverlay)

            Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight
                .resized(to: NSSize(width: 12, height: 12))
                .tinted(with: .linkBlue))
                .accessibilityHidden(true)

        }
    }

    private var footerView: some View {
        // Buttons
        HStack(spacing: 8) {
            Button {
                onConfirm?(.noAction)
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
            .accessibilityLabel(UserText.cancel)
            .accessibilityIdentifier("FireDialogView.cancelButton")
            .keyboardShortcut(.cancelAction)

            Button {
                let result = FireDialogResult(
                    clearingOption: viewModel.clearingOption,
                    includeHistory: viewModel.includeHistory,
                    includeTabsAndWindows: viewModel.includeTabsAndWindows,
                    includeCookiesAndSiteData: viewModel.includeCookiesAndSiteData,
                    includeChatHistory: viewModel.includeChatHistory,
                    selectedCookieDomains: viewModel.selectedCookieDomainsForScope,
                    selectedVisits: viewModel.historyVisits
                )
                onConfirm?(.burn(options: result))
                dismiss()
            } label: {
                Text(UserText.delete)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(DestructiveActionButtonStyle(enabled: isDeleteEnabled, topPadding: 0, bottomPadding: 0))
            .disabled(!isDeleteEnabled)
            .accessibilityLabel(UserText.delete)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("FireDialogView.burnButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

}

// Corner radius configuration for section rows
private enum RowCornerRadius {
    case top
    case bottom
    case both
    case none
}

// Modifier to apply corner clipping based on row position
private struct RowCornerClipModifier: ViewModifier {
    let cornerRadius: RowCornerRadius

    func body(content: Content) -> some View {
        switch cornerRadius {
        case .none:
            content
        case .top:
            content.clipShape(CustomRoundedCornersShape(tl: 8, tr: 8, bl: 0, br: 0))
        case .bottom:
            content.clipShape(CustomRoundedCornersShape(tl: 0, tr: 0, bl: 8, br: 8))
        case .both:
            content.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// Row with press effect - visual feedback without blocking child interactions
private struct RowWithPressEffect<Content: View>: View {
    let cornerRadius: RowCornerRadius
    let isEnabled: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var showFeedback = false

    var body: some View {
        ZStack {
            // Visual feedback overlay
            pressBackground
                .opacity(showFeedback ? 1 : 0)
                .allowsHitTesting(false)

            content()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEnabled {
                // Quick flash animation
                showFeedback = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    showFeedback = false
                    DispatchQueue.main.async {
                        action()
                    }
                }
            }
        }
        .animation(.easeOut(duration: showFeedback ? 0.06 : 0.12), value: showFeedback)
        .modifier(RowCornerClipModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var pressBackground: some View {
        let background = Color.buttonMouseDown

        switch cornerRadius {
        case .top:
            CustomRoundedCornersShape(tl: 12, tr: 12, bl: 0, br: 0)
                .fill(background)
        case .bottom:
            CustomRoundedCornersShape(tl: 0, tr: 0, bl: 12, br: 12)
                .fill(background)
        case .both:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
        case .none:
            Rectangle()
                .fill(background)
        }
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
private class MockAIChatHistoryCleaner: AIChatHistoryCleaning {
    var shouldDisplayCleanAIChatHistoryOption: Bool = true
    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        Just(shouldDisplayCleanAIChatHistoryOption).eraseToAnyPublisher()
    }
    func cleanAIChatHistory() {}
}
@available(macOS 14.0, *)
#Preview("Fire Dialog", traits: FireDialogView.Constants.viewSize.fixedLayout) {
    let tld = TLD()
    let vm = FireDialogViewModel(
        fireViewModel: FireViewModel(tld: tld, visualizeFireAnimationDecider: NSApp.delegateTyped.visualizeFireSettingsDecider),
        tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
        historyCoordinating: Application.appDelegate.historyCoordinator,
        aiChatHistoryCleaner: MockAIChatHistoryCleaner(),
        fireproofDomains: Application.appDelegate.fireproofDomains,
        faviconManagement: Application.appDelegate.faviconManager,
        tld: tld
    )

    PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm, showIndividualSitesLink: true)
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
        aiChatHistoryCleaner: MockAIChatHistoryCleaner(),
        fireproofDomains: fireproofDomains,
        faviconManagement: faviconMock,
        clearingOption: .allData,
        tld: tld
    )

    return PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm, showSitesOverlay: true, showIndividualSitesLink: true)
    }
}
#endif
