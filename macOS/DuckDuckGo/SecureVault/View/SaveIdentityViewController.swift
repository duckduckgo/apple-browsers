//
//  SaveIdentityViewController.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import PixelKit
import os.log

protocol SaveIdentityDelegate: AnyObject {

    func shouldCloseSaveIdentityViewController(_: SaveIdentityViewController)

}

final class SaveIdentityViewController: NSViewController {

    private enum LayoutConstants {
        static let contentSize = CGSize(width: 340, height: 177)
        static let inset: CGFloat = 16
        static let settingsButtonSide: CGFloat = 20
        static let identityIconTop: CGFloat = 16
        static let stackMinHeight: CGFloat = 50
    }

    static func create() -> SaveIdentityViewController {
        let controller = SaveIdentityViewController(nibName: nil, bundle: nil)
        // Calling loadView() directly won't send viewDidLoad()
        _ = controller.view

        return controller
    }

    private var identityStackView: NSStackView!
    var titleLabel: NSTextField!
    var notNowButton: NSButton!
    var saveButton: NSButton!

    weak var delegate: SaveIdentityDelegate?

    private var identity: SecureVaultModels.Identity?

    // MARK: - Actions

    @objc func onNotNowClicked(sender: NSButton) {
        self.delegate?.shouldCloseSaveIdentityViewController(self)
    }

    @objc func onSaveClicked(sender: NSButton) {
        defer {
            self.delegate?.shouldCloseSaveIdentityViewController(self)
        }

        guard var identity = identity else {
            assertionFailure("Tried to save identity, but the view controller didn't have one")
            return
        }

        identity.title = UserText.pmDefaultIdentityAutofillTitle

        do {
            try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared).storeIdentity(identity)
            PixelKit.fire(GeneralPixel.autofillItemSaved(kind: .identity))

            if let syncService = NSApp.delegateTyped.syncService {
                syncService.scheduler.requestSyncImmediately()
            }
        } catch {
            Logger.general.error("Failed to store identity \(error.localizedDescription)")
            PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
        }
    }

    @objc func onOpenPreferencesClicked(sender: NSButton) {
        Application.appDelegate.windowControllersManager.showPreferencesTab()
        self.delegate?.shouldCloseSaveIdentityViewController(self)
    }

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: LayoutConstants.contentSize))

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.lineBreakMode = .byClipping

        let openPreferencesButton = MouseOverButton(frame: .zero)
        openPreferencesButton.translatesAutoresizingMaskIntoConstraints = false
        openPreferencesButton.setButtonType(.momentaryChange)
        openPreferencesButton.isBordered = false
        openPreferencesButton.bezelStyle = .rounded
        openPreferencesButton.image = .settings16
        openPreferencesButton.imagePosition = .imageOnly
        openPreferencesButton.title = ""
        openPreferencesButton.imageScaling = .scaleProportionallyDown
        openPreferencesButton.alignment = .center
        openPreferencesButton.target = self
        openPreferencesButton.action = #selector(onOpenPreferencesClicked(sender:))

        let topSeparator = NSBox()
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.boxType = .separator
        topSeparator.setContentHuggingPriority(.init(750), for: .vertical)

        let identityIcon = NSImageView()
        identityIcon.translatesAutoresizingMaskIntoConstraints = false
        identityIcon.image = .identity
        identityIcon.imageScaling = .scaleProportionallyDown
        identityIcon.imageAlignment = .alignLeft
        identityIcon.refusesFirstResponder = true

        identityStackView = NSStackView()
        identityStackView.translatesAutoresizingMaskIntoConstraints = false
        identityStackView.orientation = .vertical
        identityStackView.distribution = .fill
        identityStackView.alignment = .leading
        identityStackView.spacing = 4
        identityStackView.detachesHiddenViews = true

        let bottomSeparator = NSBox()
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.boxType = .separator
        bottomSeparator.setContentHuggingPriority(.init(750), for: .vertical)

        saveButton = NSButton(title: "", target: self, action: #selector(onSaveClicked(sender:)))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded

        notNowButton = NSButton(title: "", target: self, action: #selector(onNotNowClicked(sender:)))
        notNowButton.translatesAutoresizingMaskIntoConstraints = false
        notNowButton.bezelStyle = .rounded

        view.addSubview(titleLabel)
        view.addSubview(topSeparator)
        view.addSubview(openPreferencesButton)
        view.addSubview(identityIcon)
        view.addSubview(bottomSeparator)
        view.addSubview(saveButton)
        view.addSubview(notNowButton)
        view.addSubview(identityStackView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.inset),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            openPreferencesButton.widthAnchor.constraint(equalToConstant: LayoutConstants.settingsButtonSide),
            openPreferencesButton.heightAnchor.constraint(equalToConstant: LayoutConstants.settingsButtonSide),
            openPreferencesButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            openPreferencesButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            view.trailingAnchor.constraint(equalTo: openPreferencesButton.trailingAnchor, constant: LayoutConstants.inset),

            topSeparator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: topSeparator.trailingAnchor),

            identityIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.inset),
            identityIcon.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: LayoutConstants.identityIconTop),

            identityStackView.heightAnchor.constraint(greaterThanOrEqualToConstant: LayoutConstants.stackMinHeight),
            identityStackView.leadingAnchor.constraint(equalTo: identityIcon.trailingAnchor, constant: LayoutConstants.inset),
            identityStackView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: LayoutConstants.inset),
            view.trailingAnchor.constraint(equalTo: identityStackView.trailingAnchor, constant: LayoutConstants.inset),

            bottomSeparator.topAnchor.constraint(equalTo: identityStackView.bottomAnchor, constant: 18),
            bottomSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: bottomSeparator.trailingAnchor),

            saveButton.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: LayoutConstants.inset),
            view.bottomAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 12),

            saveButton.leadingAnchor.constraint(equalTo: notNowButton.trailingAnchor, constant: 8),
            notNowButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])

        self.view = view
    }

    // MARK: - Public

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpStrings()
    }

    func saveIdentity(_ identity: SecureVaultModels.Identity) {
        self.identity = identity

        buildStackView(from: identity)
    }

    // MARK: - Private

    private func buildStackView(from identity: SecureVaultModels.Identity) {

        // Rebuilt from scratch on every call, so clear whatever the previous identity left behind.
        identityStackView.arrangedSubviews.forEach { view in
            view.removeFromSuperview()
        }

        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.longFormattedName))

        identityStackView.setCustomSpacingAfterLastView(20)

        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.addressStreet))
        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.addressStreet2))
        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.addressCity))
        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.addressProvince))
        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.addressPostalCode))
        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.addressCountryCode))

        identityStackView.setCustomSpacingAfterLastView(20)

        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.homePhone))
        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.mobilePhone))

        identityStackView.setCustomSpacingAfterLastView(20)

        identityStackView.addArrangedSubview(NSTextField.optionalLabel(titled: identity.emailAddress))

    }

    private func setUpStrings() {
        titleLabel.stringValue = UserText.passwordManagementSaveAddress
        notNowButton.title = UserText.notNow
        saveButton.title = UserText.save
    }

}
