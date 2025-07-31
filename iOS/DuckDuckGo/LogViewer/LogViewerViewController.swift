//
//  LogViewerViewController.swift
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

import UIKit
import OSLog
import Core

@available(iOS 15.0, *)
final class LogViewerViewController: UIViewController {
    
    // MARK: - UI Components
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = UIColor(designSystemColor: .background)
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor(designSystemColor: .textSecondary).withAlphaComponent(0.2)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.register(LogEntryTableViewCell.self, forCellReuseIdentifier: LogEntryTableViewCell.identifier)
        return tableView
    }()
    
    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search logs..."
        return searchController
    }()
    
    private lazy var playPauseButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "pause.circle"),
            style: .plain,
            target: self,
            action: #selector(playPauseButtonTapped)
        )
        return button
    }()
    
    private lazy var clearButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearButtonTapped)
        )
        return button
    }()
    
    private lazy var exportButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportButtonTapped)
        )
        return button
    }()
    
    private lazy var filterButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(filterButtonTapped)
        )
        return button
    }()
    
    // MARK: - Properties
    
    private let dataSource = LogViewerDataSource()
    private var filteredEntries: [FormattedLogEntry] = [] {
        didSet {
            // print("SAMDEBUG: did set filtered entries, count \(filteredEntries.count)")
        }
    }
    private var autoScrollEnabled = true
    
    private let dependencies: DebugScreen.Dependencies
    
    // MARK: - Initialization
    
    init(dependencies: DebugScreen.Dependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource.delegate = self
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dataSource.start()
        updatePlayPauseButton()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dataSource.stop()
        updatePlayPauseButton()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = "Log Viewer"
        view.backgroundColor = UIColor(designSystemColor: .background)
        
        // Setup navigation items
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        
        navigationItem.rightBarButtonItems = [exportButton, filterButton, clearButton, playPauseButton]
        
        // Setup table view
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        updatePlayPauseButton()
    }
    
    // MARK: - Actions
    
    @objc private func playPauseButtonTapped() {
        if dataSource.isRunning {
            dataSource.stop()
        } else {
            dataSource.start()
        }
        updatePlayPauseButton()
    }
    
    @objc private func clearButtonTapped() {
        let alert = UIAlertController(
            title: "Clear Log Entries",
            message: "This will clear all current log entries. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            self.dataSource.clearLogs()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func exportButtonTapped() {
        let exportText = dataSource.exportLogs()
        let activityViewController = UIActivityViewController(
            activityItems: [exportText],
            applicationActivities: nil
        )
        
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = exportButton
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func filterButtonTapped() {
        let filterViewController = LogFilterViewController(currentFilter: dataSource.currentFilter)
        filterViewController.delegate = self
        
        let navigationController = UINavigationController(rootViewController: filterViewController)
        present(navigationController, animated: true)
    }
    
    // MARK: - Private Methods
    
    private func updatePlayPauseButton() {
        let imageName = dataSource.isRunning ? "pause.circle" : "play.circle"
        playPauseButton.image = UIImage(systemName: imageName)
    }
    
    private func applySearchFilter() {
        let searchText = searchController.searchBar.text
        
        if let searchText = searchText, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchFilter = LogFilter(
                subsystemFilter: dataSource.currentFilter.subsystemFilter,
                categoryFilter: dataSource.currentFilter.categoryFilter,
                levelFilter: dataSource.currentFilter.levelFilter,
                searchText: searchText
            )
            
            filteredEntries = dataSource.logEntries.filter { searchFilter.matches($0) }
        } else {
            filteredEntries = dataSource.logEntries
        }
        
        tableView.reloadData()
        scrollToBottomIfNeeded()
    }
    
    private func scrollToBottomIfNeeded() {
        guard autoScrollEnabled && !filteredEntries.isEmpty else { return }
        
        DispatchQueue.main.async {
            let indexPath = IndexPath(row: self.filteredEntries.count - 1, section: 0)
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        }
    }
}

// MARK: - LogViewerDataSourceDelegate

@available(iOS 15.0, *)
extension LogViewerViewController: LogViewerDataSourceDelegate {
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didUpdateEntries entries: [FormattedLogEntry]) {
        DispatchQueue.main.async {
            self.applySearchFilter()
        }
    }
    
    func logViewerDataSource(_ dataSource: LogViewerDataSource, didEncounterError error: Error) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Log Viewer Error",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
}

// MARK: - UITableViewDataSource

@available(iOS 15.0, *)
extension LogViewerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredEntries.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: LogEntryTableViewCell.identifier, for: indexPath) as? LogEntryTableViewCell else {
            fatalError("Unable to dequeue LogEntryTableViewCell")
        }
        let entry = filteredEntries[indexPath.row]
        cell.configure(with: entry)
        return cell
    }
}

// MARK: - UITableViewDelegate

@available(iOS 15.0, *)
extension LogViewerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let entry = filteredEntries[indexPath.row]
        let detailViewController = LogEntryDetailViewController(entry: entry)
        navigationController?.pushViewController(detailViewController, animated: true)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Disable auto-scroll when user starts scrolling
        autoScrollEnabled = false
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Re-enable auto-scroll if user scrolled to bottom
        let bottomEdge = scrollView.contentOffset.y + scrollView.frame.height
        let contentHeight = scrollView.contentSize.height
        
        if bottomEdge >= contentHeight - 50 { // 50pt tolerance
            autoScrollEnabled = true
        }
    }
}

// MARK: - UISearchResultsUpdating

@available(iOS 15.0, *)
extension LogViewerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applySearchFilter()
    }
}

// MARK: - LogFilterViewControllerDelegate

@available(iOS 15.0, *)
extension LogViewerViewController: LogFilterViewControllerDelegate {
    func logFilterViewController(_ controller: LogFilterViewController, didUpdateFilter filter: LogFilter) {
        dataSource.updateFilter(filter)
        controller.dismiss(animated: true)
    }
}

// MARK: - LogEntryTableViewCell

private class LogEntryTableViewCell: UITableViewCell {
    static let identifier = "LogEntryTableViewCell"
    
    private let messageLabel = UILabel()
    private let timestampContextLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = UIColor(designSystemColor: .surface)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = UIFont.daxBodyRegular()
        messageLabel.numberOfLines = 0
        contentView.addSubview(messageLabel)

        timestampContextLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampContextLabel.font = UIFont.daxFootnoteRegular()
        timestampContextLabel.textColor = UIColor(designSystemColor: .textSecondary)
        contentView.addSubview(timestampContextLabel)
        
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            timestampContextLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 6),
            timestampContextLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            timestampContextLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timestampContextLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(with entry: FormattedLogEntry) {
        messageLabel.text = entry.composedMessage

        switch entry.level {
        case .error, .fault: messageLabel.textColor = UIColor.systemRed
        default: messageLabel.textColor = UIColor(designSystemColor: .textPrimary)
        }

        timestampContextLabel.text = entry.timestampWithContext
    }
}
