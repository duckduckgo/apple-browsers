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
import SwiftUI

final class FireproofDomainCellView: NSTableCellView {

    static var identifier: NSUserInterfaceItemIdentifier { .init(rawValue: FireproofDomainCellView.className()) }

    private var faviconHostingView: NSHostingView<FaviconView>?

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

        let iconPlaceholder = NSView()
        let titleField = NSTextField(labelWithString: "")

        iconPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        iconPlaceholder.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        iconPlaceholder.setContentHuggingPriority(.defaultHigh, for: .vertical)
        iconPlaceholder.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconPlaceholder.heightAnchor.constraint(equalToConstant: 16).isActive = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconPlaceholder)

        addSubview(titleField)

        textField = titleField

        NSLayoutConstraint.activate([
            iconPlaceholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            iconPlaceholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: iconPlaceholder.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: 0),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Host SwiftUI FaviconView in the icon slot so it handles cache + generated icons automatically
        let hosting = NSHostingView(rootView: FaviconView(url: nil, size: 16))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: iconPlaceholder.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: iconPlaceholder.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: iconPlaceholder.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: iconPlaceholder.bottomAnchor)
        ])
        faviconHostingView = hosting
    }

    func update(host: String) {
        textField?.stringValue = host
        toolTip = host
        faviconHostingView?.rootView = FaviconView(url: URL(string: "https://\(host)"), size: 16)
    }
}
