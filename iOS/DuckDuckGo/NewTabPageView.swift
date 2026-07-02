//
//  NewTabPageView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import DuckUI
import RemoteMessaging
import SwiftUI
import UIComponents

struct NewTabPageView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.isLandscapeOrientation) var isLandscapeOrientation

    @ObservedObject private var viewModel: NewTabPageViewModel
    @ObservedObject private var messagesModel: NewTabPageMessagesModel
    @ObservedObject private var favoritesViewModel: FavoritesViewModel

    let isFocussedState: Bool
    let narrowLayoutInLandscape: Bool
    let dismissKeyboardOnScroll: Bool
    let layoutConfiguration: NewTabPageLayoutConfiguration

    init(isFocussedState: Bool = false,
         narrowLayoutInLandscape: Bool = false,
         dismissKeyboardOnScroll: Bool = true,
         layoutConfiguration: NewTabPageLayoutConfiguration = .standard,
         viewModel: NewTabPageViewModel,
         messagesModel: NewTabPageMessagesModel,
         favoritesViewModel: FavoritesViewModel) {
        self.isFocussedState = isFocussedState
        self.viewModel = viewModel
        self.messagesModel = messagesModel
        self.favoritesViewModel = favoritesViewModel
        self.narrowLayoutInLandscape = narrowLayoutInLandscape
        self.dismissKeyboardOnScroll = dismissKeyboardOnScroll
        self.layoutConfiguration = layoutConfiguration

        self.messagesModel.load()
    }

    private var isShowingSections: Bool {
        !favoritesViewModel.allFavorites.isEmpty && !viewModel.fireTab
    }

    var body: some View {
        if !viewModel.isOnboarding {
            mainView
                .background(Color(designSystemColor: .background))
                .simultaneousGesture(
                    DragGesture()
                        .onChanged({ value in
                            if value.translation.height != 0.0 {
                                viewModel.beginDragging()
                            }
                        })
                        .onEnded({ _ in viewModel.endDragging() })
                )
        }
    }

    @ViewBuilder
    private var mainView: some View {
        if isShowingSections {
            sectionsView
        } else {
            emptyStateView
        }
    }
}

struct NewTabPageLayoutConfiguration {
    let expandsEscapeHatchToAvailableWidth: Bool
    let escapeHatchHorizontalPadding: CGFloat
    /// When true, the per-section top nudge is folded into the content's top inset, so the favorites
    /// grid sits at the same top inset as the escape hatch. The unified toggle input needs this so the
    /// focused embedded NTP (favorites only) and the unfocused NTP (hatch + favorites) compose alike.
    let favoritesShareHatchTopInset: Bool
    /// Fixed top inset for the content (nil = the width-based default). The unified toggle input pins it
    /// to the focused hatch's distance from the bar so the NTP hatch lands exactly on the focused hatch.
    let contentTopInsetOverride: CGFloat?
    /// Spacing between sections (hatch → favorites). The unified toggle input matches the focused chrome's
    /// reserved hatch-to-content spacing so the NTP favorites land exactly on the focused favorites
    /// (= chrome top inset 6 + bottom inset 16, plus ~4 for the pill-vs-hatch-height difference).
    let interSectionSpacing: CGFloat

    static let standard = NewTabPageLayoutConfiguration(expandsEscapeHatchToAvailableWidth: false,
                                                        escapeHatchHorizontalPadding: Metrics.updatedNonGridSectionHorizontalPadding,
                                                        favoritesShareHatchTopInset: false,
                                                        contentTopInsetOverride: nil,
                                                        interSectionSpacing: Metrics.sectionSpacing)
    static let unifiedToggleInput = NewTabPageLayoutConfiguration(expandsEscapeHatchToAvailableWidth: true,
                                                                  // Aligns the resting hatch with the focused `FocusedChromeView` hatch so it doesn't resize on dismiss.
                                                                  escapeHatchHorizontalPadding: Metrics.updatedNonGridSectionHorizontalPadding,
                                                                  favoritesShareHatchTopInset: true,
                                                                  contentTopInsetOverride: 10,
                                                                  interSectionSpacing: 26)
}

private extension NewTabPageView {
    // MARK: - Views
    @ViewBuilder
    private var sectionsView: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: layoutConfiguration.interSectionSpacing) {
                    escapeHatchSectionView

                    messagesSectionView
                        .padding(.top, sectionTopNudge)
                        .padding(.horizontal, Metrics.updatedNonGridSectionHorizontalPadding)

                    if let title = viewModel.sectionTitle, !title.isEmpty {
                        Text(title)
                            .daxTitle3()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Metrics.sectionTitleTopPadding)
                            .padding(.trailing, Metrics.sectionTitleTrailingPadding)
                    }

                    FavoritesView(model: favoritesViewModel)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(viewModel.isFavoritesHidden ? 0 : 1)
                }
                .padding(.top, contentTopInset(in: proxy))
                .padding(.bottom, sectionsViewPadding(in: proxy))
                .padding(.horizontal, sectionsViewHorizontalPadding(in: proxy))
                .background(Color(designSystemColor: .background))
            }
            .if(dismissKeyboardOnScroll, transform: {
                $0.withScrollKeyboardDismiss()
            })
        }
        .if(dismissKeyboardOnScroll, transform: {
            // Prevent recreating geometry reader when keyboard is shown/hidden.
            $0.ignoresSafeArea(.keyboard)
        })
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if viewModel.fireTab {
            FireModeEmptyStateView(type: .tab)
        } else {
            logoEmptyView
        }
    }
    
    @ViewBuilder
    private var logoEmptyView: some View {
        GeometryReader { proxy in
            ZStack {
                // Anchors the Lottie's geometric center to screen.midY - 55, so the visible duck
                // lands at screen.midY - 72 — the splash storyboard's resting position. The
                // dynamic offset compensates for the NTP body's centerY shifting based on top vs
                // bottom omnibar chrome.
                NewTabPageDaxLogoView()
                    .offset(y: (UIScreen.main.bounds.midY - 55) - proxy.frame(in: .global).midY)
                    .opacity(shouldShowLogoInEmptyState ? 1 : 0)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: layoutConfiguration.interSectionSpacing) {
                        escapeHatchSectionView

                        messagesSectionView
                            .padding(.top, sectionTopNudge)
                            .padding(.horizontal, Metrics.updatedNonGridSectionHorizontalPadding)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, contentTopInset(in: proxy))
                    .padding(.bottom, sectionsViewPadding(in: proxy))
                    .padding(.horizontal, sectionsViewHorizontalPadding(in: proxy))
                }
                .if(dismissKeyboardOnScroll, transform: {
                    $0.withScrollKeyboardDismiss()
                })
            }
        }
        .if(dismissKeyboardOnScroll, transform: {
            $0.ignoresSafeArea(.keyboard)
        })
    }

    private var shouldShowLogoInEmptyState: Bool {
        guard !viewModel.isLogoHidden else { return false }
        guard messagesModel.homeMessageViewModels.isEmpty else { return false }
        if viewModel.escapeHatch != nil && isLandscapeOrientation { return false }
        if viewModel.escapeHatch != nil && isFocussedState { return false }
        return true
    }

    /// The unified toggle input design lets the hatch fill the same content span as favorites.
    /// Legacy NTP keeps its existing max widths so the flag-off UI remains unchanged.
    private var escapeHatchMaxWidth: CGFloat {
        if layoutConfiguration.expandsEscapeHatchToAvailableWidth {
            return .infinity
        }
        if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
            return Metrics.escapeHatchMaximumWidthPad
        }
        return Metrics.messageMaximumWidth
    }

    @ViewBuilder
    private var escapeHatchSectionView: some View {
        if let escapeHatch = viewModel.escapeHatch {
            EscapeHatchView(model: escapeHatch)
                .frame(maxWidth: escapeHatchMaxWidth)
                .padding(.top, sectionTopNudge)
                .padding(.horizontal, layoutConfiguration.escapeHatchHorizontalPadding)
        }
    }

    private var messagesSectionView: some View {
        ForEach(messagesModel.homeMessageViewModels, id: \.messageId) { messageModel in
            HomeMessageView(viewModel: messageModel)
                .frame(maxWidth: horizontalSizeClass == .regular ? Metrics.messageMaximumWidthPad : Metrics.messageMaximumWidth)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func sectionsViewHorizontalPadding(in geometry: GeometryProxy) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .phone, isLandscapeOrientation, narrowLayoutInLandscape {
            return Metrics.increasedHorizontalPadding + Metrics.regularPadding
        } else {
            return geometry.frame(in: .local).width > Metrics.verySmallScreenWidth ? Metrics.regularPadding : Metrics.smallPadding
        }
    }

    private func sectionsViewPadding(in geometry: GeometryProxy) -> CGFloat {
        geometry.frame(in: .local).width > Metrics.verySmallScreenWidth ? Metrics.regularPadding : Metrics.smallPadding
    }

    /// The top nudge applied to each non-grid section, unless folded into the content inset.
    private var sectionTopNudge: CGFloat {
        layoutConfiguration.favoritesShareHatchTopInset ? 0 : Metrics.nonGridSectionTopPadding
    }

    /// Top inset above the content stack. When the section nudge is folded in, the first section —
    /// hatch or favorites — sits at the nudged inset, so favorites align with the hatch. A config can pin
    /// it to a fixed value so the NTP content lands exactly on the focused surface's content.
    private func contentTopInset(in geometry: GeometryProxy) -> CGFloat {
        if let override = layoutConfiguration.contentTopInsetOverride {
            return override
        }
        let folded = layoutConfiguration.favoritesShareHatchTopInset ? Metrics.nonGridSectionTopPadding : 0
        return sectionsViewPadding(in: geometry) + folded
    }
}

private extension View {
    @ViewBuilder
    func withScrollKeyboardDismiss() -> some View {
        if #available(iOS 16, *) {
            scrollDismissesKeyboard(.immediately)
        } else {
            self
        }
    }
}

private struct Metrics {

    static let smallPadding = 12.0
    static let regularPadding = 24.0
    static let increasedHorizontalPadding = 108.0
    static let sectionSpacing = 32.0
    static let nonGridSectionTopPadding = -8.0
    static let updatedNonGridSectionHorizontalPadding = -8.0
    static let sectionTitleTopPadding = -7.0
    static let sectionTitleTrailingPadding = 60.0

    static let messageMaximumWidth: CGFloat = 380
    static let messageMaximumWidthPad: CGFloat = 455
    /// Matches the favorites grid's content width on iPad regular size class (5 cols × 96pt
    /// max item width + 4 × 32pt spacing) so the escape hatch row aligns visually with the grid.
    static let escapeHatchMaximumWidthPad: CGFloat = 608

    static let verySmallScreenWidth: CGFloat = 320
}

// MARK: - Preview

#Preview("Regular") {
    NewTabPageView(
        viewModel: NewTabPageViewModel(fireTab: false),
        messagesModel: NewTabPageMessagesModel(
            homePageMessagesConfiguration: PreviewMessagesConfiguration(
                homeMessages: []
            ),
            messageActionHandler: RemoteMessagingActionHandler(),
            imageLoader: PreviewImageLoader()
        ),
        favoritesViewModel: FavoritesPreviewModel()
    )
}

#Preview("With message") {
    NewTabPageView(
        viewModel: NewTabPageViewModel(fireTab: false),
        messagesModel: NewTabPageMessagesModel(
            homePageMessagesConfiguration: PreviewMessagesConfiguration(
                homeMessages: [
                    HomeMessage.remoteMessage(
                        remoteMessage: RemoteMessageModel(
                            id: "0",
                            surfaces: .newTabPage,
                            content: .small(titleText: "Title", descriptionText: "Description"),
                            matchingRules: [],
                            exclusionRules: [],
                            isMetricsEnabled: false
                        )
                    )
                ]
            ),
            messageActionHandler: RemoteMessagingActionHandler(),
            imageLoader: PreviewImageLoader()
        ),
        favoritesViewModel: FavoritesPreviewModel()
    )
}

#Preview("No favorites") {
    NewTabPageView(
        viewModel: NewTabPageViewModel(fireTab: false),
        messagesModel: NewTabPageMessagesModel(
            homePageMessagesConfiguration: PreviewMessagesConfiguration(
                homeMessages: []
            ),
            messageActionHandler: RemoteMessagingActionHandler(),
            imageLoader: PreviewImageLoader()
        ),
        favoritesViewModel: FavoritesPreviewModel(favorites: [])
    )
}

#Preview("Empty") {
    NewTabPageView(
        viewModel: NewTabPageViewModel(fireTab: false),
        messagesModel: NewTabPageMessagesModel(
            homePageMessagesConfiguration: PreviewMessagesConfiguration(
                homeMessages: []
            ),
            messageActionHandler: RemoteMessagingActionHandler(),
            imageLoader: PreviewImageLoader()
        ),
        favoritesViewModel: FavoritesPreviewModel()
    )
}

private final class PreviewMessagesConfiguration: HomePageMessagesConfiguration {
    private(set) var homeMessages: [HomeMessage]

    init(homeMessages: [HomeMessage]) {
        self.homeMessages = homeMessages
    }

    func refresh(openedAfterIdle: Bool) {

    }

    func didAppear(_ homeMessage: HomeMessage) {
        // no-op
    }

    func dismissHomeMessage(_ homeMessage: HomeMessage) {
        homeMessages = homeMessages.dropLast()
    }
}

private final class PreviewImageLoader: RemoteMessagingImageLoading {
    func prefetch(_ urls: [URL]) {}
    func cachedImage(for url: URL) -> RemoteMessagingImage? { nil }
    func loadImage(from url: URL) async throws -> RemoteMessagingImage {
        throw RemoteMessagingImageLoadingError.invalidImageData
    }
}
