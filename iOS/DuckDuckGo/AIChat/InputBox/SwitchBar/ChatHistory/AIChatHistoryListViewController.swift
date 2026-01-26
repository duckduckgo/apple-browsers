//
//  AIChatHistoryListViewController.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// A view controller displaying the list of pinned and recent AI chats
final class AIChatHistoryListViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let cellIdentifier = "AIChatHistoryCell"
        static let iconSize: CGFloat = 16
        static let iconTextSpacing: CGFloat = 12
        static let cellHeight: CGFloat = 44
        static let sectionSpacing: CGFloat = 8
        static let horizontalInset: CGFloat = 16
        static let topContentInset: CGFloat = -30
    }

    // MARK: - Section

    private enum Section: Int, CaseIterable {
        case pinned
        case recent
    }

    // MARK: - Properties

    private let viewModel: AIChatSuggestionsViewModel
    private let onChatSelected: (AIChatSuggestion) -> Void
    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        tableView.backgroundColor = UIColor(designSystemColor: .background)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: Constants.horizontalInset + Constants.iconSize + Constants.iconTextSpacing, bottom: 0, right: 0)
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = Constants.sectionSpacing
        tableView.contentInset = UIEdgeInsets(top: Constants.topContentInset, left: 0, bottom: 0, right: 0)
        return tableView
    }()

    private var pinnedChats: [AIChatSuggestion] {
        viewModel.filteredSuggestions.filter { $0.isPinned }
    }

    private var recentChats: [AIChatSuggestion] {
        viewModel.filteredSuggestions.filter { !$0.isPinned }
    }

    // MARK: - Initialization

    init(viewModel: AIChatSuggestionsViewModel, onChatSelected: @escaping (AIChatSuggestion) -> Void) {
        self.viewModel = viewModel
        self.onChatSelected = onChatSelected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        subscribeToViewModel()
    }

    // MARK: - Private Methods

    private func setupView() {
        view.backgroundColor = UIColor(designSystemColor: .background)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func subscribeToViewModel() {
        viewModel.$filteredSuggestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    private func configureCell(_ cell: UITableViewCell, with chat: AIChatSuggestion, isPinned: Bool) {
        var config = cell.defaultContentConfiguration()

        config.text = chat.title
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        config.textProperties.color = UIColor(designSystemColor: .textPrimary)
        config.textProperties.lineBreakMode = .byTruncatingTail
        config.textProperties.numberOfLines = 1

        let icon = isPinned ? DesignSystemImages.Glyphs.Size16.pin : DesignSystemImages.Glyphs.Size16.history
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

// MARK: - UITableViewDataSource

extension AIChatHistoryListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        var count = 0
        if !pinnedChats.isEmpty { count += 1 }
        if !recentChats.isEmpty { count += 1 }
        return count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let actualSection = actualSection(for: section)

        switch actualSection {
        case .pinned:
            return pinnedChats.count
        case .recent:
            return recentChats.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)
        let actualSection = actualSection(for: indexPath.section)

        let chats = actualSection == .pinned ? pinnedChats : recentChats
        guard indexPath.row < chats.count else { return cell }

        let chat = chats[indexPath.row]
        configureCell(cell, with: chat, isPinned: actualSection == .pinned)

        return cell
    }

    private func actualSection(for displaySection: Int) -> Section {
        if pinnedChats.isEmpty {
            return .recent
        }
        if recentChats.isEmpty {
            return .pinned
        }
        return displaySection == 0 ? .pinned : .recent
    }
}

// MARK: - UITableViewDelegate

extension AIChatHistoryListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let actualSection = actualSection(for: indexPath.section)
        let chats = actualSection == .pinned ? pinnedChats : recentChats
        guard indexPath.row < chats.count else { return }

        let chat = chats[indexPath.row]
        onChatSelected(chat)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return Constants.cellHeight
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let totalSections = numberOfSections(in: tableView)
        if section < totalSections - 1 {
            return Constants.sectionSpacing
        }
        return 0
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }
}
