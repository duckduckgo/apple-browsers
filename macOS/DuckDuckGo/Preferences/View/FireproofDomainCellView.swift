//
//  FireproofDomainCellView.swift
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

import AppKit

final class FireproofDomainCellView: NSTableCellView {

    static var identifier: NSUserInterfaceItemIdentifier { .init(rawValue: FireproofDomainCellView.className()) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        identifier = Self.identifier

        let iconView = NSImageView()
        let titleField = NSTextField(labelWithString: "")

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        iconView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(titleField)

        imageView = iconView
        textField = titleField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: 0),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func update(host: String) {
        textField?.stringValue = host
        toolTip = host
    }
}
