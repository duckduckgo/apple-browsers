//
//  BrowsingMenuSeparatorViewCell.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

class BrowsingMenuSeparatorViewCell: UITableViewCell {

    let separator = UIView()
    private var separatorHeight: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        setupConstraints()
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configure() {
        separatorHeight.constant = 1.0 / UIScreen.main.scale
        contentView.backgroundColor = .clear
    }

    private func setupViews() {
        selectionStyle = .none
        accessibilityElementsHidden = true
        textLabel?.accessibilityElementsHidden = true

        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)
    }

    private func setupConstraints() {
        separatorHeight = separator.heightAnchor.constraint(equalToConstant: 1)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentView.trailingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 24),
            separator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            separatorHeight
        ])
    }
}
