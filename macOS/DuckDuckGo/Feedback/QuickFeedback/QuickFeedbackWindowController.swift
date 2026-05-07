//
//  QuickFeedbackWindowController.swift
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

import AppKit
import WebKit

@MainActor
final class QuickFeedbackWindowController: NSWindowController {

    let webView: WKWebView
    private let signOutBar = NSView()
    private let signOutButton = NSButton()
    private var signOutBarHeightConstraint: NSLayoutConstraint!

    var onSignOutRequested: (() -> Void)?

    init(webViewConfiguration: WKWebViewConfiguration) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "Internal Feedback"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 450, height: 500)
        panel.center()

        webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        super.init(window: panel)

        setupContentView(in: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSignOutVisible(_ visible: Bool) {
        signOutBar.isHidden = !visible
        signOutBarHeightConstraint.constant = visible ? 28 : 0
    }

    private func setupContentView(in panel: NSPanel) {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        signOutBar.translatesAutoresizingMaskIntoConstraints = false
        signOutBar.isHidden = true

        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.title = "Sign out"
        signOutButton.bezelStyle = .inline
        signOutButton.isBordered = false
        signOutButton.font = .systemFont(ofSize: 12)
        signOutButton.contentTintColor = .secondaryLabelColor
        signOutButton.target = self
        signOutButton.action = #selector(signOutClicked)

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        signOutBar.addSubview(signOutButton)
        signOutBar.addSubview(separator)

        contentView.addSubview(signOutBar)
        contentView.addSubview(webView)

        panel.contentView = contentView

        signOutBarHeightConstraint = signOutBar.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            signOutBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            signOutBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            signOutBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            signOutBarHeightConstraint,

            signOutButton.trailingAnchor.constraint(equalTo: signOutBar.trailingAnchor, constant: -8),
            signOutButton.centerYAnchor.constraint(equalTo: signOutBar.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: signOutBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: signOutBar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: signOutBar.bottomAnchor),

            webView.topAnchor.constraint(equalTo: signOutBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @objc private func signOutClicked() {
        onSignOutRequested?()
    }
}
