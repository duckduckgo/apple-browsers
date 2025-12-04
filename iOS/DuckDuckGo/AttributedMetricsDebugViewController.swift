//
//  AttributedMetricsDebugViewController.swift
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
import AttributedMetric
import PixelKit
import Common

final class AttributedMetricsDebugViewController: UITableViewController {

    var attributedMetricDataStorage: any AttributedMetricDataStoring

    required init?(coder: NSCoder) {
        self.attributedMetricDataStorage = AttributedMetricDataStorage(userDefaults: UserDefaults.standard, errorHandler: nil)
        super.init(coder: coder)
    }

    private let titles = [
        Sections.section1: "Actions",
        Sections.section2: "Current values",
    ]

    enum Sections: Int, CaseIterable {
        case section1
        case section2
    }

    enum Section1Rows: Int, CaseIterable {
        case resetAll
        case setCurrentTime
        case setOrigin
    }

    enum Section2Rows: Int, CaseIterable {
        case installDate
        case lastRetentionThreshold
        case search8Days
        case adClick8Days
        case duckAIChat8Days
        case subscriptionDate
        case subscriptionFreeTrialFired
        case subscriptionMonth1Fired
        case syncDevicesCount
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Sections(rawValue: section) else { return nil }
        return titles[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        cell.textLabel?.textColor = UIColor.label
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = nil
        cell.accessoryType = .none

        switch Sections(rawValue: indexPath.section) {
        case .section1:
            switch Section1Rows(rawValue: indexPath.row) {
            case .resetAll:
                cell.textLabel?.text = "Reset stored data"
            case .setCurrentTime:
                cell.textLabel?.text = "Set Current time"
            case .setOrigin:
                cell.textLabel?.text = "Set Origin"
            case .none:
                break
            }
        case .section2:
            cell.selectionStyle = .none
            switch Section2Rows(rawValue: indexPath.row) {
            case .installDate:
                cell.textLabel?.text = "Install Date"
                cell.detailTextLabel?.text = attributedMetricDataStorage.installDate?.ISO8601Format() ?? "nil"
            case .lastRetentionThreshold:
                cell.textLabel?.text = "Last Retention Threshold"
                cell.detailTextLabel?.text = attributedMetricDataStorage.lastRetentionThreshold?.description ?? "nil"
            case .search8Days:
                cell.textLabel?.text = "Search (8 days)"
                cell.detailTextLabel?.text = attributedMetricDataStorage.search8Days.debugDescription
            case .adClick8Days:
                cell.textLabel?.text = "Ad Click (8 days)"
                cell.detailTextLabel?.text = attributedMetricDataStorage.adClick8Days.debugDescription
            case .duckAIChat8Days:
                cell.textLabel?.text = "Duck AI Chat (8 days)"
                cell.detailTextLabel?.text = attributedMetricDataStorage.duckAIChat8Days.debugDescription
            case .subscriptionDate:
                cell.textLabel?.text = "Subscription Date"
                cell.detailTextLabel?.text = attributedMetricDataStorage.subscriptionDate?.ISO8601Format() ?? "nil"
            case .subscriptionFreeTrialFired:
                cell.textLabel?.text = "Subscription Free Trial Fired"
                cell.detailTextLabel?.text = String(attributedMetricDataStorage.subscriptionFreeTrialFired)
            case .subscriptionMonth1Fired:
                cell.textLabel?.text = "Subscription Month1 Fired"
                cell.detailTextLabel?.text = String(attributedMetricDataStorage.subscriptionMonth1Fired)
            case .syncDevicesCount:
                cell.textLabel?.text = "Sync Devices Count"
                cell.detailTextLabel?.text = String(attributedMetricDataStorage.syncDevicesCount)
            case .none:
                break
            }
        case .none:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sections(rawValue: section) {
        case .section1: return Section1Rows.allCases.count
        case .section2: return Section2Rows.allCases.count
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Sections(rawValue: indexPath.section) {
        case .section1:
            switch Section1Rows(rawValue: indexPath.row) {
            case .resetAll: handleResetAll()
            case .setCurrentTime: handleSetCurrentTime()
            case .setOrigin: handleSetOrigin()
            default: break
            }
        case .section2:
            // Section 2 rows are display-only, no actions
            break
        case .none:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Row Actions

    private func handleResetAll() {
        self.attributedMetricDataStorage.removeAll()
        self.tableView.reloadData()
        showAlert(title: "Done", message: "All Attributed Metrics data stored in UserDefaults has been removed")
    }

    private func handleSetCurrentTime() {
        let alertController = UIAlertController(title: "Set Current Time", message: nil, preferredStyle: .actionSheet)

        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.date = self.attributedMetricDataStorage.debugDate ?? Date()
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        let pickerContainer = UIViewController()
        pickerContainer.view = datePicker
        pickerContainer.preferredContentSize = CGSize(width: datePicker.frame.width, height: 250)

        alertController.setValue(pickerContainer, forKey: "contentViewController")

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let selectedDate = datePicker.date
            self.attributedMetricDataStorage.debugDate = selectedDate
            self.tableView.reloadData()
            self.showAlert(title: "Done", message: "Current time set to: \(selectedDate.ISO8601Format())\n**RESTART THE APP TO APPLY**")
        }

        let isDatePresent = attributedMetricDataStorage.debugDate != nil

        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.attributedMetricDataStorage.debugDate = nil
            self.tableView.reloadData()
            self.showAlert(title: "Done", message: "Current time override removed")
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alertController.addAction(saveAction)
        if isDatePresent {
            alertController.addAction(deleteAction)
        }
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }

    private func handleSetOrigin() {
        let alertController = UIAlertController(title: "Set Origin", message: "Enter origin value", preferredStyle: .alert)

        alertController.addTextField { textField in
            textField.placeholder = "Origin"
            textField.text = self.attributedMetricDataStorage.debugOrigin
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self, weak alertController] _ in
            guard let self = self,
                  let textField = alertController?.textFields?.first,
                  let text = textField.text else {
                return
            }
            if text.isEmpty {
                self.attributedMetricDataStorage.debugOrigin = nil
            } else {
                self.attributedMetricDataStorage.debugOrigin = text
            }
            self.tableView.reloadData()
            self.showAlert(title: "Done", message: "Origin set to: \(text)")
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)

        alertController.addAction(saveAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }

    // MARK: - Helper

    private func showAlert(title: String, message: String? = nil) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}
