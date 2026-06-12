//
//  AIChatHistoryViewController.swift
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

import Combine
import SwiftUI
import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons

final class AIChatHistoryViewController: UIViewController {

    private let viewModel: AIChatHistoryViewModel
    private var cancellables: Set<AnyCancellable> = []

    /// Set while a swipe-driven animation is in flight to suppress reactive reloads that
    /// would otherwise cancel the slide.
    private var isApplyingLocalUpdate = false

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.dataSource = self
        table.delegate = self
        table.register(AIChatHistoryCell.self, forCellReuseIdentifier: AIChatHistoryCell.reuseIdentifier)
        table.register(AIChatHistoryNoResultsCell.self, forCellReuseIdentifier: AIChatHistoryNoResultsCell.reuseIdentifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.sectionHeaderTopPadding = 0
        // Both are needed to keep the `.insetGrouped` rounded bottom corner of the last
        // row stable across trailing swipe-action animations — match Bookmarks' storyboard.
        table.clipsToBounds = true
        table.sectionFooterHeight = 18
        return table
    }()

    private lazy var searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = UserText.aiChatHistorySearchBarPlaceholder
        bar.sizeToFit()
        return bar
    }()

    private lazy var emptyStateHost: UIHostingController<AIChatHistoryEmptyStateView> = {
        let host = UIHostingController(rootView: AIChatHistoryEmptyStateView(viewModel: viewModel))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        return host
    }()

    /// `!loadFailed` so a storage failure (which also clears the lists) routes through the
    /// load-error alert instead of being misread as a no-matches search.
    private var isShowingNoSearchResults: Bool {
        viewModel.isEmpty && !viewModel.effectiveQuery.isEmpty && !viewModel.loadFailed
    }

    init(viewModel: AIChatHistoryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let backgroundColor: UIColor = .systemGroupedBackground
        view.backgroundColor = backgroundColor
        navigationController?.view.backgroundColor = backgroundColor

        title = UserText.actionChats
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: UserText.navigationTitleDone,
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )

        setupViews()
        configureToolbar()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    private func setupViews() {
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        searchBar.delegate = self
        let headerHeight = searchBar.intrinsicContentSize.height
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight))
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            searchBar.topAnchor.constraint(equalTo: headerView.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
        ])
        tableView.tableHeaderView = headerView
    }

    private func configureToolbar() {
        let fire = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.fire,
            style: .plain,
            target: nil,
            action: nil
        )
        let compose = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.compose,
            style: .plain,
            target: self,
            action: #selector(composeButtonTapped)
        )
        let gap = UIBarButtonItem(systemItem: .fixedSpace)
        gap.width = 12
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        let edit = UIBarButtonItem(
            title: UserText.actionGenericEdit,
            style: .plain,
            target: nil,
            action: nil
        )
        toolbarItems = [fire, gap, compose, spacer, edit]
    }

    private func bindViewModel() {
        Publishers.CombineLatest3(viewModel.$pinned, viewModel.$recent, viewModel.$hasLoaded)
            .removeDuplicates { lhs, rhs in lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self, !self.isApplyingLocalUpdate else { return }
                self.refreshContent()
            }
            .store(in: &cancellables)

        // `removeDuplicates` keeps the alert to a single presentation per failure transition.
        viewModel.$loadFailed
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] failed in
                guard failed else { return }
                self?.presentLoadErrorAlert()
            }
            .store(in: &cancellables)
    }

    private func presentLoadErrorAlert() {
        let alert = UIAlertController(
            title: UserText.aiChatHistoryLoadErrorTitle,
            message: UserText.aiChatHistoryLoadErrorMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: UserText.actionOK, style: .default))
        present(alert, animated: true)
    }

    private func refreshContent() {
        guard viewModel.hasLoaded else {
            tableView.isHidden = true
            navigationController?.setToolbarHidden(true, animated: false)
            return
        }
        // Hero empty state only when there are no chats AND no search active. A no-matches
        // search keeps the table (and its search-bar header) visible so the user can clear.
        if viewModel.isEmpty && viewModel.effectiveQuery.isEmpty {
            showEmptyState()
        } else {
            showList()
        }
    }

    private func showEmptyState() {
        guard emptyStateHost.parent == nil else { return }
        tableView.isHidden = true
        navigationController?.setToolbarHidden(true, animated: false)

        addChild(emptyStateHost)
        view.addSubview(emptyStateHost.view)
        NSLayoutConstraint.activate([
            emptyStateHost.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        emptyStateHost.didMove(toParent: self)
    }

    private func showList() {
        if emptyStateHost.parent != nil {
            emptyStateHost.willMove(toParent: nil)
            emptyStateHost.view.removeFromSuperview()
            emptyStateHost.removeFromParent()
        }
        tableView.isHidden = false
        navigationController?.setToolbarHidden(false, animated: false)
        tableView.reloadData()
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func composeButtonTapped() {
        viewModel.newChatTapped()
    }
}

// MARK: - UITableViewDataSource

extension AIChatHistoryViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        isShowingNoSearchResults ? 1 : viewModel.numberOfSections
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isShowingNoSearchResults ? 1 : viewModel.numberOfRows(in: section)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if isShowingNoSearchResults { return nil }
        guard let title = viewModel.title(forSection: section) else { return nil }
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if isShowingNoSearchResults { return .leastNormalMagnitude }
        return viewModel.title(forSection: section) == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isShowingNoSearchResults {
            return tableView.dequeueReusableCell(withIdentifier: AIChatHistoryNoResultsCell.reuseIdentifier, for: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: AIChatHistoryCell.reuseIdentifier, for: indexPath)
        guard let chatCell = cell as? AIChatHistoryCell else { return cell }
        chatCell.titleLabel.text = viewModel.title(forRowAt: indexPath)
        chatCell.iconImageView.image = viewModel.icon(forRowAt: indexPath)
        return chatCell
    }
}

// MARK: - UITableViewDelegate

extension AIChatHistoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let chatId = viewModel.chatId(forRowAt: indexPath) else { return }
        viewModel.openChat(chatId: chatId)
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatId = viewModel.chatId(forRowAt: indexPath) else { return nil }
        let wasPinned = viewModel.isPinned(chatId: chatId)

        let action = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
            guard let self, let move = self.viewModel.togglePin(chatId: chatId) else {
                completion(false); return
            }
            self.isApplyingLocalUpdate = true
            // Refresh the icon while the cell is still at its source position — `moveRow`
            // keeps the same instance, so it'd otherwise carry the pre-toggle icon.
            if let cell = tableView.cellForRow(at: move.source) as? AIChatHistoryCell {
                cell.iconImageView.image = self.viewModel.icon(forRowAt: move.destination)
            }
            tableView.performBatchUpdates({
                tableView.moveRow(at: move.source, to: move.destination)
            }, completion: { [weak self] _ in
                self?.isApplyingLocalUpdate = false
                // Catch up any reactive emission that fired (and got skipped) while the
                // flag was set — e.g. an FE-driven add/delete that landed mid-animation.
                self?.refreshContent()
                completion(true)
            })
        }
        action.image = DesignSystemImages.Glyphs.Size24.pin
        action.accessibilityLabel = wasPinned
            ? UserText.aiChatHistoryUnpinSwipeAccessibilityLabel
            : UserText.aiChatHistoryPinSwipeAccessibilityLabel
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Resolve chatId now (see `chatId(forRowAt:)` doc) and capture it in the closures.
        guard let chatId = viewModel.chatId(forRowAt: indexPath) else { return nil }

        let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
            self?.viewModel.deleteChat(chatId: chatId)
            completion(true)
        }
        delete.image = DesignSystemImages.Glyphs.Size24.fire
        delete.accessibilityLabel = UserText.aiChatHistoryDeleteSwipeAccessibilityLabel

        let download = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
            self?.viewModel.downloadChat(chatId: chatId)
            completion(true)
        }
        download.image = DesignSystemImages.Glyphs.Size24.downloads
        download.accessibilityLabel = UserText.aiChatHistoryDownloadSwipeAccessibilityLabel

        return UISwipeActionsConfiguration(actions: [delete, download])
    }
}

// MARK: - UISearchBarDelegate

extension AIChatHistoryViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.updateQuery(searchText)
    }
}
