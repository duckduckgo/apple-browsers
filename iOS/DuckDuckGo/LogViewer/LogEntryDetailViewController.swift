//
//  LogEntryDetailViewController.swift
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

final class LogEntryDetailViewController: UIViewController {

    private let logEntry: FormattedLogEntry

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private lazy var contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()
    
    init(entry: FormattedLogEntry) {
        self.logEntry = entry
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateContent()
    }
    
    private func setupUI() {
        title = "Log Entry Details"
        view.backgroundColor = UIColor(designSystemColor: .background)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareButtonTapped)
        )
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func populateContent() {
        let levelTimestampView = createInfoSection(
            title: "Level & Time",
            content: "\(logEntry.level.displayName) • \(formatFullTimestamp(logEntry.timestamp))"
        )
        contentStackView.addArrangedSubview(levelTimestampView)

        let subsystemView = createInfoSection(title: "Subsystem", content: logEntry.subsystem)
        contentStackView.addArrangedSubview(subsystemView)

        if !logEntry.category.isEmpty {
            let categoryView = createInfoSection(title: "Category", content: logEntry.category)
            contentStackView.addArrangedSubview(categoryView)
        }

        let processView = createInfoSection(title: "Process", content: logEntry.process)
        contentStackView.addArrangedSubview(processView)

        let messageView = createInfoSection(
            title: "Message",
            content: logEntry.message,
            isExpandable: true
        )

        contentStackView.addArrangedSubview(messageView)
    }
    
    private func createInfoSection(title: String, content: String, isExpandable: Bool = false) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor(designSystemColor: .surface)
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor(designSystemColor: .surface).cgColor
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.isLayoutMarginsRelativeArrangement = true
        
        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = UIColor(designSystemColor: .textSecondary)
        titleLabel.text = title.uppercased()
        
        let contentLabel = UILabel()
        contentLabel.font = UIFont.systemFont(ofSize: 16)
        contentLabel.textColor = UIColor(designSystemColor: .textPrimary)
        contentLabel.text = content
        contentLabel.numberOfLines = isExpandable ? 0 : 3
        
        if isExpandable {
            contentLabel.lineBreakMode = .byWordWrapping
        }
        
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(contentLabel)
        
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .full
        return formatter.string(from: date)
    }
    
    @objc private func shareButtonTapped() {
        let shareText = formatEntryForSharing()
        let activityViewController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
    
    private func formatEntryForSharing() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        return """
        DuckDuckGo iOS Log Entry
        
        Timestamp: \(dateFormatter.string(from: logEntry.timestamp))
        Level: \(logEntry.level.displayName)
        Subsystem: \(logEntry.subsystem)
        Category: \(logEntry.category)
        
        Message:
        \(logEntry.message)
        """
    }
}
