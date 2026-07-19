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
    private let fireButtonAnimator: FireButtonAnimator
    private var cancellables: Set<AnyCancellable> = []

    private var isRedesignEnabled: Bool { viewModel.isRedesignEnabled }

    /// Set while a swipe-driven animation is in flight to suppress reactive reloads that
    /// would otherwise cancel the slide.
    private var isApplyingLocalUpdate = false

    private var isEditingChats = false
    private weak var fireBarButtonItem: UIBarButtonItem?
    private weak var deleteSelectionItem: UIBarButtonItem?
    private weak var downloadSelectionItem: UIBarButtonItem?

    /// Fire ("Delete All") is offered only over the full list: disabled in edit mode and while a
    /// search filter is active, since the action clears every chat, not just the visible matches.
    private var isFireAllEnabled: Bool {
        !isEditingChats && viewModel.effectiveQuery.isEmpty
    }

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
        // Dismiss the keyboard when the list is dragged, matching system search screens.
        table.keyboardDismissMode = .onDrag
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

    init(viewModel: AIChatHistoryViewModel, fireButtonAnimator: FireButtonAnimator) {
        self.viewModel = viewModel
        self.fireButtonAnimator = fireButtonAnimator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let backgroundColor = UIColor(designSystemColor: .background)
        view.backgroundColor = backgroundColor
        navigationController?.view.backgroundColor = backgroundColor
        tableView.backgroundColor = backgroundColor

        title = UserText.actionChats
        configureNavigationButtons()

        setupViews()
        configureToolbar()
        decorateBarsIfNeeded()
        bindViewModel()

        viewModel.screenDidLoad()
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
        if isRedesignEnabled {
            tableView.allowsMultipleSelectionDuringEditing = true
            tableView.tintColor = UIColor(designSystemColor: .accentPrimary)
        } else {
            installSearchHeader()
        }
    }

    private func installSearchHeader() {
        guard tableView.tableHeaderView == nil else { return }
        let headerHeight = searchBar.intrinsicContentSize.height
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight))
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(searchBar)
        // The table imposes a transient width==0 on the header before it gets its real
        // width; let trailing yield during that pass instead of logging a conflict.
        let searchBarTrailing = searchBar.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12)
        searchBarTrailing.priority = .required - 1
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            searchBarTrailing,
            searchBar.topAnchor.constraint(equalTo: headerView.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
        ])
        tableView.tableHeaderView = headerView
    }

    private func removeSearchHeader() {
        tableView.tableHeaderView = nil
    }

    private lazy var closeBarButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.close,
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )
        item.accessibilityLabel = UserText.keyCommandClose
        return item
    }()

    /// Left: X closes the sheet. Right: Edit toggles edit mode (showing Done while editing).
    private func configureLegacyNavigationButtons() {
        navigationItem.leftBarButtonItem = closeBarButtonItem
        let edit = UIBarButtonItem(
            title: isEditingChats ? UserText.navigationTitleDone : UserText.actionGenericEdit,
            style: isEditingChats ? .done : .plain,
            target: self,
            action: #selector(editButtonTapped)
        )
        if #available(iOS 26, *) {
            edit.style = .plain
        }
        navigationItem.rightBarButtonItem = edit
    }

    /// NavBar: close + search + overflow menu normally; a Done check while selecting.
    private func configureNavigationButtons() {
        guard isRedesignEnabled else {
            configureLegacyNavigationButtons()
            return
        }
        if isEditingChats {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = [makeSelectionDoneItem()]
        } else {
            navigationItem.leftBarButtonItem = closeBarButtonItem
            if #available(iOS 26, *) {
                navigationItem.rightBarButtonItems = [makeOverflowMenuItem(), .fixedSpace(), makeSearchBarButtonItem()]
            } else {
                navigationItem.rightBarButtonItems = [makeOverflowMenuItem(), makeSearchBarButtonItem()]
            }
        }
    }

    private func makeSearchBarButtonItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.findSearchSmall,
            style: .plain,
            target: self,
            action: #selector(searchButtonTapped)
        )
        item.accessibilityLabel = UserText.aiChatHistorySearchAccessibilityLabel
        return item
    }

    private func makeSelectionDoneItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.check.withRenderingMode(.alwaysTemplate),
            style: .done,
            target: self,
            action: #selector(selectionDoneTapped)
        )
        if #available(iOS 26, *) {
            item.style = .prominent
        }
        item.tintColor = UIColor(designSystemColor: .accentPrimary)
        item.accessibilityLabel = UserText.navigationTitleDone
        return item
    }

    private func makeOverflowMenuItem() -> UIBarButtonItem {
        let selectChats = UIAction(
            title: UserText.aiChatHistoryMenuSelectChats,
            image: DesignSystemImages.Glyphs.Size16.checkCircle
        ) { [weak self] _ in
            self?.enterSelectionMode()
        }
        // Chat Protection: later subtask; shown disabled for now.
        let chatProtection = UIAction(
            title: UserText.aiChatHistoryMenuChatProtection,
            image: DesignSystemImages.Glyphs.Size16.shield,
            attributes: .disabled
        ) { _ in }
        let item = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.menuDotsHorizontal,
            menu: UIMenu(children: [selectChats, chatProtection])
        )
        item.accessibilityLabel = UserText.aiChatHistoryMenuAccessibilityLabel
        return item
    }

    /// Pre-iOS 26 sheets default bar button items to the system accent (blue). Match Bookmarks
    /// by applying theme tints; iOS 26 liquid-glass toolbar styling is left to the system.
    private func decorateBarsIfNeeded() {
        if #available(iOS 26, *) { return }
        decorateNavigationBar()
        decorateToolbar()
    }

    private func configureLegacyToolbar() {
        let fire = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.fire,
            style: .plain,
            target: self,
            action: #selector(fireButtonTapped)
        )
        fire.isEnabled = isFireAllEnabled
        let compose = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.compose,
            style: .plain,
            target: self,
            action: #selector(composeButtonTapped)
        )
        compose.isEnabled = !isEditingChats
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbarItems = [fire, spacer, compose]
    }

    /// Redesign: filled fire + "New Chat" pill normally; Delete pill + download while selecting.
    private func configureToolbar() {
        guard isRedesignEnabled else {
            configureLegacyToolbar()
            return
        }
        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        if isEditingChats {
            let delete = makeToolbarItem(
                title: UserText.actionDelete,
                image: DesignSystemImages.Glyphs.Size24.fireSolid,
                action: #selector(deleteSelectedTapped)
            )
            let download = UIBarButtonItem(
                image: DesignSystemImages.Glyphs.Size24.downloads,
                style: .plain,
                target: self,
                action: #selector(downloadSelectedTapped)
            )
            download.accessibilityLabel = UserText.aiChatHistoryDownloadSwipeAccessibilityLabel
            deleteSelectionItem = delete
            downloadSelectionItem = download
            toolbarItems = [delete, spacer, download]
            updateSelectionActionButtons()
        } else {
            let fire = UIBarButtonItem(
                image: DesignSystemImages.Glyphs.Size24.fireSolid,
                style: .plain,
                target: self,
                action: #selector(fireButtonTapped)
            )
            fire.isEnabled = isFireAllEnabled
            let newChat = makeToolbarItem(
                title: UserText.actionNewAIChat,
                image: DesignSystemImages.Glyphs.Size24.compose,
                action: #selector(composeButtonTapped)
            )
            toolbarItems = [fire, spacer, newChat]
        }
    }

    /// Icon+title toolbar button via a custom view (a standard bar item drops the title on iOS 26).
    private func makeToolbarItem(title: String, image: UIImage, action: Selector) -> UIBarButtonItem {
        var config = UIButton.Configuration.plain()
        config.image = image
        config.title = title
        config.imagePadding = 6
        let button = UIButton(configuration: config)
        button.tintColor = UIColor(designSystemColor: .icons)
        button.addTarget(self, action: action, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }

    private func updateSelectionActionButtons() {
        let hasSelection = !(tableView.indexPathsForSelectedRows ?? []).isEmpty
        // Delete stays tappable: "Delete All" with no selection, "Delete" once chats are picked.
        if let deleteButton = deleteSelectionItem?.customView as? UIButton {
            deleteButton.isEnabled = true
            deleteButton.configuration?.title = hasSelection ? UserText.actionDelete : UserText.aiChatHistoryDeleteAll
        }
        downloadSelectionItem?.isEnabled = hasSelection
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

        // Toggle the fire button only when the search transitions empty↔active, not per keystroke.
        viewModel.$effectiveQuery
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureToolbar()
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

    @objc private func searchButtonTapped() {
        if tableView.tableHeaderView != nil {
            hideSearchBarIfNeeded()
        } else {
            installSearchHeader()
            searchBar.becomeFirstResponder()
        }
    }

    @objc private func fireButtonTapped(_ sender: UIBarButtonItem) {
        guard viewModel.totalChatCount > 0 else { return }
        viewModel.fireAllTapped()
        presentDeleteChatsConfirmation(count: viewModel.totalChatCount, attachPopoverTo: sender) { [weak self] in
            self?.burnAllChats()
        }
    }

    /// Shared delete-confirmation sheet; runs `onDelete` once it dismisses. No-op when `count` is 0.
    private func presentDeleteChatsConfirmation(count: Int, attachPopoverTo source: AnyObject, onDelete: @escaping () -> Void) {
        guard count > 0 else { return }
        let presenter = FireConfirmationPresenter()
        presenter.presentFireConfirmation(
            on: self,
            attachPopoverTo: source,
            tabViewModel: nil,
            pixelSource: .browsing,
            fireContext: .deleteChats(count: count, onDelete: { [weak self] in
                self?.dismiss(animated: true) { onDelete() }
            }),
            browsingMode: .normal,
            onConfirm: { _ in },
            onCancel: {}
        )
    }

    /// Plays the fire animation while the view model burns all chats; the list then
    /// reactively falls through to its empty state without dismissing the sheet.
    private func burnAllChats() {
        let viewModel = self.viewModel
        fireButtonAnimator.animate {
            await viewModel.burnAllChats()
        } onTransitionCompleted: {
        } completion: {
        }
    }

    private func burnSelectedChats(chatIds: [String]) {
        let viewModel = self.viewModel
        fireButtonAnimator.animate {
            await viewModel.burnSelectedChats(chatIds: chatIds)
        } onTransitionCompleted: {
        } completion: {
        }
    }

    @objc private func editButtonTapped() {
        if isEditingChats {
            tableView.setEditing(false, animated: true)
            isEditingChats = false
        } else {
            tableView.isEditing = false
            tableView.setEditing(true, animated: true)
            isEditingChats = true
            viewModel.editModeEntered()
        }
        configureToolbar()
        configureNavigationButtons()
    }

    // MARK: - Redesign: multi-select

    private func enterSelectionMode() {
        guard !isEditingChats else { return }
        // Search and multi-select are mutually exclusive: leave search first.
        hideSearchBarIfNeeded()
        isEditingChats = true
        viewModel.editModeEntered()
        // Configure the bars before the edit animation so the Done tint is set up front.
        configureNavigationButtons()
        configureToolbar()
        tableView.setEditing(true, animated: true)
    }

    private func hideSearchBarIfNeeded() {
        guard tableView.tableHeaderView != nil else { return }
        searchBar.text = nil
        searchBar.setShowsCancelButton(false, animated: false)
        searchBar.resignFirstResponder()
        viewModel.updateQuery("")
        removeSearchHeader()
    }

    private func exitSelectionMode() {
        guard isEditingChats else { return }
        isEditingChats = false
        tableView.setEditing(false, animated: true)
        configureNavigationButtons()
        configureToolbar()
    }

    @objc private func selectionDoneTapped() {
        exitSelectionMode()
    }

    @objc private func deleteSelectedTapped() {
        let selectedChatIds = (tableView.indexPathsForSelectedRows ?? [])
            .compactMap { viewModel.chatId(forRowAt: $0) }
        let source: AnyObject = deleteSelectionItem?.customView ?? view
        if selectedChatIds.isEmpty {
            presentDeleteChatsConfirmation(count: viewModel.totalChatCount, attachPopoverTo: source) { [weak self] in
                self?.burnAllChats()
                self?.exitSelectionMode()
            }
        } else {
            presentDeleteChatsConfirmation(count: selectedChatIds.count, attachPopoverTo: source) { [weak self] in
                self?.burnSelectedChats(chatIds: selectedChatIds)
                self?.exitSelectionMode()
            }
        }
    }

    @objc private func downloadSelectedTapped() {
        let selectedChatIds = (tableView.indexPathsForSelectedRows ?? [])
            .compactMap { viewModel.chatId(forRowAt: $0) }
        guard !selectedChatIds.isEmpty else { return }
        viewModel.downloadSelectedChats(chatIds: selectedChatIds)
        exitSelectionMode()
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
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
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
        // In multi-select a tap toggles the row's checkbox instead of opening the chat. Only the
        // redesign selects during editing (legacy leaves selection-during-editing off), so this
        // guard is effectively redesign-only.
        if tableView.isEditing {
            updateSelectionActionButtons()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        guard let chatId = viewModel.chatId(forRowAt: indexPath) else { return }
        viewModel.openChat(chatId: chatId)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateSelectionActionButtons()
        }
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
        action.image = wasPinned ? DesignSystemImages.Glyphs.Size24.unpin : DesignSystemImages.Glyphs.Size24.pin
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

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        if isRedesignEnabled {
            searchBar.setShowsCancelButton(true, animated: false)
        } else {
            searchBar.setShowsCancelButton(true, animated: true)
        }
        viewModel.searchActivated()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.updateQuery(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
        viewModel.updateQuery("")
        // Redesign: cancelling hides the on-demand search bar again.
        if isRedesignEnabled {
            removeSearchHeader()
        }
    }
}
