//
//  NetworkProtectionLogViewerViewController.swift
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
import Common
import DesignResourcesKit

final class NetworkProtectionLogViewerViewController: UITableViewController {
    
    private let logManager = NetworkProtectionLogManager()
    private var logFiles: [URL] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadLogFiles()
    }
    
    private func setupUI() {
        title = "VPN Log Snapshots"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissViewController))
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LogFileCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NoLogsCell")
    }
    
    @objc private func dismissViewController() {
        navigationController?.popViewController(animated: true)
    }
    
    private func loadLogFiles() {
        do {
            logFiles = try logManager.getExistingLogFiles()
            tableView.reloadData()
        } catch {
            showErrorAlert(message: "Failed to load log files: \(error.localizedDescription)")
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(logFiles.count, 1)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if logFiles.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "NoLogsCell", for: indexPath)
            cell.textLabel?.text = "No log snapshots available"
            cell.textLabel?.font = .systemFont(ofSize: 13)
            cell.textLabel?.textColor = UIColor(designSystemColor: .textSecondary)
            cell.selectionStyle = .none
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "LogFileCell", for: indexPath)
        let logFile = logFiles[indexPath.row]
        
        cell.textLabel?.text = logFile.lastPathComponent
        cell.textLabel?.font = .systemFont(ofSize: 13)
        cell.textLabel?.textColor = UIColor(designSystemColor: .textPrimary)
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !logFiles.isEmpty else { return }
        
        let logFile = logFiles[indexPath.row]
        showLogContent(for: logFile)
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete && !logFiles.isEmpty else { return }
        
        let logFile = logFiles[indexPath.row]
        
        do {
            try logManager.deleteLogFile(at: logFile)
            logFiles.remove(at: indexPath.row)
            
            if logFiles.isEmpty {
                tableView.reloadData()
            } else {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        } catch {
            showErrorAlert(message: "Failed to delete log file: \(error.localizedDescription)")
        }
    }
    
    private func showLogContent(for logFile: URL) {
        let logContentVC = NetworkProtectionLogContentViewController(logFile: logFile, logManager: logManager)
        navigationController?.pushViewController(logContentVC, animated: true)
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class NetworkProtectionLogContentViewController: UIViewController {
    
    private let logFile: URL
    private let logManager: NetworkProtectionLogManager
    private var textView: UITextView!
    
    init(logFile: URL, logManager: NetworkProtectionLogManager) {
        self.logFile = logFile
        self.logManager = logManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadLogContent()
    }
    
    private func setupUI() {
        title = logFile.lastPathComponent
        view.backgroundColor = UIColor(designSystemColor: .background)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareLogFile))
        
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = UIColor(designSystemColor: .surface)
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadLogContent() {
        do {
            let logContent = try logManager.readLogFile(at: logFile)
            textView.text = logContent
        } catch {
            textView.text = "Failed to load log content: \(error.localizedDescription)"
            textView.textColor = UIColor(designSystemColor: .textSecondary)
        }
    }
    
    @objc private func shareLogFile() {
        let activityVC = UIActivityViewController(activityItems: [logFile], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityVC, animated: true)
    }
}
