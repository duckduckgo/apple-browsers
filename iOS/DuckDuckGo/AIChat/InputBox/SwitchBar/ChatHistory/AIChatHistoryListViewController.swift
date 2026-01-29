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
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// A view controller displaying the list of recent AI chats
final class AIChatHistoryListViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let cellIdentifier = "AIChatHistoryCell"
        static let iconSize: CGFloat = 16
        static let iconTextSpacing: CGFloat = 12
        static let cellHeight: CGFloat = 44
        static let horizontalInset: CGFloat = 16
        static let topContentInset: CGFloat = 0
        static let sectionHeaderHeight: CGFloat = 32
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
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = 0
        tableView.contentInset = UIEdgeInsets(top: Constants.topContentInset, left: 0, bottom: 0, right: 0)
        return tableView
    }()

    private var chats: [AIChatSuggestion] {
        viewModel.filteredSuggestions
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
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
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

    private func configureCell(_ cell: UITableViewCell, with chat: AIChatSuggestion) {
        var config = cell.defaultContentConfiguration()

        config.text = chat.title
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        config.textProperties.color = UIColor(designSystemColor: .textPrimary)
        config.textProperties.lineBreakMode = .byTruncatingTail
        config.textProperties.numberOfLines = 1

        let icon = chat.isPinned ? DesignSystemImages.Glyphs.Size24.pin : DesignSystemImages.Glyphs.Size24.chat
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
        return chats.isEmpty ? 0 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)

        guard indexPath.row < chats.count else { return cell }

        let chat = chats[indexPath.row]
        configureCell(cell, with: chat)

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return UserText.aiChatRecentChatsTitle
    }
}

// MARK: - UITableViewDelegate

extension AIChatHistoryListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.row < chats.count else { return }

        let chat = chats[indexPath.row]
        let pixel: Pixel.Event = chat.isPinned ? .aiChatRecentChatSelectedPinned : .aiChatRecentChatSelected
        DailyPixel.fireDailyAndCount(pixel: pixel)
        onChatSelected(chat)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return Constants.cellHeight
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Constants.sectionHeaderHeight
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }
}
