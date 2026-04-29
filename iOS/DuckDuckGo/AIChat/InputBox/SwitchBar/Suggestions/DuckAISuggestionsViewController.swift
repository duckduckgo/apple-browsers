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
import DesignResourcesKit
import DesignResourcesKitIcons
import Suggestions
import UIKit

protocol DuckAISuggestionsViewControllerDelegate: AnyObject {
    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion)
    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion)
    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String)
}

/// Three-section suggestions list shown beneath the Duck.ai-mode input.
/// Sections: recent chats / top URL hits / "Search DuckDuckGo" send-to-search row.
/// The "Search DuckDuckGo" row is symmetric with the Search-side "Ask privately" row.
@MainActor
final class DuckAISuggestionsViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case chats
        case urls
        case search
    }

    private enum Constants {
        static let cellIdentifier = "DuckAISuggestionsCell"
        // Match Search-side autocomplete styling.
        static let iconSize: CGFloat = 24
        static let iconTextSpacing: CGFloat = 10
        static let cellHeight: CGFloat = 44
        static let cellHeightWithSubtitle: CGFloat = 58
        static let horizontalInset: CGFloat = 16
        static let topContentInset: CGFloat = -20
    }

    weak var delegate: DuckAISuggestionsViewControllerDelegate?

    private let chatViewModel: AIChatSuggestionsViewModel
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let queryProvider: () -> String

    /// Debounce sized to absorb the gap between chat-fetcher and URL-fetcher settle times so a
    /// single reload renders both. Smaller and one fetcher's slower result triggers a second reload.
    private static let reloadCoalesceMilliseconds = 120

    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .insetGrouped)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.delegate = self
        t.dataSource = self
        t.alwaysBounceVertical = true
        t.keyboardDismissMode = .onDrag
        t.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        t.backgroundColor = UIColor(designSystemColor: .background)
        t.separatorInset = UIEdgeInsets(top: 0, left: Constants.horizontalInset + Constants.iconSize + Constants.iconTextSpacing, bottom: 0, right: 0)
        t.sectionFooterHeight = 0
        t.contentInset = UIEdgeInsets(top: Constants.topContentInset, left: 0, bottom: 0, right: 0)
        return t
    }()

    private var chats: [AIChatSuggestion] { chatViewModel.filteredSuggestions }
    private var urls: [Suggestion] { urlLoader.topURLs }
    private var hasSearchRow: Bool { !queryProvider().isEmpty }

    init(chatViewModel: AIChatSuggestionsViewModel,
         urlLoader: DuckAIURLSuggestionsLoader,
         queryProvider: @escaping () -> String) {
        self.chatViewModel = chatViewModel
        self.urlLoader = urlLoader
        self.queryProvider = queryProvider
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
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        // Reload only on fetcher settle. Text changes alone would fire a reload that renders
        // stale fetcher data with the new search-row title, briefly showing inconsistent state.
        // The fetchers themselves debounce the text publisher, so any text change ultimately
        // triggers a reload via this pipeline (~150–200ms later) — same lag as Search-side.
        let chatChanges = chatViewModel.$filteredSuggestions.map { _ in () }.eraseToAnyPublisher()
        let urlChanges = urlLoader.$topURLs.map { _ in () }.eraseToAnyPublisher()
        Publishers.MergeMany([chatChanges, urlChanges])
            .debounce(for: .milliseconds(Self.reloadCoalesceMilliseconds), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
            .store(in: &cancellables)
    }

    /// Empty sections are excluded so `insetGrouped` doesn't reserve their header padding
    /// above the first visible section. Recomputed on every datasource/delegate read so
    /// UITableView's relayout passes (which sometimes call delegate methods with the old
    /// index path) always see consistent data.
    private var liveSections: [Section] {
        var sections: [Section] = []
        if !chats.isEmpty { sections.append(.chats) }
        if !urls.isEmpty { sections.append(.urls) }
        if hasSearchRow { sections.append(.search) }
        return sections
    }

    private func reload() {
        guard isViewLoaded else { return }
        UIView.performWithoutAnimation {
            tableView.reloadData()
        }
    }

    // MARK: - Cell config

    private func configureChatCell(_ cell: UITableViewCell, with chat: AIChatSuggestion) {
        let icon = chat.isPinned ? DesignSystemImages.Glyphs.Size24.pin : DesignSystemImages.Glyphs.Size24.aiChat
        applyConfiguration(to: cell, title: chat.title, subtitle: nil, icon: icon)
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
    }
}

extension DuckAISuggestionsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { liveSections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let live = liveSections
        guard section < live.count else { return 0 }
        switch live[section] {
        case .chats: return chats.count
        case .urls: return urls.count
        case .search: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)
        let live = liveSections
        guard indexPath.section < live.count else { return cell }
        switch live[indexPath.section] {
        case .chats:
            guard indexPath.row < chats.count else { return cell }
            configureChatCell(cell, with: chats[indexPath.row])
        case .urls:
            guard indexPath.row < urls.count else { return cell }
            configureURLCell(cell, with: urls[indexPath.row])
        case .search:
            configureSearchCell(cell, query: queryProvider())
        }
        return cell
    }
}

extension DuckAISuggestionsViewController: UITableViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.window?.endEditing(true)
    }

    // UITableView occasionally invokes delegate methods with index paths from the previous
    // data set (e.g. during animated relayout passes), so each method tolerates a stale index
    // by returning a safe default.
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let live = liveSections
        guard indexPath.section < live.count else { return Constants.cellHeight }
        switch live[indexPath.section] {
        case .chats:
            return Constants.cellHeight
        case .urls:
            // `.website` renders without a subtitle; everything else has one.
            guard indexPath.row < urls.count else { return Constants.cellHeight }
            switch urls[indexPath.row] {
            case .website: return Constants.cellHeight
            default: return Constants.cellHeightWithSubtitle
            }
        case .search:
            return Constants.cellHeightWithSubtitle
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 0 }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 0 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let live = liveSections
        guard indexPath.section < live.count else { return }
        switch live[indexPath.section] {
        case .chats:
            guard indexPath.row < chats.count else { return }
            delegate?.duckAISuggestionsDidSelectChat(chats[indexPath.row])
        case .urls:
            guard indexPath.row < urls.count else { return }
            delegate?.duckAISuggestionsDidSelectURL(urls[indexPath.row])
        case .search:
            delegate?.duckAISuggestionsDidSelectSearchDuckDuckGo(query: queryProvider())
        }
    }
}
