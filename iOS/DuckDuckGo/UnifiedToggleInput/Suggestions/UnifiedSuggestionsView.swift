//
//  UnifiedSuggestionsView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI
import os

/// The single unified suggestions surface for both Search and Duck.ai. Switches on the
/// resolver's content state: list rows / favorites / logo. One view, model decides the rest.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    let header: AnyView?
    /// Built lazily by the host for the `.favorites` state; nil when favorites aren't supported (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?

    var body: some View {
        // The escape hatch is one persistent element above the content — NOT duplicated inside the
        // recents List header and the favorites/logo overlay. Re-creating it across those subtrees
        // on a mode switch made it jump instead of gliding with the input; a single instance rides
        // the inset animation in both directions.
        VStack(spacing: 0) {
            if showsHatch, let header {
                header
                    .padding(.horizontal, Metrics.contentHorizontalMargin)
                    .padding(.top, Metrics.hatchTopInset)
                    .padding(.bottom, Metrics.hatchBottomInset)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    utiTransitionLog.debug("hatch.minY appear=\(proxy.frame(in: .global).minY, privacy: .public)")
                                }
                                .onChange(of: proxy.frame(in: .global).minY) { y in
                                    utiTransitionLog.debug("hatch.minY=\(y, privacy: .public)")
                                }
                        }
                    )
            }
            contentArea
        }
    }

    /// The hatch shows in the non-typing states (favorites / logo / recents), mirroring legacy
    /// `isQueryActive`; the search / duck.ai suggestion lists hide it.
    private var showsHatch: Bool {
        guard header != nil else { return false }
        switch viewModel.content {
        case .favorites, .logo: return true
        case .list(let kind): return kind == .recents
        }
    }

    private var contentArea: some View {
        // The list stays mounted in every state so SwiftUI never recreates it (a fresh `List`
        // flashes its default background before `.scrollContentBackground(.hidden)` applies).
        // Favorites renders on top; the list is hidden + non-interactive beneath it.
        ZStack {
            listLayer
            overlayLayer
        }
    }

    private var isShowingList: Bool {
        if case .list = viewModel.content { return true }
        return false
    }

    /// The kind the mounted list is currently bound to; defaults to `.search` when idle so the
    /// list holds a stable (empty) view-model rather than being torn down.
    private var activeListKind: SuggestionsListSourceKind {
        if case .list(let kind) = viewModel.content { return kind }
        return .search
    }

    private var listLayer: some View {
        SuggestionsListView(viewModel: viewModel.listViewModel(for: activeListKind),
                            isAddressBarAtBottom: isAddressBarAtBottom)
            .opacity(isShowingList ? 1 : 0)
            .allowsHitTesting(isShowingList)
    }

    @ViewBuilder
    private var overlayLayer: some View {
        switch viewModel.content {
        case .favorites:
            if let controller = favoritesProvider() {
                SuggestionsFavoritesView(controller: controller)
            }
        case .logo, .list:
            // Logo is drawn by DaxLogoManager; the list fills via listLayer. Nothing to overlay.
            EmptyView()
        }
    }

    private enum Metrics {
        /// Matches the NTP's `sectionsViewHorizontalPadding` (regularPadding) so the hatch and the
        /// suggestion list share the favorites grid's side margins.
        static let contentHorizontalMargin: CGFloat = 24
        /// Matches the NTP's hatch top inset so the chrome hatch lines up with the NTP hatch.
        static let hatchTopInset: CGFloat = 16
        static let hatchBottomInset: CGFloat = 16
    }
}
