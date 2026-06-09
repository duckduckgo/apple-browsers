//
//  DuckAISuggestionTableViewCell.swift
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

import Foundation
import UIKit
import DesignResourcesKitIcons

final class DuckAISuggestionTableViewCell: UITableViewCell {

    private enum Metrics {
        static let size: CGSize = CGSize(width: 44, height: 44)
    }

    private lazy var deleteButton: UIButton = {
        let fireImage = DesignSystemImages.Glyphs.Size16.fire.withRenderingMode(.alwaysTemplate)
        let deleteAction = UIAction { [weak self] _ in
            self?.onDeletePressed?()
        }

        let button = UIButton(type: .system)
        button.setImage(fireImage, for: .normal)
        button.frame.size = Metrics.size
        button.contentHorizontalAlignment = .trailing
        button.tintColor = UIColor(designSystemColor: .icons)
        button.addAction(deleteAction, for: .touchUpInside)
        return button
    }()

    var onDeletePressed: (() -> Void)?

    var displaysDeleteButton: Bool = false {
        didSet {
            accessoryView = displaysDeleteButton ? deleteButton : nil
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        displaysDeleteButton = false
    }
}
