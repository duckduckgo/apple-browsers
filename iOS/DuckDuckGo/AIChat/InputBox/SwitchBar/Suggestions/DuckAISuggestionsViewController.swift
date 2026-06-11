//
//  DuckAISuggestionsViewController.swift
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

import AIChat
import Combine
import Core
import DDGSync
import DesignResourcesKit
import DesignResourcesKitIcons
import Suggestions
import SwiftUI
import UIKit
import PrivacyConfig

protocol DuckAISuggestionsViewControllerDelegate: AnyObject {
    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion)
    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion)
    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String)
    func duckAISuggestionsDidRequestChatDeletion(_ chat: AIChatSuggestion, sender: UIViewController, source: UIView)
    func duckAISuggestionsDidRequestURLDeletion(_ suggestion: Suggestion)
    func duckAISuggestionsDidRequestSyncSetup()
}

/// Three-section suggestions list under the Duck.ai-mode input: recent chats / top URL hits / "Search DuckDuckGo" row.
@MainActor
final class DuckAISuggestionsViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case chats
        case urls
        case search
    }

    private enum Constants {
        static let cellIdentifier = "DuckAISuggestionsCell"
        static let iconSize: CGFloat = 24
        static let iconTextSpacing: CGFloat = 10
        static let cellHeight: CGFloat = 44
        static let cellHeightWithSubtitle: CGFloat = 58
        static let horizontalInset: CGFloat = 16
        /// Extra clearance above the natural insetGrouped top padding so the first cell stays below the floating (x) dismiss button.
        static let topContentInset: CGFloat = 12
        static let escapeHatchCardHeight: CGFloat = 56
        static let escapeHatchTopPadding: CGFloat = 14
        static let headerBottomPadding: CGFloat = 24
        static let syncPromoInterCardSpacing: CGFloat = 20
        static let recentChatsHeaderHeight: CGFloat = 48
        /// Gap between the "Recent Chats" title baseline and the first chat cell.
        static let recentChatsHeaderBottomPadding: CGFloat = 24
    }

    struct LayoutConfiguration {
        let tableHorizontalInset: CGFloat
        let escapeHatchHorizontalInset: CGFloat
        let escapeHatchMaxWidth: CGFloat?

        static let standard = LayoutConfiguration(
            tableHorizontalInset: 0,
            escapeHatchHorizontalInset: Constants.horizontalInset,
            escapeHatchMaxWidth: HomeMessageCollectionViewCell.maximumWidth
        )

        static let unifiedToggleInput = LayoutConfiguration(
            tableHorizontalInset: 8,
            escapeHatchHorizontalInset: Constants.horizontalInset,
            escapeHatchMaxWidth: nil
        )
    }

    /// Suppresses the "Recent Chats" section header per the unified-input redesign.
    /// Flip to `true` to restore the header; rendering logic below is preserved.
    private static let areSectionHeadersEnabled = false

    weak var delegate: DuckAISuggestionsViewControllerDelegate?

    private let featureFlagger: FeatureFlagger
    private let chatViewModel: AIChatSuggestionsViewModel
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let queryProvider: () -> String
    private let layoutConfiguration: LayoutConfiguration

    /// Absorbs the gap between the two fetcher debounces so a single reload renders both. Coupled to
    /// `AIChatHistoryManager.Constants.debounceMilliseconds` (150ms) and `DuckAIURLSuggestionsLoader.debounceMilliseconds` (100ms).
    /// Increase if either of those grows. Kept tight (≈ debounce gap + small slack) so fast typing/deleting doesn't visibly lag.
    private static let reloadCoalesceMilliseconds = 80

    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        tableView.register(DuckAISuggestionTableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        tableView.backgroundColor = UIColor(designSystemColor: .background)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: Constants.horizontalInset + Constants.iconSize + Constants.iconTextSpacing, bottom: 0, right: 0)
        // Without this, iPad readable-width pulls cells narrower than the UTI input above.
        tableView.cellLayoutMarginsFollowReadableWidth = false
        // Pin section / cell horizontal insets to 16pt so they line up with the unified input
        // bar's `cardHorizontalMargin` and the escape-hatch card hosted in the table header.
        tableView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        return tableView
    }()

    private var chats: [AIChatSuggestion] { chatViewModel.filteredSuggestions }
    private var urls: [Suggestion] { urlLoader.topURLs }
    private var hasSearchRow: Bool { !queryProvider().isEmpty }

    private struct EscapeHatch: Equatable {
        let model: EscapeHatchModel
        static func == (lhs: EscapeHatch, rhs: EscapeHatch) -> Bool {
            // Identity dedupe: SwiftUI `@ObservedObject` already redraws on the model's `openTabCount` changes,
            // so the hosting-controller rebuild only needs to fire when the hatch identity actually changes.
            lhs.model === rhs.model
        }
    }

    private var escapeHatchHostingController: UIHostingController<EscapeHatchView>?
    private var currentEscapeHatch: EscapeHatch?
    private var additionalTopInset: CGFloat = 0
    /// Hatch is hidden while typing — mirrors Search-side, where the autocomplete view covers the NTP+hatch.
    private var isQueryActive = false

    private let syncService: DDGSyncing?
    private let syncPromoViewModel: AIChatSyncPromoViewModel?
    private var syncPromoHostingController: UIHostingController<AIChatSyncPromoView>?
    private var isVisibleContent = false

    /// Fired when the list transitions from hidden to visible. 
    var onBecameVisible: (() -> Void)?

    init(chatViewModel: AIChatSuggestionsViewModel,
         urlLoader: DuckAIURLSuggestionsLoader,
         queryProvider: @escaping () -> String,
         layoutConfiguration: LayoutConfiguration = .standard,
         syncPromoManager: SyncPromoManaging? = nil,
         syncService: DDGSyncing? = nil,
         syncPromoViewModel: AIChatSyncPromoViewModel? = nil,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.chatViewModel = chatViewModel
        self.urlLoader = urlLoader
        self.queryProvider = queryProvider
        self.layoutConfiguration = layoutConfiguration
        self.syncService = syncService
        self.syncPromoViewModel = syncPromoViewModel
            ?? syncPromoManager.map { AIChatSyncPromoViewModel(syncPromoManager: $0) }
        self.featureFlagger = featureFlagger
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(designSystemColor: .background)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: layoutConfiguration.tableHorizontalInset),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -layoutConfiguration.tableHorizontalInset),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        // Reload on fetcher settle (not text change), so the search-row title and section data update together.
        // `removeDuplicates` on each fetcher's output suppresses redundant emissions of identical data, which
        // otherwise produce a second no-op `reloadData` per keystroke and a visible cell-reflow bump.
        let chatChanges = chatViewModel.$filteredSuggestions.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        let urlChanges = urlLoader.$topURLs.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        Publishers.MergeMany([chatChanges, urlChanges])
            .debounce(for: .milliseconds(Self.reloadCoalesceMilliseconds), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.rebuildHeader()
                self?.reload()
            }
            .store(in: &cancellables)

        syncService?.authStatePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildHeader() }
            .store(in: &cancellables)

        rebuildHeader()
    }

    /// MUST stay computed: UITableView calls delegate methods with stale index paths during animated relayouts.
    private var liveSections: [Section] {
        var sections: [Section] = []
        if !chats.isEmpty { sections.append(.chats) }
        if !urls.isEmpty { sections.append(.urls) }
        if hasSearchRow { sections.append(.search) }
        return sections
    }

    /// Nil for stale paths during animated relayouts.
    private func resolvedSection(at indexPath: IndexPath) -> Section? {
        resolvedSection(at: indexPath.section)
    }

    private func resolvedSection(at section: Int) -> Section? {
        let live = liveSections
        guard section < live.count else { return nil }
        return live[section]
    }

    func reload() {
        guard isViewLoaded else { return }
        UIView.performWithoutAnimation {
            tableView.reloadData()
        }
    }

    /// In-place title refresh for the always-visible "Search DuckDuckGo" row. Avoids `reloadData` so a per-keystroke
    /// reflow doesn't bump cells around as the user types.
    func updateSearchRowTitle() {
        guard isViewLoaded,
              let searchSectionIndex = liveSections.firstIndex(of: .search) else { return }
        let path = IndexPath(row: 0, section: searchSectionIndex)
        guard let cell = tableView.cellForRow(at: path) else { return }
        configureSearchCell(cell, query: queryProvider())
    }

    // MARK: - Escape hatch

    /// No-op on identical model — called repeatedly from container layout/refresh paths.
    func setEscapeHatch(_ model: EscapeHatchModel?) {
        let next: EscapeHatch?
        if let model {
            next = EscapeHatch(model: model)
        } else {
            next = nil
        }
        guard next != currentEscapeHatch else { return }
        currentEscapeHatch = next
        rebuildHeader()
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        guard inset != additionalTopInset else { return }
        additionalTopInset = inset
        updateContentInset()
        updateTableHeader()
    }

    /// Force-reloads so the "Recent Chats" header (gated on `hasSearchRow`) toggles immediately, ahead of the fetcher-settle reload-coalesce.
    func setQueryActive(_ active: Bool) {
        guard active != isQueryActive else { return }
        isQueryActive = active
        rebuildHeader()
        reload()
    }

    func setIsVisibleContent(_ visible: Bool) {
        guard visible != isVisibleContent else { return }
        isVisibleContent = visible
        recordSyncPromoImpressionIfNeeded()
        if visible {
            onBecameVisible?()
        }
    }

    // MARK: - Header (escape hatch + sync promo)

    private var shouldShowSyncPromo: Bool {
        syncPromoViewModel?.shouldShowPromo(isQueryActive: isQueryActive, chatCount: chats.count) ?? false
    }

    private func rebuildHeader() {
        if let existing = escapeHatchHostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
            escapeHatchHostingController = nil
        }
        if let hatch = currentEscapeHatch, !isQueryActive {
            let view = EscapeHatchView(model: hatch.model)
            let hosting = UIHostingController(rootView: view)
            hosting.view.backgroundColor = .clear
            addChild(hosting)
            escapeHatchHostingController = hosting
            hosting.didMove(toParent: self)
        }

        if let existing = syncPromoHostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
            syncPromoHostingController = nil
        }
        if shouldShowSyncPromo {
            let view = AIChatSyncPromoView(
                onCTATap: { [weak self] in self?.handleSyncPromoCTATap() },
                onCloseTap: { [weak self] in self?.handleSyncPromoClose() }
            )
            let hosting = UIHostingController(rootView: view)
            hosting.view.backgroundColor = .clear
            addChild(hosting)
            syncPromoHostingController = hosting
            hosting.didMove(toParent: self)
        }
        updateTableHeader()
        updateContentInset()
    }

    private func updateContentInset() {
        guard isViewLoaded else { return }
        tableView.contentInset = UIEdgeInsets(top: Constants.topContentInset + additionalTopInset, left: 0, bottom: 0, right: 0)
    }

    private func updateTableHeader() {
        guard isViewLoaded else { return }

        let hatchHosting = escapeHatchHostingController
        let promoHosting = syncPromoHostingController

        guard hatchHosting != nil || promoHosting != nil else {
            UIView.performWithoutAnimation { tableView.tableHeaderView = nil }
            return
        }

        // Without this, the SwiftUI hosting views' first layout animates from a default position when (re)mounted.
        UIView.performWithoutAnimation {
            let effectiveTopPadding = Constants.escapeHatchTopPadding + additionalTopInset
            let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
            let availableCardWidth = width - 2 * layoutConfiguration.escapeHatchHorizontalInset
            let cardWidth = layoutConfiguration.escapeHatchMaxWidth.map { min(availableCardWidth, $0) } ?? availableCardWidth

            var hatchHeight: CGFloat = 0
            if let hatchHosting {
                hatchHeight = Constants.escapeHatchCardHeight
                hatchHosting.view.frame.size = CGSize(width: cardWidth, height: hatchHeight)
            }
            var promoHeight: CGFloat = 0
            if let promoHosting {
                let target = CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height)
                promoHeight = promoHosting.view.systemLayoutSizeFitting(
                    target,
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                ).height
                promoHosting.view.frame.size = CGSize(width: cardWidth, height: promoHeight)
            }

            var totalHeight = effectiveTopPadding
            if hatchHeight > 0 { totalHeight += hatchHeight }
            if hatchHeight > 0 && promoHeight > 0 { totalHeight += Constants.syncPromoInterCardSpacing }
            if promoHeight > 0 { totalHeight += promoHeight }
            totalHeight += Constants.headerBottomPadding

            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: totalHeight))
            container.backgroundColor = UIColor(designSystemColor: .background)
            container.autoresizingMask = [.flexibleWidth]

            let cardOriginX = (width - cardWidth) / 2
            var nextY = effectiveTopPadding

            if let hatchHosting {
                hatchHosting.view.frame = CGRect(x: cardOriginX, y: nextY, width: cardWidth, height: hatchHeight)
                hatchHosting.view.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
                container.addSubview(hatchHosting.view)
                nextY += hatchHeight
                if promoHosting != nil { nextY += Constants.syncPromoInterCardSpacing }
            }

            if let promoHosting {
                promoHosting.view.frame = CGRect(x: cardOriginX, y: nextY, width: cardWidth, height: promoHeight)
                promoHosting.view.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
                container.addSubview(promoHosting.view)
                nextY += promoHeight
            }

            tableView.tableHeaderView = container

            recordSyncPromoImpressionIfNeeded()
        }
    }

    private func recordSyncPromoImpressionIfNeeded() {
        syncPromoViewModel?.recordImpressionIfNeeded(
            isVisibleContent: isVisibleContent,
            isPromoVisible: syncPromoHostingController != nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Header view's frame doesn't auto-size with the tableView's width; rebuild on layout.
        let hasHeaderHost = escapeHatchHostingController != nil || syncPromoHostingController != nil
        guard hasHeaderHost,
              let header = tableView.tableHeaderView,
              header.frame.width != tableView.bounds.width else { return }
        updateTableHeader()
    }

    // MARK: - Sync promo callbacks

    private func handleSyncPromoCTATap() {
        if syncPromoViewModel?.handleCTATap() == .requestSyncSetup {
            delegate?.duckAISuggestionsDidRequestSyncSetup()
        }
        rebuildHeader()
    }

    private func handleSyncPromoClose() {
        syncPromoViewModel?.handleCloseTap()
        rebuildHeader()
    }

    // MARK: - Cell config

    private func configureChatCell(_ cell: UITableViewCell, with chat: AIChatSuggestion) {
        let icon = chat.isPinned ? DesignSystemImages.Glyphs.Size24.pin : DesignSystemImages.Glyphs.Size24.aiChat

        applyConfiguration(to: cell, title: chat.title, subtitle: nil, icon: icon)
        configureChatDeleteActionIfNeeded(to: cell, chat: chat)
    }

    private func configureURLCell(_ cell: UITableViewCell, with suggestion: Suggestion) {
        let title: String
        let subtitle: String?
        let icon: UIImage
        switch suggestion {
        case .website(let url):
            title = url.formattedForSuggestion()
            subtitle = nil
            icon = DesignSystemImages.Glyphs.Size24.globe
        case .bookmark(let bookmarkTitle, let url, let isFavorite, _):
            title = bookmarkTitle
            subtitle = url.formattedForSuggestion()
            icon = isFavorite ? DesignSystemImages.Glyphs.Size24.bookmarkFavorite : DesignSystemImages.Glyphs.Size24.bookmark
        case .historyEntry(_, let url, _) where url.isDuckDuckGoSearch:
            title = url.searchQuery ?? ""
            subtitle = UserText.autocompleteSearchDuckDuckGo
            icon = DesignSystemImages.Glyphs.Size24.history
        case .historyEntry(let historyTitle, let url, _):
            title = historyTitle ?? url.formattedForSuggestion()
            subtitle = historyTitle == nil ? nil : url.formattedForSuggestion()
            icon = DesignSystemImages.Glyphs.Size24.history
        case .openTab(let tabTitle, let url, _, _):
            title = tabTitle
            subtitle = "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())"
            icon = DesignSystemImages.Glyphs.Size24.tabsMobile
        case .phrase, .internalPage, .unknown, .askAIChat:
            assertionFailure("DuckAIURLSuggestionsLoader filter must keep only URL-typed suggestions; got \(suggestion)")
            return
        }
        applyConfiguration(to: cell, title: title, subtitle: subtitle, icon: icon)
        configureURLDeleteActionIfNeeded(to: cell, suggestion: suggestion)
    }

    private func configureSearchCell(_ cell: UITableViewCell, query: String) {
        applyConfiguration(
            to: cell,
            title: query,
            subtitle: UserText.autocompleteSearchDuckDuckGo,
            icon: DesignSystemImages.Glyphs.Size24.findSearchSmall
        )
    }

    private func applyConfiguration(to cell: UITableViewCell,
                                    title: String,
                                    subtitle: String?,
                                    icon: UIImage) {
        var config = cell.defaultContentConfiguration()
        config.text = title
        config.textProperties.font = UIFont.daxBodyRegular()
        config.textProperties.color = UIColor(designSystemColor: .textPrimary)
        config.textProperties.numberOfLines = 1
        config.textProperties.lineBreakMode = .byTruncatingTail
        if let subtitle {
            config.secondaryText = subtitle
            config.secondaryTextProperties.font = UIFont.daxFootnoteRegular()
            config.secondaryTextProperties.color = UIColor(designSystemColor: .textSecondary)
            config.secondaryTextProperties.numberOfLines = 1
            config.secondaryTextProperties.lineBreakMode = .byTruncatingTail
        }
        config.image = icon.withRenderingMode(.alwaysTemplate)
        config.imageProperties.tintColor = UIColor(designSystemColor: .icons)
        config.imageProperties.maximumSize = CGSize(width: Constants.iconSize, height: Constants.iconSize)
        config.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: Constants.horizontalInset,
            bottom: 0,
            trailing: Constants.horizontalInset
        )
        config.imageToTextPadding = Constants.iconTextSpacing
        cell.contentConfiguration = config
        cell.backgroundColor = UIColor(designSystemColor: .surface)
        cell.accessoryView = nil
    }
}

private extension DuckAISuggestionsViewController {

    func configureChatDeleteActionIfNeeded(to cell: UITableViewCell, chat: AIChatSuggestion) {
        guard let cell = cell as? DuckAISuggestionTableViewCell else {
            return
        }

        cell.accessoryButtonImage = DesignSystemImages.Glyphs.Size16.fire
        cell.displaysAccessoryButton = featureFlagger.isFeatureOn(.removeChatHistory)
        cell.onAccessoryButtonPressed = { [weak self] source in
            self?.requestChatDeletion(chat: chat, source: source)
        }
    }

    func configureURLDeleteActionIfNeeded(to cell: UITableViewCell, suggestion: Suggestion) {
        guard let cell = cell as? DuckAISuggestionTableViewCell, case .historyEntry = suggestion else {
            return
        }

        cell.accessoryButtonImage = DesignSystemImages.Glyphs.Size16.clear
        cell.displaysAccessoryButton = featureFlagger.isFeatureOn(.removeChatHistory)
        cell.onAccessoryButtonPressed = { [weak self] _ in
            self?.requestURLDeletion(suggestion: suggestion)
        }
    }

    func requestChatDeletion(chat: AIChatSuggestion, source: UIView) {
        delegate?.duckAISuggestionsDidRequestChatDeletion(chat, sender: self, source: source)
    }

    func requestURLDeletion(suggestion: Suggestion) {
        delegate?.duckAISuggestionsDidRequestURLDeletion(suggestion)
    }
}

extension DuckAISuggestionsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { liveSections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch resolvedSection(at: section) {
        case .chats: return chats.count
        case .urls: return urls.count
        case .search: return 1
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)
        switch resolvedSection(at: indexPath) {
        case .chats:
            guard indexPath.row < chats.count else { return cell }
            configureChatCell(cell, with: chats[indexPath.row])
        case .urls:
            guard indexPath.row < urls.count else { return cell }
            configureURLCell(cell, with: urls[indexPath.row])
        case .search:
            configureSearchCell(cell, query: queryProvider())
        case nil:
            break
        }
        return cell
    }
}

extension DuckAISuggestionsViewController: UITableViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.window?.endEditing(true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch resolvedSection(at: indexPath) {
        case .chats:
            return Constants.cellHeight
        case .urls:
            guard indexPath.row < urls.count else { return Constants.cellHeight }
            return Self.urlSuggestionHasSubtitle(urls[indexPath.row])
                ? Constants.cellHeightWithSubtitle
                : Constants.cellHeight
        case .search:
            return Constants.cellHeightWithSubtitle
        case nil:
            return Constants.cellHeight
        }
    }

    /// Mirrors the subtitle logic in `configureURLCell` so cell heights match what's actually rendered.
    private static func urlSuggestionHasSubtitle(_ suggestion: Suggestion) -> Bool {
        switch suggestion {
        case .website: return false
        case .historyEntry(let title, let url, _): return url.isDuckDuckGoSearch || title != nil
        case .bookmark, .openTab: return true
        case .phrase, .internalPage, .unknown, .askAIChat: return false
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard Self.areSectionHeadersEnabled else { return 0 }
        guard resolvedSection(at: section) == .chats, !hasSearchRow else { return 0 }
        return Constants.recentChatsHeaderHeight
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard Self.areSectionHeadersEnabled else { return nil }
        guard resolvedSection(at: section) == .chats, !hasSearchRow else { return nil }
        return makeRecentChatsHeaderView()
    }

    private func makeRecentChatsHeaderView() -> UIView {
        let container = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = UserText.aiChatRecentChatsSectionTitle
        label.font = UIFont.daxTitle3()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -Constants.recentChatsHeaderBottomPadding)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch resolvedSection(at: indexPath) {
        case .chats:
            guard indexPath.row < chats.count else { return }
            delegate?.duckAISuggestionsDidSelectChat(chats[indexPath.row])
        case .urls:
            guard indexPath.row < urls.count else { return }
            delegate?.duckAISuggestionsDidSelectURL(urls[indexPath.row])
        case .search:
            delegate?.duckAISuggestionsDidSelectSearchDuckDuckGo(query: queryProvider())
        case nil:
            break
        }
    }
}
