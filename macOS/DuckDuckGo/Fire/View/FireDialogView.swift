//
//  FireDialogView.swift
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

import AIChat
import AppKit
import Common
import FoundationExtensions
import DesignResourcesKit
import DesignResourcesKitIcons
import History
import Lottie
import SwiftUI
import SwiftUIExtensions
import BrowserServicesKit
import Combine

@MainActor
struct FireDialogView: ModalView {

    enum Response {
        case noAction
        case burn(options: FireDialogResult?)
    }

    fileprivate enum Constants {
        static let viewSize = CGSize(width: 428, height: 592)
        static let footerReservedHeight: CGFloat = 52
        static let toolbarHorizontalPadding: CGFloat = AppVersion.isLiquidGlassSupported ? 20 : 16
        static let horizontalPadding: CGFloat = AppVersion.isLiquidGlassSupported ? 24 : 16
        static let bottomPadding: CGFloat = AppVersion.isLiquidGlassSupported ? 24 : 16
        static let boxContentPadding: CGFloat = 16
        static var sectionRowWidth: CGFloat { viewSize.width - 2 * horizontalPadding - 2 * boxContentPadding }
    }

    @State private var viewHeight: CGFloat = Constants.viewSize.height

    private var tabsSubtitle: String {
        switch viewModel.clearingOption {
        case .currentTab:
            return UserText.fireDialogCloseThisTabAfterDeleting
        case .currentWindow, // current window is pending removal, not supported by the simplified fire dialog, and defaults to burning all data.
                .allData:
            return UserText.fireDialogCloseAllTabsWindowsAfterDeleting
        }
    }

    @ObservedObject var viewModel: FireDialogViewModel
    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    private let style = FireDialogStyle.current
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
    @State private var isSectionsExpanded: Bool = false

    init(viewModel: FireDialogViewModel,
         showSitesOverlay: Bool = false, // for Previews - @State flag to show "sites to be removed" overlay
         onConfirm: ((FireDialogView.Response) -> Void)? = nil) {
        self.viewModel = viewModel
        self._isShowingSitesOverlay = State(initialValue: showSitesOverlay)
        self.onConfirm = onConfirm
    }

    private var isIncludeHistoryEnabled: Bool {
        viewModel.historyItemsCountForCurrentScope > 0
    }

    private var isIncludeCookiesAndSiteDataEnabled: Bool {
        viewModel.cookiesSitesCountForCurrentScope > 0
    }

    private var historyDetail: String {
        let count = viewModel.historyItemsCountForCurrentScope
        return count > 0 ? UserText.fireDialogHistoryItemsDetail(count) : UserText.none
    }

    private var cookiesDetail: String {
        let count = viewModel.cookiesSitesCountForCurrentScope
        return count > 0 ? UserText.fireDialogCookiesSitesDetail(count) : UserText.none
    }

    private var chatsDetail: String {
        let count = viewModel.chatsCountForCurrentScope
        return count > 0 ? UserText.fireDialogChatsCountDetail(count) : UserText.none
    }

    private var isDeleteEnabled: Bool {
        (viewModel.mode.shouldShowCloseTabsToggle && viewModel.includeTabsAndWindows)
        || (viewModel.includeHistory && isIncludeHistoryEnabled)
        || (viewModel.includeCookiesAndSiteData && isIncludeCookiesAndSiteDataEnabled)
        || viewModel.includeChatHistory
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                VStack(spacing: 24) {
                    headerView
                        .padding(.top, 14) // presenter sheet crops the padding 🤷‍♂️
                        .accessibilityHidden(isShowingSitesOverlay)

                    VStack(spacing: 16) {
                        if viewModel.mode.shouldShowSegmentedControl {
                            segmentedControlView
                                .accessibilityHidden(isShowingSitesOverlay)
                        }
                        VStack(spacing: 0) {
                            detailsDisclosureView
                                .accessibilityHidden(isShowingSitesOverlay)
                            if isSectionsExpanded {
                                sectionsView
                            }
                        }
                    }
                    .padding(Constants.boxContentPadding)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .inset(by: 0.5)
                            .stroke(Color(designSystemColor: .containerBorderPrimary), lineWidth: 1)
                    )
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .background(alignment: .topTrailing) {
                    moreOptionsMenu
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel(UserText.fireDialogMoreOptions)
                        .accessibilityIdentifier("FireDialogView.toolbarMoreButton")
                        .padding(.top, 16)
                        .padding(.trailing, Constants.toolbarHorizontalPadding)

                }

                footerView
                    .zIndex(10)
                    .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
            }
            .readSize { size in
                // Set exact content height to avoid content shifting and animation jumping when sheet resizes
                viewHeight = size.height
            }

            // Sites Overlay — spans the full dialog height (incl. footer) so it fully covers the footer
            if isShowingSitesOverlay {
                // Scrim fades independently and stays above content
                Color.black.opacity(0.35)
                    .zIndex(9)

                VStack(spacing: 0) {
                    Spacer(minLength: 62)

                    sitesOverlay
                }
                .zIndex(11)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: NSAnimationContext.current.duration),
                   value: isAnimatingSitesOverlay)
        .frame(width: Constants.viewSize.width, height: viewHeight, alignment: .top)
        .background(Color(designSystemColor: .surfaceSecondary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(viewModel.mode.dialogTitle)
    }

    private var moreOptionsMenuDotsIcon: some View {
        Image(nsImage: DesignSystemImages.Glyphs.Size16.menuDots)
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundColor(Color(designSystemColor: .iconsSecondary))
    }

    @ViewBuilder
    private var moreOptionsMenu: some View {
        if #available(macOS 13.0, *) {
            // `.button` menu style adopts the ambient button style, preserving the
            // toolbar button's pressed state (see the sibling close button).
            Menu {
                moreOptionsMenuItems
            } label: {
                moreOptionsMenuDotsIcon
            }
            .menuStyle(.button)
            .buttonStyle(
                StandardButtonStyle(topPadding: 4,
                                    bottomPadding: 4,
                                    horizontalPadding: 4,
                                    backgroundColor: .clear,
                                    backgroundPressedColor: Color(designSystemColor: .controlsFillSecondary))
            )
            .clipShape(Circle())
        } else {
            Menu {
                moreOptionsMenuItems
            } label: {
                moreOptionsMenuDotsIcon
                    .padding(4)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private var moreOptionsMenuItems: some View {
        Button {
            viewModel.openNewFireWindow()
        } label: {
            HStack {
                Image(nsImage: DesignSystemImages.Glyphs.Size12.fireWindow)
                Text(UserText.newBurnerWindowMenuItem)
            }
        }
        .accessibilityIdentifier("FireDialogView.moreOptions.newFireWindow")

        Divider()

        Button {
            viewModel.toggleCurrentSiteFireproofing()
        } label: {
            Text(viewModel.isCurrentSiteFireproof ? UserText.removeFireproofing : UserText.fireproofSite)
        }
        .disabled(!viewModel.canFireproofCurrentSite)
        .accessibilityIdentifier("FireDialogView.moreOptions.fireproofSite")

        Button {
            viewModel.showManageFireproofSites()
        } label: {
            Text(UserText.manageFireproofSites)
        }
        .accessibilityIdentifier("FireDialogView.moreOptions.manageFireproofSites")

        Divider()

        Button {
            viewModel.deleteIndividualSites()
        } label: {
            Text(UserText.fireDialogMenuDeleteIndividualSites)
        }
        .accessibilityIdentifier("FireDialogView.moreOptions.deleteIndividualSites")

        Divider()

        Button {
            viewModel.openDataDeletionSettings()
        } label: {
            HStack {
                Image(nsImage: DesignSystemImages.Glyphs.Size12.settings)
                Text(UserText.fireDialogMenuDataDeletionSettings)
            }
        }
        .accessibilityIdentifier("FireDialogView.moreOptions.dataDeletionSettings")
    }

    private var headerView: some View {
        VStack(spacing: 6) {
            FirePictogramAnimation(isAppRebranded: themeManager.isAppRebranded)
                .frame(width: 72, height: 72)
                .padding(.top, 8)

            Text(viewModel.mode.dialogTitle)
                .multilineText()
                .multilineTextAlignment(.center)
                .font(.system(size: 15).weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .accessibilityIdentifier("FireDialogView.title")
        }
        .padding(.top, 16)
    }

    private var segmentedControlView: some View {
        FireDialogTabsContainer(
            selection: Binding(
                get: { viewModel.clearingOption.rawValue },
                set: { viewModel.clearingOption = FireDialogViewModel.ClearingOption(rawValue: $0) ?? .allData }
            ),
            tabs: [
                FireDialogTabItem(id: FireDialogViewModel.ClearingOption.currentTab.rawValue, title: UserText.fireDialogModeFromThisTab, image: Image(nsImage: DesignSystemImages.Glyphs.Size16.tabDesktop)),
                FireDialogTabItem(id: FireDialogViewModel.ClearingOption.allData.rawValue, title: UserText.fireDialogModeAllData, image: Image(nsImage: DesignSystemImages.Glyphs.Size16.browser))
            ]
        )
        .accessibilityIdentifier("FireDialogView.segmentedControl")
    }

    private var detailsDisclosureView: some View {
        HStack {
            Text(UserText.fireDialogChooseWhatToDelete)
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: .textSecondary))

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isSectionsExpanded.toggle()
                }
            } label: {
                Image(nsImage: (isSectionsExpanded ? DesignSystemImages.Glyphs.Size24.chevronUpSmall : DesignSystemImages.Glyphs.Size24.chevronDownSmall))
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 12, height: 12)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
                    .padding(6)
                    .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UserText.fireDialogChooseWhatToDelete)
            .accessibilityValue(isSectionsExpanded ? UserText.fireDialogAccessibilityDetailsExpanded : UserText.fireDialogAccessibilityDetailsCollapsed)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("FireDialogView.detailsDisclosureButton")
        }
        .padding(.horizontal, 4)
    }

    private var sectionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: History
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.history,
                title: UserText.fireDialogHistoryTitle,
                detail: historyDetail,
                isOn: Binding {
                    viewModel.includeHistory && isIncludeHistoryEnabled
                } set: {
                    viewModel.includeHistory = $0
                },
                isEnabled: isIncludeHistoryEnabled,
                roundedCorners: .top,
                toggleId: "FireDialogView.historyToggle"
            )
            .accessibilityHidden(isShowingSitesOverlay)
            sectionDivider()

            // Row 2: Cookies and Site Data
            sectionRow(
                icon: DesignSystemImages.Glyphs.Size16.cookie,
                title: UserText.cookiesAndSiteDataTitle,
                subtitle: UserText.fireDialogCookiesSignOutWarning,
                detail: cookiesDetail,
                isOn: Binding { viewModel.includeCookiesAndSiteData && isIncludeCookiesAndSiteDataEnabled } set: { viewModel.includeCookiesAndSiteData = $0 },
                // don‘t make the detail label clickable when there‘s no site data in scope
                detailAction: isIncludeCookiesAndSiteDataEnabled ? { isShowingSitesOverlay = true } : nil,
                // grey-out the detail label when the toggle is Off
                detailActionEnabled: viewModel.includeCookiesAndSiteData,
                isEnabled: isIncludeCookiesAndSiteDataEnabled,
                roundedCorners: viewModel.mode.shouldShowFireproofSection ? .none : .bottom,
                toggleId: "FireDialogView.cookiesToggle"
            )
            .disabled(!isIncludeCookiesAndSiteDataEnabled)
            .accessibilityHidden(isShowingSitesOverlay)

            if viewModel.shouldShowChatHistoryToggle {
                sectionDivider()

            // Row 3: Chat History
                sectionRow(
                    icon: DesignSystemImages.Glyphs.Size16.aiChat,
                    title: UserText.fireDialogChatHistoryTitle,
                    detail: chatsDetail,
                    isOn: $viewModel.includeChatHistorySetting,
                    toggleId: "FireDialogView.chatsToggle"
                )
                .accessibilityHidden(isShowingSitesOverlay)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, -10)
        .fixedSize(horizontal: false, vertical: true)
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
                    .buttonStyle(
                        StandardButtonStyle(topPadding: 6,
                                            bottomPadding: 6,
                                            horizontalPadding: 6,
                                            backgroundColor: Color(designSystemColor: .controlsFillPrimary),
                                            backgroundPressedColor: Color(designSystemColor: .controlsFillPrimary))
                    )
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
                .fill(Color(designSystemColor: .surfaceSecondary))
        )
    }

    private func sectionRow(icon: NSImage, title: String, subtitle: String? = nil, detail: String? = nil, isOn: Binding<Bool>, detailAction: (() -> Void)? = nil, detailActionEnabled: Bool = true, isEnabled: Bool = true, roundedCorners: RowCornerRadius = .none, toggleId: String) -> some View {
        RowWithPressEffect(roundedCorners: roundedCorners, rowCornerRadius: style.rowCornerRadius, isEnabled: isEnabled) {
            guard isEnabled else { return }
            isOn.wrappedValue.toggle()
        } content: {
            HStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(nsImage: icon)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(3)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .accessibilityValue(subtitle ?? detail ?? "")
                .accessibilityAddTraits(.updatesFrequently)

                Spacer()

                HStack(spacing: 8) {
                    if let detail {
                        SectionRowDetailLabel(
                            text: detail,
                            action: detailAction,
                            isEnabled: detailActionEnabled,
                            accessibilityIdentifier: "FireDialogView.cookiesDetailButton"
                        )
                    }

                    Toggle(isOn: isOn)
                        .toggleStyle(FireToggleStyle(onFill: style.knobFillColor, knobFill: Color(designSystemColor: .accentContentPrimary)))
                        .accessibilityLabel(title)
                        .accessibilityIdentifier(toggleId)
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 4)
            .frame(width: Constants.sectionRowWidth, alignment: .leading)
        }
    }

    private func sectionDivider(padding: CGFloat = 4) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(designSystemColor: .containerBorderPrimary)).frame(height: 1)
                .padding(.horizontal, padding)
        }
    }

    /// A section row's trailing detail text (e.g. "6 sites"). When `action` is provided, it
    /// becomes clickable: a pill-shaped background fades in on hover, with a pointing-hand cursor.
    private struct SectionRowDetailLabel: View {
        let text: String
        let action: (() -> Void)?
        var isEnabled: Bool = true
        var accessibilityIdentifier: String?

        @State private var isHovered = false

        var body: some View {
            if let action {
                Button(action: action) {
                    label
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .onHover { isHovered = $0 }
                .cursor(.pointingHand)
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
            } else {
                label
            }
        }

        private var label: some View {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(isHovered && isEnabled ? Color(designSystemColor: .buttonsSecondaryFillDefault) : Color.clear)
                )
                .opacity(action != nil && !isEnabled ? 0.4 : 1.0)
        }
    }

    private var individualSitesColor: NSColor {
        style.individualSitesColor
    }

    private var deleteButtonBackground: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(singleUseColor: .fireButtonGradientStart), location: 0.116),
                .init(color: Color(singleUseColor: .fireButtonGradientEnd), location: 1.0)
            ],
            startPoint: UnitPoint(x: 0, y: 0.37),
            endPoint: UnitPoint(x: 1, y: 0.63)
        )
    }

    private var deleteButtonPressedBackground: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(singleUseColor: .fireButtonPressedGradientStart), location: 0.116),
                .init(color: Color(singleUseColor: .fireButtonPressedGradientEnd), location: 1.0)
            ],
            startPoint: UnitPoint(x: 0, y: 0.37),
            endPoint: UnitPoint(x: 1, y: 0.63)
        )
    }

    private var footerView: some View {

        VStack(alignment: .leading, spacing: 16) {

            if viewModel.mode.shouldShowCloseTabsToggle {
                Toggle(tabsSubtitle, isOn: $viewModel.includeTabsAndWindows)
                    .toggleStyle(.checkbox)
                    .tint(style.knobFillColor)
                    .accessibilityLabel(tabsSubtitle)
                    .accessibilityIdentifier("FireDialogView.tabsToggle")
                    .accessibilityHidden(isShowingSitesOverlay)
                    .font(.system(size: 11))
            }

            // Buttons
            HStack(spacing: 12) {

                Button {
                    onConfirm?(.noAction)
                    dismiss()
                } label: {
                    Text(UserText.cancel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Group {
                                if AppVersion.isLiquidGlassSupported {
                                    Capsule(style: .continuous)
                                        .fill(Color(designSystemColor: .buttonsSecondaryFillDefault))
                                } else {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(designSystemColor: .buttonsSecondaryFillDefault))
                                }
                            }
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
                    Text(viewModel.includeTabsAndWindows ? UserText.fireDialogDeleteAndClose : UserText.delete)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(
                    DestructiveActionButtonStyle(
                        enabled: isDeleteEnabled,
                        topPadding: 0,
                        bottomPadding: 0,
                        background: deleteButtonBackground,
                        pressedBackground: deleteButtonPressedBackground,
                        pillShape: true
                    )
                )
                .disabled(!isDeleteEnabled)
                .accessibilityLabel(viewModel.includeTabsAndWindows ? UserText.fireDialogDeleteAndClose : UserText.delete)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("FireDialogView.burnButton")
                .accessibilityHidden(isShowingSitesOverlay)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.bottom, Constants.bottomPadding)
    }
}

private struct FireDialogStyle {
    let knobFillColor: Color
    let individualSitesColor: NSColor
    let rowCornerRadius: CGFloat
    let segmentedControlCornerRadius: CGFloat
    let segmentedControlItemCornerRadius: CGFloat
    let selectedForeground: Color
    let selectedIconBackground: Color

    private static var `default`: FireDialogStyle {
        FireDialogStyle(knobFillColor: Color(designSystemColor: .accentPrimary),
                        individualSitesColor: NSColor(designSystemColor: .accentTextPrimary),
                        rowCornerRadius: 12,
                        segmentedControlCornerRadius: 12,
                        segmentedControlItemCornerRadius: 10,
                        selectedForeground: Color(designSystemColor: .accentPrimary),
                        selectedIconBackground: Color(designSystemColor: .accentGlowSecondary))
    }

    private static var rebranded: FireDialogStyle {
        FireDialogStyle(knobFillColor: Color(singleUseColor: .fireModeAccent),
                        individualSitesColor: NSColor(designSystemColor: .textPrimary),
                        rowCornerRadius: 16,
                        segmentedControlCornerRadius: 16,
                        segmentedControlItemCornerRadius: 14,
                        selectedForeground: Color(designSystemColor: .accentFirePrimary),
                        selectedIconBackground: Color(designSystemColor: .accentFireGlowSecondary))
    }

    static var current: FireDialogStyle {
        DesignSystemRebrand.isAppRebranded() ? .rebranded : .default
    }
}

// MARK: - Tabs container

private struct FireDialogTabItem: Identifiable {
    let id: Int
    let title: String
    let image: Image
}

private struct FireDialogTabsContainer: View {
    @Binding var selection: Int
    let tabs: [FireDialogTabItem]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs) { tab in
                FireDialogTabButton(tab: tab, isSelected: selection == tab.id) {
                    selection = tab.id
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct FireDialogTabButton: View {
    let tab: FireDialogTabItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(designSystemColor: .accentFirePrimary).opacity(0.12) : Color.clear)
                        .frame(width: 32, height: 32)
                    tab.image
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 16, height: 16)
                        .foregroundColor(isSelected ? Color(designSystemColor: .accentFirePrimary) : Color(designSystemColor: .iconsSecondary))
                }
                .opacity(0.8)

                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? Color(designSystemColor: .accentFirePrimary) : Color(designSystemColor: .textSecondary))
                    .padding(.bottom, -3)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(designSystemColor: .surfaceTertiary) : Color(designSystemColor: .containerFillSecondary))
                    .shadow(color: isSelected ? Color(designSystemColor: .shadowPrimary) : .clear, radius: 4, x: 0, y: 1)
                    .shadow(color: isSelected ? Color(designSystemColor: .shadowTertiary) : .clear, radius: 1, x: 0, y: 0.25)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? UserText.fireDialogAccessibilitySelected : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// Corner radius configuration for section rows
private enum RowCornerRadius {
    case top
    case bottom
    case none
}

// Modifier to apply corner clipping based on row position
private struct RowCornerClipModifier: ViewModifier {
    let roundedCorners: RowCornerRadius
    let roundedCornerRadius: CGFloat

    func body(content: Content) -> some View {
        switch roundedCorners {
        case .none:
            content
        case .top:
            content.clipShape(CustomRoundedCornersShape(tl: roundedCornerRadius, tr: roundedCornerRadius, bl: 0, br: 0))
        case .bottom:
            content.clipShape(CustomRoundedCornersShape(tl: 0, tr: 0, bl: roundedCornerRadius, br: roundedCornerRadius))
        }
    }
}

// Row with press effect - visual feedback without blocking child interactions
private struct RowWithPressEffect<Content: View>: View {
    let roundedCorners: RowCornerRadius
    let rowCornerRadius: CGFloat
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
        .modifier(RowCornerClipModifier(roundedCorners: roundedCorners, roundedCornerRadius: rowCornerRadius))
    }

    @ViewBuilder
    private var pressBackground: some View {
        let background = Color.buttonMouseDown

        switch roundedCorners {
        case .top:
            CustomRoundedCornersShape(tl: rowCornerRadius, tr: rowCornerRadius, bl: 0, br: 0)
                .fill(background)
        case .bottom:
            CustomRoundedCornersShape(tl: 0, tr: 0, bl: rowCornerRadius, br: rowCornerRadius)
                .fill(background)
        case .none:
            Rectangle()
                .fill(background)
        }
    }
}

// MARK: - Fire Pictogram Lottie

/// Loads the fire pictogram Lottie animation.
private struct FirePictogramAnimation: NSViewRepresentable {

    let isAppRebranded: Bool

    private var assetName: String {
        isAppRebranded ? "fire-pictogram-new" : "fire-pictogram"
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        attachAnimation(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func attachAnimation(to container: NSView) {
        guard let animation = LottieAnimation.asset(assetName, bundle: .main) else {
            return
        }
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.animationSpeed = 1.0
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        view.play()
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
    func cleanAIChatHistory() async -> Result<Void, Error> {
        return .success(())
    }
    func allChats() -> [DuckAiChat] {
        []
    }
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
        featureFlagger: Application.appDelegate.featureFlagger,
        tld: tld,
        windowControllersManager: Application.appDelegate.windowControllersManager,
        dataClearingPreferences: Application.appDelegate.dataClearingPreferences,
        pixelFiring: nil
    )

    PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm)
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
        featureFlagger: Application.appDelegate.featureFlagger,
        clearingOption: .allData,
        tld: tld,
        windowControllersManager: Application.appDelegate.windowControllersManager,
        dataClearingPreferences: Application.appDelegate.dataClearingPreferences,
        pixelFiring: nil
    )

    return PreviewView(showWindowTitle: false) {
        FireDialogView(viewModel: vm, showSitesOverlay: true)
    }
}
#endif
