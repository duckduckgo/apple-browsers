//
//  AIChatHistoryNoResultsCell.swift
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
import DesignResourcesKit

/// "No matches found" cell shown inside the chat-history list when a search returns nothing.
/// Rendered as a single row so it inherits the `.insetGrouped` rounded card visual, matching
/// the equivalent row in `BookmarksViewController` (see `NoResultsCell` in
/// `BookmarksViewControllerCells.swift`).
final class AIChatHistoryNoResultsCell: UITableViewCell {

    static let reuseIdentifier = "AIChatHistoryNoResultsCell"

    private let label: UILabel = {
        let label = UILabel()
        label.text = UserText.aiChatHistoryNoSearchResultsTitle
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(designSystemColor: .surface)
        selectionStyle = .none
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }
}
