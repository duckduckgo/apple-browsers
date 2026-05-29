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

/// Container for the native Duck.ai chat-history sheet. Owns a UIKit `UITableView`
/// for the populated list and embeds the SwiftUI empty state via `UIHostingController`
/// when the view model has no chats. Mirrors the structure of `BookmarksViewController`:
/// search bar in the table header, system `UIToolbar` at the bottom.
final class AIChatHistoryViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case pinned
        case recent
    }

    private let viewModel: AIChatHistoryViewModel
    private var cancellables: Set<AnyCancellable> = []

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.dataSource = self
        table.delegate = self
        table.register(AIChatHistoryCell.self, forCellReuseIdentifier: AIChatHistoryCell.reuseIdentifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        // Default ~22pt gap between table header and the first section. Figma wants
        // the search bar and PINNED to sit close together.
        table.sectionHeaderTopPadding = 0
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

        // Match the body's grouped-background colour so the nav bar blends with the list
        // — same trick `BookmarksViewController` uses.
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

        Task { await viewModel.loadChats() }
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

        // Search bar lives in the table header. 12pt outer inset visually lines its
        // pill up with the `.insetGrouped` cells below — the system manages the
        // card inset itself; trying to override it via `directionalLayoutMargins`
        // only changes cell *content* margins, not the card position.
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
            target: nil,
            action: nil
        )
        // Fixed gap separates Fire and Compose into their own pills (iOS 26 groups
        // adjacent toolbar items into a single pill by default).
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
        Publishers.CombineLatest(viewModel.$pinned, viewModel.$recent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshContent()
            }
            .store(in: &cancellables)
    }

    private func refreshContent() {
        if viewModel.isEmpty {
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
}

// MARK: - UITableViewDataSource

extension AIChatHistoryViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .pinned: return viewModel.pinned.count
        case .recent: return viewModel.recent.count
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // Title returned for accessibility; visual header is built in `viewForHeaderInSection`.
        title(for: section)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = title(for: section) else { return nil }
        let label = UILabel()
        label.text = title
        // Figma: 13pt SF Pro regular, text-secondary, uppercase, 18pt line height.
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        // Figma: 24pt left padding inside the 16pt content container → 24pt from
        // card's outer edge. Top 16pt, no bottom padding.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        title(for: section) == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    private func title(for section: Int) -> String? {
        switch Section(rawValue: section) {
        case .pinned: return viewModel.pinned.isEmpty ? nil : "PINNED"
        case .recent: return viewModel.recent.isEmpty ? nil : "RECENT"
        case .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AIChatHistoryCell.reuseIdentifier, for: indexPath)
        guard let chatCell = cell as? AIChatHistoryCell else { return cell }
        if let chat = chat(at: indexPath) {
            chatCell.configure(with: chat)
        }
        return chatCell
    }
}

// MARK: - UITableViewDelegate

extension AIChatHistoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Row taps wired in a follow-up.
    }
}

// MARK: - Helpers

private extension AIChatHistoryViewController {

    func chat(at indexPath: IndexPath) -> ChatItem? {
        switch Section(rawValue: indexPath.section) {
        case .pinned: return viewModel.pinned[safe: indexPath.row]
        case .recent: return viewModel.recent[safe: indexPath.row]
        case .none: return nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
