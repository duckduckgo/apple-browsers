//
//  ConfigurationURLDebugViewController.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import WebKit
import Core
import Configuration
import DesignResourcesKit

final class ConfigurationURLDebugViewController: UITableViewController {

    enum Sections: Int, CaseIterable {
        case customURLs
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .long
        return formatter
    }()

    weak var viewModel: DebugScreensViewModel?
    
    private var configurationItems: [DebugScreensViewModel.ConfigurationItem] {
        return viewModel?.getConfigurationItems() ?? []
    }

    @IBAction func resetAll() {
        viewModel?.resetAllCustomURLs()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Sections.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .customURLs: return configurationItems.count
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = configurationItems[indexPath.row]
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ConfigurationURLTableViewCell.reuseIdentifier) as? ConfigurationURLTableViewCell else {
            fatalError("Failed to dequeue cell")
        }
        
        configureCell(cell, for: item, at: indexPath)
        return cell
    }
    
    private func configureCell(_ cell: ConfigurationURLTableViewCell, for item: DebugScreensViewModel.ConfigurationItem, at indexPath: IndexPath) {
        cell.title.text = item.title
        cell.subtitle.text = viewModel?.getURL(for: item.configuration) ?? ""
        cell.subtitle.textColor = viewModel?.getCustomURL(for: item.configuration) != nil ? UIColor(designSystemColor: .accent) : .label
        
        if let lastUpdate = viewModel?.getLastConfigurationUpdateDate() {
            cell.ternary.text = dateFormatter.string(from: lastUpdate)
        } else {
            cell.ternary.text = "-"
        }

        cell.refresh.addAction(UIAction { [weak self] _ in
            self?.fetchConfiguration(for: item, at: indexPath)
        }, for: .primaryActionTriggered)

        cell.trash.addAction(UIAction { [weak self] _ in
            self?.resetCustomURL(for: item, at: indexPath)
        }, for: .primaryActionTriggered)
    }
    
    private func fetchConfiguration(for item: DebugScreensViewModel.ConfigurationItem, at indexPath: IndexPath) {
        viewModel?.fetchConfiguration(for: item.configuration) { [weak self] _ in
            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
        }
    }
    
    private func resetCustomURL(for item: DebugScreensViewModel.ConfigurationItem, at indexPath: IndexPath) {
        viewModel?.setCustomURL(nil, for: item.configuration)
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = configurationItems[indexPath.row]
        presentCustomURLAlert(for: item)
    }

    private func presentCustomURLAlert(for item: DebugScreensViewModel.ConfigurationItem) {
        let alert = UIAlertController(title: item.title, message: "Provide custom URL", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Enter custom URL"
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.tableView.reloadData()
        }
        alert.addAction(cancelAction)

        if viewModel?.getCustomURL(for: item.configuration) != nil {
            let resetAction = UIAlertAction(title: "Reset to default URL", style: .default) { _ in
                self.viewModel?.setCustomURL(nil, for: item.configuration)
                self.tableView?.reloadData()
            }
            alert.addAction(resetAction)
        }

        let submitAction = UIAlertAction(title: "Override", style: .default) { _ in
            let urlString = alert.textFields?.first?.text
            let customURL = urlString.flatMap { URL(string: $0) }
            self.viewModel?.setCustomURL(customURL, for: item.configuration)
            
            // Trigger fetch for the updated configuration
            self.viewModel?.fetchConfiguration(for: item.configuration) { _ in
                self.tableView.reloadData()
            }
        }
        alert.addAction(submitAction)
        
        let indexPath = IndexPath(row: configurationItems.firstIndex { $0.configuration == item.configuration } ?? 0, section: Sections.customURLs.rawValue)
        let cell = self.tableView.cellForRow(at: indexPath)!
        present(controller: alert, fromView: cell)
    }
}

final class ConfigurationURLTableViewCell: UITableViewCell {

    static let reuseIdentifier = "ConfigurationURLTableViewCell"

    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet weak var refresh: UIButton!
    @IBOutlet weak var trash: UIButton!
    @IBOutlet weak var ternary: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        subtitle.textColor = UIColor(designSystemColor: .accent)
    }
}
