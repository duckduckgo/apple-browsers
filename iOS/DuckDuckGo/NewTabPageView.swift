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

import SwiftUI
import DuckUI
import RemoteMessaging

struct NewTabPageView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.isLandscapeOrientation) var isLandscapeOrientation

    @ObservedObject private var viewModel: NewTabPageViewModel
    @ObservedObject private var messagesModel: NewTabPageMessagesModel
    @ObservedObject private var favoritesViewModel: FavoritesViewModel

    let isFocussedState: Bool
    let narrowLayoutInLandscape: Bool
    let dismissKeyboardOnScroll: Bool

    init(isFocussedState: Bool = false,
         narrowLayoutInLandscape: Bool = false,
         dismissKeyboardOnScroll: Bool = true,
         viewModel: NewTabPageViewModel,
         messagesModel: NewTabPageMessagesModel,
         favoritesViewModel: FavoritesViewModel) {
        self.isFocussedState = isFocussedState
        self.viewModel = viewModel
        self.messagesModel = messagesModel
        self.favoritesViewModel = favoritesViewModel
        self.narrowLayoutInLandscape = narrowLayoutInLandscape
        self.dismissKeyboardOnScroll = dismissKeyboardOnScroll

        self.messagesModel.load()
    }

    private var isShowingSections: Bool {
        !favoritesViewModel.allFavorites.isEmpty
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

private extension NewTabPageView {
    // MARK: - Views
    @ViewBuilder
    private var sectionsView: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: Metrics.sectionSpacing) {
                    escapeHatchSectionView

                    messagesSectionView
                        .padding(.top, Metrics.nonGridSectionTopPadding)
                        .padding(.horizontal, Metrics.updatedNonGridSectionHorizontalPadding)

                    FavoritesView(model: favoritesViewModel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, sectionsViewPadding(in: proxy))
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
            FireModeEmptyStateView(type: .tab,
                                   escapeHatch: viewModel.escapeHatch,
                                   onEscapeHatchTap: viewModel.onEscapeHatchTap)
        } else {
            logoEmptyView
        }
    }
    
    @ViewBuilder
    private var logoEmptyView: some View {
        GeometryReader { proxy in
            ZStack {
                if shouldShowLogoInEmptyState {
                    NewTabPageDaxLogoView()
                }

                ScrollView {
                    VStack(spacing: Metrics.sectionSpacing) {
                        escapeHatchSectionView

                        messagesSectionView
                            .padding(.top, Metrics.nonGridSectionTopPadding)
                            .padding(.horizontal, Metrics.updatedNonGridSectionHorizontalPadding)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.vertical, sectionsViewPadding(in: proxy))
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
        guard messagesModel.homeMessageViewModels.isEmpty else { return false }
        if viewModel.escapeHatch != nil && isLandscapeOrientation { return false }
        if viewModel.escapeHatch != nil && isFocussedState { return false }
        return true
    }

    @ViewBuilder
    private var escapeHatchSectionView: some View {
        if let escapeHatch = viewModel.escapeHatch {
            ReturnToTabCard(model: escapeHatch) {
                viewModel.onEscapeHatchTap?()
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? Metrics.messageMaximumWidthPad : Metrics.messageMaximumWidth)
            .padding(.top, Metrics.nonGridSectionTopPadding)
            .padding(.horizontal, Metrics.updatedNonGridSectionHorizontalPadding)
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

    static let messageMaximumWidth: CGFloat = 380
    static let messageMaximumWidthPad: CGFloat = 455

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

    func refresh() {

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
