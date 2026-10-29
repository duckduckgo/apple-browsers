//
//  TabsBarSearchViewController.swift
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

import UIKit

final class TabsBarSearchViewController: UITableViewController, UISearchResultsUpdating {

    var tabs: [Tab] = [] {
        didSet {
            if isViewLoaded { updateResults() }
        }
    }
    var onSelect: ((Tab) -> Void)?
    private(set) var filteredTabs: [Tab] = []

    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()

    init() {
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search Tabs"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = UserText.aiChatChooseTabsSearchPlaceholder
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        tableView.keyboardDismissMode = .onDrag
        tableView.accessibilityIdentifier = "Browser.TabsBar.SearchResults"
        emptyLabel.text = UserText.aiChatChooseTabsNoMatches
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.numberOfLines = 0
        updateResults()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.isActive = true
        searchController.searchBar.becomeFirstResponder()
    }

    @objc private func close() {
        navigationController?.dismiss(animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        updateResults()
    }

    private func updateResults() {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        filteredTabs = tabs.filter { tab in
            query.isEmpty || Self.title(for: tab).localizedStandardContains(query)
                || (tab.link?.url.absoluteString.localizedStandardContains(query) ?? false)
        }
        tableView.backgroundView = filteredTabs.isEmpty ? emptyLabel : nil
        tableView.reloadData()
    }

    static func title(for tab: Tab) -> String {
        if tab.isAITab {
            let title = UserText.omnibarFullAIChatModeDisplayTitle
            return tab.aiChatConversationTitle.map { "\(title) - \($0)" } ?? title
        }
        return tab.link?.displayTitle ?? tab.link?.url.host ?? (tab.fireTab ? UserText.fireTabTitle : UserText.newTabTitle)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredTabs.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TabSearchResult")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "TabSearchResult")
        let tab = filteredTabs[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = Self.title(for: tab)
        content.secondaryText = tab.isAITab ? nil : tab.link?.url.absoluteString
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = content
        cell.accessibilityTraits.insert(.button)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(filteredTabs[indexPath.row])
    }
}
