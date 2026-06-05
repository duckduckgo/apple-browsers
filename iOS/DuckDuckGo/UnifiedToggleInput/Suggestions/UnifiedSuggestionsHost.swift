//
//  UnifiedSuggestionsHost.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.

import Combine
import SwiftUI
import UIKit

/// Hosts the SwiftUI `UnifiedSuggestionsView` for any UTI surface (Duck.ai, Search). Parameterized
/// by `UnifiedSuggestionsHostConfig` so the host is surface-agnostic. Dax logo stays driven by
/// `DaxLogoManager`.
@MainActor
final class UnifiedSuggestionsHost {

    var onContentChanged: (() -> Void)?

    private let config: UnifiedSuggestionsHostConfig
    private let listViewModel: SuggestionsListViewModel
    private let viewModel: UnifiedSuggestionsViewModel
    private var hostingController: UIHostingController<UnifiedSuggestionsView>?
    private var escapeHatchModel: EscapeHatchModel?
    private var cancellables = Set<AnyCancellable>()

    init(config: UnifiedSuggestionsHostConfig) {
        self.config = config
        self.listViewModel = SuggestionsListViewModel(source: config.source)
        self.viewModel = UnifiedSuggestionsViewModel(
            inputsPublisher: config.inputsPublisher,
            listViewModel: listViewModel
        )
    }

    // MARK: - Container-facing surface

    var hasContent: Bool { config.hasContent() }

    func hasSettled(forQuery query: String) -> Bool { config.hasSettled(query) }

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard hostingController == nil else { return }

        config.onStart()

        listViewModel.onSelect = { [weak self] id in self?.config.onSelectRow(id) }
        listViewModel.onTapAhead = { [weak self] id in self?.config.onTapAheadRow(id) }
        listViewModel.onDelete = { [weak self] id in self?.config.onDeleteRow(id) }

        viewModel.$content
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)

        let view = UnifiedSuggestionsView(
            viewModel: viewModel,
            isAddressBarAtBottom: config.isAddressBarAtBottom,
            header: makeHeader(),
            favoritesProvider: config.favoritesProvider)
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        parentViewController.addChild(hosting)
        containerView.addSubview(hosting.view)
        // The SwiftUI List needs a definite height or it collapses; pin the bottom to the
        // keyboard guide (mirrors the legacy DuckAISuggestionsViewController table pinning).
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: containerView.keyboardLayoutGuide.topAnchor)
        ])
        hosting.didMove(toParent: parentViewController)
        hostingController = hosting
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        escapeHatchModel = model
        rebuildRootView()
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        hostingController?.additionalSafeAreaInsets.top = inset
    }

    /// No-op: visibility gating is handled by `DaxLogoManager` + `hasContent`/`hasSettled`.
    func setIsVisibleContent(_ visible: Bool) {}

    func tearDown() {
        cancellables.removeAll()
        onContentChanged = nil
        config.onTearDown()
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
    }

    // MARK: - Private

    private func makeHeader() -> AnyView? {
        guard let escapeHatchModel else { return nil }
        return AnyView(EscapeHatchView(model: escapeHatchModel))
    }

    private func rebuildRootView() {
        guard let hosting = hostingController else { return }
        hosting.rootView = UnifiedSuggestionsView(
            viewModel: viewModel,
            isAddressBarAtBottom: config.isAddressBarAtBottom,
            header: makeHeader(),
            favoritesProvider: config.favoritesProvider)
    }
}
