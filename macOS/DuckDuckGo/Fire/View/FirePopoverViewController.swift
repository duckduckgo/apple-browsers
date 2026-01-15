//
//  FirePopoverViewController.swift
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

import Cocoa
import Common
import DesignResourcesKitIcons

protocol FirePopoverViewControllerDelegate: AnyObject {
    func firePopoverViewControllerDidClear(_ firePopoverViewController: FirePopoverViewController)
    func firePopoverViewControllerDidCancel(_ firePopoverViewController: FirePopoverViewController)
}

/// Simplified Fire popover used ONLY for burner windows (Fire windows).
/// Regular windows use the SwiftUI FireDialogView instead.
final class FirePopoverViewController: NSViewController {

    weak var delegate: FirePopoverViewControllerDelegate?

    private let fireViewModel: FireViewModel
    private weak var tabCollectionViewModel: TabCollectionViewModel?
    private let themeManager: ThemeManaging

    private lazy var backgroundView: ColorView = {
        let view = ColorView(frame: .zero, backgroundColor: NSColor(designSystemColor: .surfacePrimary))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var openBurnerWindowButton: MouseOverButton = {
        let button = MouseOverButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.title = ""
        button.mouseOverColor = themeManager.theme.colorsProvider.buttonMouseOverColor
        button.mouseDownColor = themeManager.theme.colorsProvider.buttonMouseDownColor
        button.cornerRadius = 4
        button.target = self
        button.action = #selector(openNewBurnerWindowAction)
        return button
    }()

    private lazy var burnerIconView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = DesignSystemImages.Glyphs.Size16.fireWindow
        imageView.contentTintColor = NSColor.labelColor
        return imageView
    }()

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.fireDialogFireWindowTitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }()

    private lazy var descriptionLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.fireDialogFireWindowDescription)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }()

    private lazy var separatorBox: NSBox = {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .separator
        return box
    }()

    private lazy var closeBurnerWindowButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(closeBurnerWindowButtonAction))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setButtonType(.momentaryPushIn)

        button.attributedTitle = NSAttributedString(
            string: UserText.fireDialogBurnWindowButton,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: themeManager.theme.palette.destructiveTextPrimary
            ]
        )

        return button
    }()

    init(fireViewModel: FireViewModel,
         tabCollectionViewModel: TabCollectionViewModel,
         themeManager: ThemeManaging = NSApp.delegateTyped.themeManager) {
        self.fireViewModel = fireViewModel
        self.tabCollectionViewModel = tabCollectionViewModel
        self.themeManager = themeManager

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("FirePopoverViewController: Bad initializer")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 344, height: 144))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }

    private func setupUI() {
        view.addSubview(backgroundView)
        view.addSubview(burnerIconView)
        view.addSubview(titleLabel)
        view.addSubview(openBurnerWindowButton)
        view.addSubview(descriptionLabel)
        view.addSubview(separatorBox)
        view.addSubview(closeBurnerWindowButton)

        NSLayoutConstraint.activate([
            // Background fills the view
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Mouse over button (behind everything in top section)
            openBurnerWindowButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            openBurnerWindowButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            openBurnerWindowButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            openBurnerWindowButton.heightAnchor.constraint(equalToConstant: 60),

            // Burner icon
            burnerIconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            burnerIconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            burnerIconView.widthAnchor.constraint(equalToConstant: 32),
            burnerIconView.heightAnchor.constraint(equalToConstant: 32),

            // Title label
            titleLabel.leadingAnchor.constraint(equalTo: burnerIconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 25),

            // Description label
            descriptionLabel.leadingAnchor.constraint(equalTo: burnerIconView.trailingAnchor, constant: 6),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            // Separator
            separatorBox.topAnchor.constraint(equalTo: openBurnerWindowButton.bottomAnchor, constant: 6),
            separatorBox.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separatorBox.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separatorBox.heightAnchor.constraint(equalToConstant: 5),

            // Close button
            closeBurnerWindowButton.topAnchor.constraint(equalTo: separatorBox.bottomAnchor, constant: 13),
            closeBurnerWindowButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeBurnerWindowButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeBurnerWindowButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            closeBurnerWindowButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @objc private func openNewBurnerWindowAction(_ sender: Any) {
        Application.appDelegate.newBurnerWindow(self)
    }

    @objc private func closeBurnerWindowButtonAction(_ sender: Any) {
        let windowControllersManager = Application.appDelegate.windowControllersManager
        guard let tabCollectionViewModel = tabCollectionViewModel,
              let windowController = windowControllersManager.windowController(for: tabCollectionViewModel) else {
            assertionFailure("No TabCollectionViewModel or MainWindowController")
            return
        }
        windowController.window?.close()
    }
}
