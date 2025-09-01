//
//  LogFilterViewController.swift
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

protocol LogFilterViewControllerDelegate: AnyObject {
    func logFilterViewController(_ controller: LogFilterViewController, didUpdateFilter filter: LogFilter)
}

final class LogFilterViewController: UIViewController {

    weak var delegate: LogFilterViewControllerDelegate?

    private var currentFilter: LogFilter
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = UIColor(designSystemColor: .background)
        return tableView
    }()
    
    init(currentFilter: LogFilter) {
        self.currentFilter = currentFilter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        title = "Log Filters"
        view.backgroundColor = UIColor(designSystemColor: .background)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneTapped() {
        delegate?.logFilterViewController(self, didUpdateFilter: currentFilter)
    }
    
    @objc private func toggleSwitchChanged(_ sender: UISwitch) {
        guard let toggleRow = ToggleFilterRow(rawValue: sender.tag) else { return }
        
        switch toggleRow {
        case .filterEmptySubsystems:
            currentFilter = LogFilter(
                subsystemFilter: currentFilter.subsystemFilter,
                categoryFilter: currentFilter.categoryFilter,
                levelFilter: currentFilter.levelFilter,
                searchText: currentFilter.searchText,
                filterEmptySubsystems: sender.isOn,
                filterAppleLogs: currentFilter.filterAppleLogs
            )
        case .filterAppleLogs:
            currentFilter = LogFilter(
                subsystemFilter: currentFilter.subsystemFilter,
                categoryFilter: currentFilter.categoryFilter,
                levelFilter: currentFilter.levelFilter,
                searchText: currentFilter.searchText,
                filterEmptySubsystems: currentFilter.filterEmptySubsystems,
                filterAppleLogs: sender.isOn
            )
        }
    }
}

extension LogFilterViewController: UITableViewDataSource {
    
    enum Section: Int, CaseIterable {
        case toggleFilters = 0
        case customFilters = 1
        case logLevel = 2
        
        var title: String {
            switch self {
            case .toggleFilters:
                return "Filter Options"
            case .customFilters:
                return "Custom Filters"
            case .logLevel:
                return "Minimum Log Level"
            }
        }
    }
    
    enum ToggleFilterRow: Int, CaseIterable {
        case filterEmptySubsystems = 0
        case filterAppleLogs = 1
        
        var title: String {
            switch self {
            case .filterEmptySubsystems:
                return "Filter Empty Subsystems"
            case .filterAppleLogs:
                return "Filter Apple Logs"
            }
        }
    }
    
    enum CustomFilterRow: Int, CaseIterable {
        case subsystem
        case category
        
        var title: String {
            switch self {
            case .subsystem:
                return "Subsystem Filter"
            case .category:
                return "Category Filter"
            }
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .toggleFilters:
            return ToggleFilterRow.allCases.count
        case .customFilters:
            return CustomFilterRow.allCases.count
        case .logLevel:
            return 6 // debug, info, notice, error, fault, none
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = UIColor(designSystemColor: .surface)
        cell.textLabel?.textColor = UIColor(designSystemColor: .textPrimary)
        cell.detailTextLabel?.textColor = UIColor(designSystemColor: .textSecondary)
        
        guard let sectionType = Section(rawValue: indexPath.section) else { return cell }
        
        switch sectionType {
        case .toggleFilters:
            configureToggleFilterCell(cell, at: indexPath)
        case .customFilters:
            configureCustomFilterCell(cell, at: indexPath)
        case .logLevel:
            configureLogLevelCell(cell, at: indexPath)
        }
        
        return cell
    }
    
    private func configureToggleFilterCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let toggleRow = ToggleFilterRow(rawValue: indexPath.row) else { return }
        
        cell.textLabel?.text = toggleRow.title
        cell.selectionStyle = .none

        let toggleSwitch = UISwitch()
        switch toggleRow {
        case .filterEmptySubsystems:
            toggleSwitch.isOn = currentFilter.filterEmptySubsystems
        case .filterAppleLogs:
            toggleSwitch.isOn = currentFilter.filterAppleLogs
        }
        
        toggleSwitch.addTarget(self, action: #selector(toggleSwitchChanged(_:)), for: .valueChanged)
        toggleSwitch.tag = indexPath.row
        cell.accessoryView = toggleSwitch
    }
    
    private func configureCustomFilterCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let filterRow = CustomFilterRow(rawValue: indexPath.row) else { return }
        
        cell.textLabel?.text = filterRow.title
        cell.accessoryType = .disclosureIndicator
        
        switch filterRow {
        case .subsystem:
            cell.detailTextLabel?.text = currentFilter.subsystemFilter ?? "None"
        case .category:
            cell.detailTextLabel?.text = currentFilter.categoryFilter ?? "None"
        }
    }
    
    private func configureLogLevelCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        let levels: [OSLogEntryLog.Level?] = [.debug, .info, .notice, .error, .fault, nil]
        let level = levels[indexPath.row]
        
        if let level = level {
            cell.textLabel?.text = level.displayName
        } else {
            cell.textLabel?.text = "No Filter"
        }
        
        cell.accessoryType = (currentFilter.levelFilter == level) ? .checkmark : .none
    }
}

extension LogFilterViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let sectionType = Section(rawValue: indexPath.section) else { return }
        
        switch sectionType {
        case .toggleFilters:
            // Toggle switches handle their own actions, no selection needed
            break
        case .customFilters:
            handleCustomFilterSelection(at: indexPath)
        case .logLevel:
            handleLogLevelSelection(at: indexPath)
        }
    }
    
    private func handleCustomFilterSelection(at indexPath: IndexPath) {
        guard let filterRow = CustomFilterRow(rawValue: indexPath.row) else { return }
        
        let alert = UIAlertController(title: filterRow.title, message: "Enter filter text:", preferredStyle: .alert)
        
        alert.addTextField { textField in
            switch filterRow {
            case .subsystem:
                textField.text = self.currentFilter.subsystemFilter
                textField.placeholder = "e.g., Subscription"
            case .category:
                textField.text = self.currentFilter.categoryFilter
                textField.placeholder = "e.g., Keychain"
            }
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Set", style: .default) { _ in
            let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let filterText = text?.isEmpty == true ? nil : text
            
            switch filterRow {
            case .subsystem:
                self.currentFilter = LogFilter(
                    subsystemFilter: filterText,
                    categoryFilter: self.currentFilter.categoryFilter,
                    levelFilter: self.currentFilter.levelFilter,
                    searchText: self.currentFilter.searchText,
                    filterEmptySubsystems: self.currentFilter.filterEmptySubsystems,
                    filterAppleLogs: self.currentFilter.filterAppleLogs
                )
            case .category:
                self.currentFilter = LogFilter(
                    subsystemFilter: self.currentFilter.subsystemFilter,
                    categoryFilter: filterText,
                    levelFilter: self.currentFilter.levelFilter,
                    searchText: self.currentFilter.searchText,
                    filterEmptySubsystems: self.currentFilter.filterEmptySubsystems,
                    filterAppleLogs: self.currentFilter.filterAppleLogs
                )
            }
            
            self.tableView.reloadData()
        })
        
        present(alert, animated: true)
    }
    
    private func handleLogLevelSelection(at indexPath: IndexPath) {
        let levels: [OSLogEntryLog.Level?] = [.debug, .info, .notice, .error, .fault, nil]
        let selectedLevel = levels[indexPath.row]
        
        currentFilter = LogFilter(
            subsystemFilter: currentFilter.subsystemFilter,
            categoryFilter: currentFilter.categoryFilter,
            levelFilter: selectedLevel,
            searchText: currentFilter.searchText,
            filterEmptySubsystems: currentFilter.filterEmptySubsystems,
            filterAppleLogs: currentFilter.filterAppleLogs
        )
        
        tableView.reloadSections(IndexSet(integer: Section.logLevel.rawValue), with: .none)
    }

}
