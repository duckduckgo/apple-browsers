//
//  SaveCredentialsViewController.swift
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

import AppKit
import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import PixelKit
import os.log
import DesignResourcesKitIcons

protocol SaveCredentialsDelegate: AnyObject {

    /// May not be called on main thread.
    func shouldCloseSaveCredentialsViewController(_: SaveCredentialsViewController)

}

extension SaveCredentialsViewController: MouseOverViewDelegate {
    func mouseOverView(_ mouseOverView: MouseOverView, isMouseOver: Bool) {
        if isMouseOver {
            lockImageBackgroundView.fillColor = NSColor.infoHoverButtonHovered
            presentSecurityInfoPopover()
        } else {
            dismissSecurityInfoPopover()
        }
    }

    private func presentSecurityInfoPopover() {
        // Only show the popover if we aren't already presenting one:
        guard infoViewController == nil else {
            infoViewController?.cancelAutoDismiss()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let message = autofillPreferences.isAutoLockEnabled ? UserText.pmSaveCredentialsSecurityInfo : UserText.pmSaveCredentialsSecurityInfoAutolockOff
            let infoViewController = PopoverInfoViewController(message: message) { [weak self] in
                self?.lockImageBackgroundView.fillColor = NSColor.infoHoverButton
            }
            infoViewController.show(onParent: self, relativeTo: self.tooltipView)
        }
    }

    private func dismissSecurityInfoPopover() {
        infoViewController?.scheduleAutoDismiss()
    }
}

final class SaveCredentialsViewController: NSViewController {

    static func create(fireproofDomains: FireproofDomains) -> SaveCredentialsViewController {
        let controller = SaveCredentialsViewController(fireproofDomains: fireproofDomains)
        // Calling loadView() directly won't send viewDidLoad()
        _ = controller.view

        return controller
    }

    private enum LayoutConstants {
        static let contentSize = CGSize(width: 340, height: 306)
        static let headerHeight: CGFloat = 44
        static let headerInset: CGFloat = 20
        static let logoSide: CGFloat = 24
        static let faviconSide: CGFloat = 16
        static let fieldInset: CGFloat = 20
        static let labelInset: CGFloat = 22
        static let buttonInset: CGFloat = 20
        static let bottomInset: CGFloat = 12
        static let revealButtonSize = CGSize(width: 30, height: 20)
        static let lockBoxInset: CGFloat = 6
        static let lockBoxLeading: CGFloat = 14
    }

    var themeUpdateCancellable: AnyCancellable?

    private let backfilledKey = GeneralPixel.AutofillParameterKeys.backfilled
    private let fireproofDomains: FireproofDomains

    var backgroundBox: NSBox!
    var ddgPasswordManagerTitle: NSView!
    var titleLabel: NSTextField!
    var passwordManagerTitle: NSView!
    var passwordManagerAccountLabel: NSTextField!
    var passwordManagerTitleLabel: NSTextField!
    var unlockPasswordManagerTitle: NSView!
    var faviconImage: NSImageView!
    var domainLabel: NSTextField!
    var usernameField: NSTextField!
    var hiddenPasswordField: NSSecureTextField!
    var visiblePasswordField: NSTextField!
    var unlockPasswordManagerTitleLabel: NSTextField!
    var usernameFieldTitleLabel: NSTextField!
    var passwordFieldTitleLabel: NSTextField!
    var notNowSegmentedControl: NSSegmentedControl!
    var saveButton: NSButton!
    var updateButton: NSButton!
    var dontUpdateButton: NSButton!
    var doneButton: NSButton!
    var editButton: NSButton!
    var openPasswordManagerButton: NSButton!
    var passwordManagerNotNowButton: NSButton!
    var fireproofCheck: NSButton!
    var fireproofCheckDescription: NSTextFieldCell!
    var tooltipView: MouseOverView!
    var lockImageBackgroundView: NSBox!

    private var infoViewController: PopoverInfoViewController? {
        presentedViewControllers?.first {
            ($0 as? PopoverInfoViewController) != nil
        } as? PopoverInfoViewController
    }

    private enum Action {
        case displayed
        case confirmed
        case dismissed
    }

    weak var delegate: SaveCredentialsDelegate?

    private var credentials: SecureVaultModels.WebsiteCredentials?

    private var backfilled = false

    private var faviconManagement: FaviconManagement = NSApp.delegateTyped.faviconManager

    private var passwordManagerCoordinator: PasswordManagerCoordinating = Application.appDelegate.passwordManagerCoordinator

    private var autofillPreferences: AutofillPreferencesPersistor = AutofillPreferences()

    private var passwordManagerStateCancellable: AnyCancellable?

    private var cancellables: Set<AnyCancellable> = []

    private var saveButtonAction: (() -> Void)?

    private var shouldPostFirstPasswordSavedNotification = false

    var passwordData: Data {
        let string = hiddenPasswordField.isHidden ? visiblePasswordField.stringValue : hiddenPasswordField.stringValue
        return string.data(using: .utf8)!
    }

    private func makeHeaderLabel(size: CGFloat, clipping: Bool = true) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: size, weight: .medium)
        if clipping { label.lineBreakMode = .byClipping }
        return label
    }

    private func makeLogoImageView(_ image: NSImage) -> NSImageView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignLeft
        imageView.refusesFirstResponder = true
        imageView.setContentHuggingPriority(.init(251), for: .horizontal)
        imageView.setContentHuggingPriority(.init(251), for: .vertical)
        return imageView
    }

    private func makeDialogButton(action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.isHidden = true
        return button
    }

    private func makeBezeledField(secure: Bool = false) -> NSTextField {
        let field = secure ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.sendsActionOnEndEditing = true
        (field.cell as? NSTextFieldCell)?.isScrollable = true
        field.setContentHuggingPriority(.init(750), for: .vertical)
        return field
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .separator
        box.setContentHuggingPriority(.init(750), for: .vertical)
        return box
    }

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: LayoutConstants.contentSize))

        backgroundBox = NSBox()
        backgroundBox.translatesAutoresizingMaskIntoConstraints = false
        backgroundBox.boxType = .custom
        backgroundBox.borderWidth = 0
        backgroundBox.cornerRadius = 4
        backgroundBox.fillColor = .popoverBackground
        backgroundBox.titlePosition = .noTitle

        // MARK: Headers (only one of the three is shown at a time)
        titleLabel = makeHeaderLabel(size: 15, clipping: false)
        let titleLogo = makeLogoImageView(.daxLockScreenLogo)
        ddgPasswordManagerTitle = NSView()
        ddgPasswordManagerTitle.translatesAutoresizingMaskIntoConstraints = false
        ddgPasswordManagerTitle.addSubview(titleLogo)
        ddgPasswordManagerTitle.addSubview(titleLabel)

        passwordManagerTitleLabel = makeHeaderLabel(size: 15)
        passwordManagerAccountLabel = makeHeaderLabel(size: 11)
        let bitwardenLogo = makeLogoImageView(.bitwardenLogoSmall)
        passwordManagerTitle = NSView()
        passwordManagerTitle.translatesAutoresizingMaskIntoConstraints = false
        passwordManagerTitle.isHidden = true
        passwordManagerTitle.addSubview(bitwardenLogo)
        passwordManagerTitle.addSubview(passwordManagerTitleLabel)
        passwordManagerTitle.addSubview(passwordManagerAccountLabel)

        unlockPasswordManagerTitleLabel = makeHeaderLabel(size: 15, clipping: false)
        unlockPasswordManagerTitleLabel.lineBreakMode = .byCharWrapping
        let unlockLogo = makeLogoImageView(.bitwardenLogoSmall)
        unlockPasswordManagerTitle = NSView()
        unlockPasswordManagerTitle.translatesAutoresizingMaskIntoConstraints = false
        unlockPasswordManagerTitle.isHidden = true
        unlockPasswordManagerTitle.addSubview(unlockLogo)
        unlockPasswordManagerTitle.addSubview(unlockPasswordManagerTitleLabel)

        let headerSeparator = makeSeparator()

        // MARK: Fields
        faviconImage = makeLogoImageView(.logo)
        domainLabel = NSTextField(labelWithString: "")
        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        domainLabel.lineBreakMode = .byTruncatingMiddle

        usernameFieldTitleLabel = NSTextField(labelWithString: "")
        usernameFieldTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameFieldTitleLabel.lineBreakMode = .byClipping
        usernameField = makeBezeledField()

        passwordFieldTitleLabel = NSTextField(labelWithString: "")
        passwordFieldTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        passwordFieldTitleLabel.lineBreakMode = .byClipping
        visiblePasswordField = makeBezeledField()
        hiddenPasswordField = {
            let field = NSSecureTextField(frame: .zero)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = true
            field.isSelectable = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.lineBreakMode = .byClipping
            field.usesSingleLineMode = true
            field.focusRingType = .none
            field.contentType = .oneTimeCode
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.cell?.sendsActionOnEndEditing = true
            (field.cell as? NSTextFieldCell)?.isScrollable = true
            field.setContentHuggingPriority(.init(750), for: .vertical)
            return field
        }()

        let revealPasswordButton = NSButton(frame: .zero)
        revealPasswordButton.translatesAutoresizingMaskIntoConstraints = false
        revealPasswordButton.setButtonType(.momentaryPushIn)
        revealPasswordButton.isBordered = false
        revealPasswordButton.bezelStyle = .shadowlessSquare
        revealPasswordButton.image = .secureEyeToggle
        revealPasswordButton.imagePosition = .imageOnly
        revealPasswordButton.title = ""
        revealPasswordButton.alignment = .center
        revealPasswordButton.target = self
        revealPasswordButton.action = #selector(onTogglePasswordVisibility(sender:))

        fireproofCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        fireproofCheck.translatesAutoresizingMaskIntoConstraints = false
        fireproofCheck.state = .on
        // `fireproofCheckDescription` is the cell, not the field, so keep the field in a local for layout.
        let fireproofDescriptionField = NSTextField(labelWithString: "")
        fireproofDescriptionField.translatesAutoresizingMaskIntoConstraints = false
        fireproofDescriptionField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        fireproofDescriptionField.isSelectable = true
        fireproofCheckDescription = fireproofDescriptionField.cell as? NSTextFieldCell

        let fireproofStack = NSStackView(views: [fireproofCheck, fireproofDescriptionField])
        fireproofStack.translatesAutoresizingMaskIntoConstraints = false
        fireproofStack.orientation = .vertical
        fireproofStack.distribution = .fill
        fireproofStack.alignment = .leading
        fireproofStack.spacing = 3
        fireproofStack.detachesHiddenViews = true

        let bottomSeparator = makeSeparator()

        // MARK: Bottom buttons
        saveButton = makeDialogButton(action: #selector(onSaveClicked(sender:)))
        updateButton = makeDialogButton(action: #selector(onSaveClicked(sender:)))
        dontUpdateButton = makeDialogButton(action: #selector(onDontUpdateClicked(_:)))
        openPasswordManagerButton = makeDialogButton(action: #selector(onOpenPasswordManagerClicked(sender:)))
        doneButton = makeDialogButton(action: #selector(onDoneClicked(sender:)))
        editButton = makeDialogButton(action: #selector(onEditClicked(sender:)))
        passwordManagerNotNowButton = makeDialogButton(action: #selector(onNotNowClicked(sender:)))

        notNowSegmentedControl = NSSegmentedControl()
        notNowSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        notNowSegmentedControl.isHidden = true
        notNowSegmentedControl.segmentCount = 2
        notNowSegmentedControl.segmentStyle = .rounded
        notNowSegmentedControl.segmentDistribution = .fillProportionally
        notNowSegmentedControl.trackingMode = .momentary
        notNowSegmentedControl.alignment = .left
        notNowSegmentedControl.setWidth(80, forSegment: 0)
        notNowSegmentedControl.setWidth(20, forSegment: 1)
        notNowSegmentedControl.setTag(1, forSegment: 1)
        notNowSegmentedControl.target = self
        notNowSegmentedControl.action = #selector(onNotNowSegmentedControlClicked(_:))
        notNowSegmentedControl.setContentHuggingPriority(.init(750), for: .vertical)
        notNowSegmentedControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        let lockImage = makeLogoImageView(.lockColor16)
        tooltipView = MouseOverView(frame: .zero)
        tooltipView.cornerRadius = 4
        tooltipView.autoresizingMask = [.width, .height, .minXMargin, .maxXMargin, .minYMargin, .maxYMargin]

        lockImageBackgroundView = NSBox()
        lockImageBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        lockImageBackgroundView.boxType = .custom
        lockImageBackgroundView.borderWidth = 0
        lockImageBackgroundView.cornerRadius = 4
        lockImageBackgroundView.titlePosition = .noTitle
        lockImageBackgroundView.addSubview(tooltipView)
        lockImageBackgroundView.addSubview(lockImage)

        var subviews: [NSView] = [backgroundBox, ddgPasswordManagerTitle, headerSeparator]
        subviews.append(contentsOf: [passwordManagerTitle, unlockPasswordManagerTitle, faviconImage] as [NSView])
        subviews.append(contentsOf: [domainLabel, usernameFieldTitleLabel, usernameField] as [NSView])
        subviews.append(contentsOf: [passwordFieldTitleLabel, visiblePasswordField, hiddenPasswordField] as [NSView])
        subviews.append(contentsOf: [revealPasswordButton, fireproofStack, bottomSeparator] as [NSView])
        subviews.append(contentsOf: [saveButton, notNowSegmentedControl, updateButton] as [NSView])
        subviews.append(contentsOf: [openPasswordManagerButton, dontUpdateButton, doneButton] as [NSView])
        subviews.append(contentsOf: [editButton, passwordManagerNotNowButton, lockImageBackgroundView] as [NSView])
        for subview in subviews {
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            backgroundBox.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: backgroundBox.trailingAnchor),
            backgroundBox.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: backgroundBox.bottomAnchor),

            ddgPasswordManagerTitle.heightAnchor.constraint(equalToConstant: LayoutConstants.headerHeight),
            ddgPasswordManagerTitle.topAnchor.constraint(equalTo: view.topAnchor),
            ddgPasswordManagerTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ])
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: ddgPasswordManagerTitle.trailingAnchor),
            titleLogo.widthAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            titleLogo.heightAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            titleLogo.leadingAnchor.constraint(equalTo: ddgPasswordManagerTitle.leadingAnchor,
                                               constant: LayoutConstants.headerInset),
            titleLogo.centerYAnchor.constraint(equalTo: ddgPasswordManagerTitle.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleLogo.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: titleLogo.centerYAnchor),
        ])
        NSLayoutConstraint.activate([
            ddgPasswordManagerTitle.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor,
                                                              constant: LayoutConstants.headerInset),

            passwordManagerTitle.heightAnchor.constraint(equalToConstant: LayoutConstants.headerHeight),
            passwordManagerTitle.topAnchor.constraint(equalTo: view.topAnchor),
            passwordManagerTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: passwordManagerTitle.trailingAnchor),
            bitwardenLogo.widthAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
        ])
        NSLayoutConstraint.activate([
            bitwardenLogo.heightAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            bitwardenLogo.leadingAnchor.constraint(equalTo: passwordManagerTitle.leadingAnchor,
                                                   constant: LayoutConstants.headerInset),
            bitwardenLogo.centerYAnchor.constraint(equalTo: passwordManagerTitle.centerYAnchor),
            passwordManagerTitleLabel.leadingAnchor.constraint(equalTo: bitwardenLogo.trailingAnchor, constant: 8),
            passwordManagerTitleLabel.centerYAnchor.constraint(equalTo: passwordManagerTitle.centerYAnchor, constant: -4.5),
            passwordManagerAccountLabel.leadingAnchor.constraint(equalTo: bitwardenLogo.trailingAnchor, constant: 8),
            passwordManagerAccountLabel.centerYAnchor.constraint(equalTo: passwordManagerTitle.centerYAnchor, constant: 9),
        ])
        NSLayoutConstraint.activate([

            unlockPasswordManagerTitle.heightAnchor.constraint(equalToConstant: LayoutConstants.headerHeight),
            unlockPasswordManagerTitle.topAnchor.constraint(equalTo: view.topAnchor),
            unlockPasswordManagerTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: unlockPasswordManagerTitle.trailingAnchor),
            unlockLogo.widthAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            unlockLogo.heightAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            unlockLogo.leadingAnchor.constraint(equalTo: unlockPasswordManagerTitle.leadingAnchor,
                                                constant: LayoutConstants.headerInset),
        ])
        NSLayoutConstraint.activate([
            unlockLogo.centerYAnchor.constraint(equalTo: unlockPasswordManagerTitle.centerYAnchor),
            unlockPasswordManagerTitleLabel.leadingAnchor.constraint(equalTo: unlockLogo.trailingAnchor, constant: 8),
            unlockPasswordManagerTitleLabel.centerYAnchor.constraint(equalTo: unlockPasswordManagerTitle.centerYAnchor),
            unlockPasswordManagerTitle.trailingAnchor.constraint(equalTo: unlockPasswordManagerTitleLabel.trailingAnchor,
                                                                 constant: LayoutConstants.headerInset),

            headerSeparator.widthAnchor.constraint(equalTo: view.widthAnchor),
            headerSeparator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        NSLayoutConstraint.activate([
            headerSeparator.bottomAnchor.constraint(equalTo: ddgPasswordManagerTitle.bottomAnchor),

            faviconImage.widthAnchor.constraint(equalToConstant: LayoutConstants.faviconSide),
            faviconImage.heightAnchor.constraint(equalToConstant: LayoutConstants.faviconSide),
            faviconImage.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.labelInset),
            domainLabel.leadingAnchor.constraint(equalTo: faviconImage.trailingAnchor, constant: 8),
            domainLabel.centerYAnchor.constraint(equalTo: faviconImage.centerYAnchor),
            domainLabel.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: 15),
        ])
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: domainLabel.trailingAnchor, constant: 16),

            usernameFieldTitleLabel.topAnchor.constraint(equalTo: domainLabel.bottomAnchor, constant: 15),
            usernameFieldTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.labelInset),
            usernameField.topAnchor.constraint(equalTo: usernameFieldTitleLabel.bottomAnchor, constant: 8),
            usernameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.fieldInset),
            view.trailingAnchor.constraint(equalTo: usernameField.trailingAnchor, constant: LayoutConstants.fieldInset),

            passwordFieldTitleLabel.topAnchor.constraint(equalTo: usernameField.bottomAnchor, constant: 12),
        ])
        NSLayoutConstraint.activate([
            passwordFieldTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.labelInset),
            hiddenPasswordField.topAnchor.constraint(equalTo: passwordFieldTitleLabel.bottomAnchor, constant: 8),
            hiddenPasswordField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.fieldInset),
            visiblePasswordField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.fieldInset),
            visiblePasswordField.widthAnchor.constraint(equalTo: hiddenPasswordField.widthAnchor),
            visiblePasswordField.centerYAnchor.constraint(equalTo: revealPasswordButton.centerYAnchor),

            revealPasswordButton.widthAnchor.constraint(equalToConstant: LayoutConstants.revealButtonSize.width),
        ])
        NSLayoutConstraint.activate([
            revealPasswordButton.heightAnchor.constraint(equalToConstant: LayoutConstants.revealButtonSize.height),
            revealPasswordButton.leadingAnchor.constraint(equalTo: hiddenPasswordField.trailingAnchor),
            revealPasswordButton.centerYAnchor.constraint(equalTo: hiddenPasswordField.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: revealPasswordButton.trailingAnchor, constant: 12),

            fireproofStack.topAnchor.constraint(equalTo: hiddenPasswordField.bottomAnchor, constant: 15),
            fireproofStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.fieldInset),
            view.trailingAnchor.constraint(equalTo: fireproofStack.trailingAnchor),
        ])
        NSLayoutConstraint.activate([
            fireproofDescriptionField.leadingAnchor.constraint(equalTo: fireproofStack.leadingAnchor,
                                                               constant: LayoutConstants.fieldInset),
            fireproofStack.trailingAnchor.constraint(equalTo: fireproofDescriptionField.trailingAnchor,
                                                     constant: LayoutConstants.fieldInset),

            bottomSeparator.widthAnchor.constraint(equalTo: view.widthAnchor),
            bottomSeparator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomSeparator.topAnchor.constraint(equalTo: fireproofStack.bottomAnchor, constant: 15),
        ])
        NSLayoutConstraint.activate([

            saveButton.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: LayoutConstants.buttonInset),
            view.bottomAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: LayoutConstants.bottomInset),
            saveButton.leadingAnchor.constraint(equalTo: notNowSegmentedControl.trailingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: notNowSegmentedControl.centerYAnchor),
            notNowSegmentedControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 101),

            updateButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        NSLayoutConstraint.activate([
            updateButton.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: updateButton.trailingAnchor, constant: LayoutConstants.buttonInset),
            view.bottomAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: LayoutConstants.bottomInset),
            updateButton.leadingAnchor.constraint(equalTo: dontUpdateButton.trailingAnchor, constant: 12),
            dontUpdateButton.heightAnchor.constraint(equalToConstant: 20),
            dontUpdateButton.centerYAnchor.constraint(equalTo: updateButton.centerYAnchor),

            openPasswordManagerButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: openPasswordManagerButton.trailingAnchor,
                                           constant: LayoutConstants.buttonInset),
            view.bottomAnchor.constraint(equalTo: openPasswordManagerButton.bottomAnchor,
                                         constant: LayoutConstants.bottomInset),
            openPasswordManagerButton.leadingAnchor.constraint(equalTo: passwordManagerNotNowButton.trailingAnchor,
                                                               constant: 12),
            passwordManagerNotNowButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            view.bottomAnchor.constraint(equalTo: passwordManagerNotNowButton.bottomAnchor,
                                         constant: LayoutConstants.bottomInset),
        ])
        NSLayoutConstraint.activate([

            doneButton.widthAnchor.constraint(equalToConstant: 80),
            doneButton.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: doneButton.trailingAnchor, constant: LayoutConstants.buttonInset),
            view.bottomAnchor.constraint(equalTo: doneButton.bottomAnchor, constant: LayoutConstants.bottomInset),
            doneButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 12),
            editButton.heightAnchor.constraint(equalToConstant: 20),
            editButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
        ])
        NSLayoutConstraint.activate([

            lockImageBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                             constant: LayoutConstants.lockBoxLeading),
            lockImageBackgroundView.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
            lockImage.topAnchor.constraint(equalTo: lockImageBackgroundView.topAnchor, constant: LayoutConstants.lockBoxInset),
            lockImage.leadingAnchor.constraint(equalTo: lockImageBackgroundView.leadingAnchor,
                                               constant: LayoutConstants.lockBoxInset),
            lockImageBackgroundView.trailingAnchor.constraint(equalTo: lockImage.trailingAnchor,
                                                              constant: LayoutConstants.lockBoxInset),
        ])
        NSLayoutConstraint.activate([
            lockImageBackgroundView.bottomAnchor.constraint(equalTo: lockImage.bottomAnchor,
                                                            constant: LayoutConstants.lockBoxInset),

        ])

        tooltipView.frame = lockImageBackgroundView.bounds.insetBy(dx: 5, dy: 5)

        self.view = view
    }

    init(fireproofDomains: FireproofDomains) {
        self.fireproofDomains = fireproofDomains
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(Self.self): Bad initializer")
    }

    private(set) var themeManager: ThemeManaging = NSApp.delegateTyped.themeManager

    override func viewDidLoad() {
        super.viewDidLoad()

        visiblePasswordField.isHidden = true
        saveButton.becomeFirstResponder()
        updateSaveSegmentedControl()
        setUpStrings()
        setUpSecurityInfoViews()

        subscribeToThemeChanges()
        applyThemeStyle()

        subscribeToFaviconCacheUpdates()
    }

    /// Favicons are lazy-loaded: `getCachedFaviconSafeForRendering(for:)` can miss the cache and return `nil`
    /// (we fall back to `.web`). When the image is decoded later, `.faviconCacheUpdated` is posted; re-run the
    /// favicon assignment so the placeholder is replaced with the real icon.
    private func subscribeToFaviconCacheUpdates() {
        NotificationCenter.default.publisher(for: .faviconCacheUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let domain = self.credentials?.account.domain else { return }
                // Refresh when the update relates to our domain, or defensively if no payload is present.
                if let update = notification.faviconsCacheUpdate, !update.hosts.contains(domain) {
                    return
                }
                self.loadFaviconForDomain(domain)
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updatePasswordFieldVisibility(visible: false)

        subscribeToPasswordManagerState()
    }

    override func viewWillDisappear() {
        passwordManagerStateCancellable = nil
        if shouldPostFirstPasswordSavedNotification {
            NotificationCenter.default.post(name: .firstPasswordSaved, object: nil)
        }
    }

    private func setUpStrings() {
        passwordManagerTitleLabel.stringValue = UserText.passwordManagementSaveCredentialsPasswordManagerTitle
        unlockPasswordManagerTitleLabel.stringValue = UserText.passwordManagementSaveCredentialsUnlockPasswordManager
        usernameFieldTitleLabel.stringValue = UserText.authAlertUsernamePlaceholder
        passwordFieldTitleLabel.stringValue = UserText.authAlertPasswordPlaceholder
        fireproofCheck.title = UserText.passwordManagementSaveCredentialsFireproofCheckboxTitle
        fireproofCheckDescription.title = UserText.passwordManagementSaveCredentialsFireproofCheckboxDescription
        saveButton.title = UserText.save
        notNowSegmentedControl.setLabel(UserText.dontSave, forSegment: 0)
        let fontAttributes = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
          let titleSize = (UserText.dontSave as NSString).size(withAttributes: fontAttributes)
        notNowSegmentedControl.setWidth(titleSize.width + 16, forSegment: 0)
        notNowSegmentedControl.setLabel(UserText.dontSave, forSegment: 0)
        updateButton.title = UserText.update
        openPasswordManagerButton.title = UserText.bitwardenPreferencesOpenBitwarden
        dontUpdateButton.title = UserText.dontUpdate
        doneButton.title = UserText.done
        editButton.title = UserText.edit
        passwordManagerNotNowButton.title = UserText.notNow
    }

    private func setUpSecurityInfoViews() {
        tooltipView.delegate = self
        lockImageBackgroundView.cornerRadius = lockImageBackgroundView.bounds.height / 2
        lockImageBackgroundView.fillColor = NSColor.infoHoverButton
        lockImageBackgroundView.boxType = .custom
    }

    /// Note that if the credentials.account.id is not nil, then we consider this an update rather than a save.
    func update(credentials: SecureVaultModels.WebsiteCredentials, automaticallySaved: Bool, backfilled: Bool) {
        self.credentials = credentials
        self.backfilled = backfilled
        self.domainLabel.stringValue = credentials.account.domain ?? ""
        self.usernameField.stringValue = credentials.account.username ?? ""
        self.hiddenPasswordField.stringValue = String(data: credentials.password ?? Data(), encoding: .utf8) ?? ""
        self.visiblePasswordField.stringValue = self.hiddenPasswordField.stringValue
        self.loadFaviconForDomain(credentials.account.domain)

        if let domain = credentials.account.domain, fireproofDomains.isFireproof(fireproofDomain: domain) {
            fireproofCheck.state = .on
        } else {
            fireproofCheck.state = .off
        }

        // Only use the non-editable state if a credential was automatically saved and it didn't already exist.
        let condition = credentials.account.id != nil && !(credentials.account.username?.isEmpty ?? true) && automaticallySaved
        updateViewState(editable: !condition)

        let existingCredentials = getExistingCredentialsFrom(credentials)
        evaluateCredentialsAndFirePixels(for: .displayed, credentials: existingCredentials, backfilled: backfilled)
    }

    private func updateViewState(editable: Bool) {
        usernameField.setEditable(editable)
        hiddenPasswordField.setEditable(editable)
        visiblePasswordField.setEditable(editable)

        if editable || passwordManagerCoordinator.isEnabled {
            notNowSegmentedControl.isHidden = passwordManagerCoordinator.isEnabled || credentials?.account.id != nil
            passwordManagerNotNowButton.isHidden = !passwordManagerCoordinator.isEnabled || credentials?.account.id != nil
            saveButton.isHidden = credentials?.account.id != nil || passwordManagerCoordinator.isLocked
            updateButton.isHidden = credentials?.account.id == nil || passwordManagerCoordinator.isLocked
            dontUpdateButton.isHidden = credentials?.account.id == nil
            openPasswordManagerButton.isHidden = !passwordManagerCoordinator.isLocked

            editButton.isHidden = true
            doneButton.isHidden = true

            ddgPasswordManagerTitle.isHidden = passwordManagerCoordinator.isEnabled
            passwordManagerTitle.isHidden = !passwordManagerCoordinator.isEnabled || passwordManagerCoordinator.isLocked
            passwordManagerAccountLabel.stringValue = UserText.passwordManagementSaveCredentialsAccountLabel(activeVault: passwordManagerCoordinator.activeVaultEmail ?? "")
            unlockPasswordManagerTitle.isHidden = !passwordManagerCoordinator.isEnabled || !passwordManagerCoordinator.isLocked
            titleLabel.stringValue = credentials?.account.id == nil ? UserText.pmSaveCredentialsEditableTitle : UserText.pmUpdateCredentialsTitle
            usernameField.makeMeFirstResponder()
        } else {
            notNowSegmentedControl.isHidden = true
            saveButton.isHidden = true
            updateButton.isHidden = true
            dontUpdateButton.isHidden = true

            editButton.isHidden = false
            doneButton.isHidden = false

            titleLabel.stringValue = UserText.pmSaveCredentialsNonEditableTitle
            view.window?.makeFirstResponder(nil)
        }
        let notNowTrailingToOpenPasswordConstraint = passwordManagerNotNowButton.trailingAnchor.constraint(equalTo: openPasswordManagerButton.leadingAnchor, constant: -12)
        let notNowTrailingToSaveButtonConstraint = passwordManagerNotNowButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12)
        let dontUpdateRrailingToOpenPasswordConstraint = dontUpdateButton.trailingAnchor.constraint(equalTo: openPasswordManagerButton.leadingAnchor, constant: -12)
        let dontUpdateTrailingToUpdateButtonConstraint = dontUpdateButton.trailingAnchor.constraint(equalTo: updateButton.leadingAnchor, constant: -12)
        if openPasswordManagerButton.isHidden {
            notNowTrailingToOpenPasswordConstraint.isActive = false
            dontUpdateRrailingToOpenPasswordConstraint.isActive = false
            notNowTrailingToSaveButtonConstraint.isActive = true
            dontUpdateTrailingToUpdateButtonConstraint.isActive = true
        } else {
            notNowTrailingToSaveButtonConstraint.isActive = false
            dontUpdateTrailingToUpdateButtonConstraint.isActive = false
            notNowTrailingToOpenPasswordConstraint.isActive = true
            dontUpdateRrailingToOpenPasswordConstraint.isActive = true
        }
    }

    private func updateSaveSegmentedControl() {
        if notNowSegmentedControl.segmentCount > 1 {
            notNowSegmentedControl.setShowsMenuIndicator(true, forSegment: 1)
        }
        notNowSegmentedControl.selectedSegment = -1
    }

    @objc func onSaveClicked(sender: Any?) {
        defer {
            self.delegate?.shouldCloseSaveCredentialsViewController(self)
        }

        var account = SecureVaultModels.WebsiteAccount(username: usernameField.stringValue.trimmingWhitespace(),
                                                       domain: domainLabel.stringValue)
        account.id = credentials?.account.id
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        let existingCredentials = getExistingCredentialsFrom(credentials)

        do {
            if passwordManagerCoordinator.isEnabled {
                guard !passwordManagerCoordinator.isLocked else {
                    Logger.sync.error("Failed to store credentials: Password manager is locked")
                    return
                }

                passwordManagerCoordinator.storeWebsiteCredentials(credentials) { error in
                    if let error = error {
                        Logger.sync.error("Failed to store credentials: \(error.localizedDescription)")
                    }
                }
            } else {
                let vault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared)
                _ = try vault.storeWebsiteCredentials(credentials)
                NSApp.delegateTyped.syncService?.scheduler.notifyDataChanged()
                Logger.sync.debug("Requesting sync if enabled")

                if existingCredentials?.account.id == nil, let count = try? vault.accountsCount(), count == 1 {
                    shouldPostFirstPasswordSavedNotification = true
                }
            }
        } catch {
            Logger.sync.error("failed to store credentials \(error.localizedDescription)")
            PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
        }

        NotificationCenter.default.post(name: .autofillSaveEvent, object: nil, userInfo: nil)

        evaluateCredentialsAndFirePixels(for: .confirmed, credentials: existingCredentials, backfilled: backfilled)

        PixelKit.fire(GeneralPixel.autofillItemSaved(kind: .password))

        if passwordManagerCoordinator.isEnabled {
            passwordManagerCoordinator.reportPasswordSave()
        }

        if let domain = account.domain {
            if self.fireproofCheck.state == .on {
                fireproofDomains.add(domain: domain)
            } else {
                // If the Fireproof checkbox has been unchecked, and the domain is Fireproof, then un-Fireproof it.
                guard fireproofDomains.isFireproof(fireproofDomain: domain) else { return }
                fireproofDomains.remove(domain: domain)
            }
        }
    }

    @objc func onDontUpdateClicked(_ sender: Any) {
        delegate?.shouldCloseSaveCredentialsViewController(self)

        let existingCredentials = getExistingCredentialsFrom(credentials)
        evaluateCredentialsAndFirePixels(for: .dismissed, credentials: existingCredentials, backfilled: backfilled)
    }

    @objc func onNotNowSegmentedControlClicked(_ sender: Any) {
        if notNowSegmentedControl.selectedSegment == 0 {
            onNotNowClicked(sender: sender)
        } else {
            displayMenuForSecondSegment()
        }
    }

    func displayMenuForSecondSegment() {
        let item = NSMenuItem(title: UserText.neverForThisSite, action: #selector(onNeverPromptClicked), target: self, keyEquivalent: "")
        let menu = NSMenu(title: "", items: [item])

        let segmentWidth = notNowSegmentedControl.bounds.width - 64.0
        let segmentFrame = CGRect(x: segmentWidth, y: 0, width: segmentWidth, height: notNowSegmentedControl.bounds.height)

        if let contentView = notNowSegmentedControl.window?.contentView {
            let menuOrigin = notNowSegmentedControl.convert(segmentFrame.origin, to: contentView)
            let finalMenuOrigin = CGPoint(x: menuOrigin.x, y: menuOrigin.y - segmentFrame.height - 5.0)
            menu.popUp(positioning: nil, at: finalMenuOrigin, in: contentView)
        }

    }

    @objc func onNotNowClicked(sender: Any?) {
        func notifyDelegate() {
            delegate?.shouldCloseSaveCredentialsViewController(self)
        }

        let existingCredentials = getExistingCredentialsFrom(credentials)
        evaluateCredentialsAndFirePixels(for: .dismissed, credentials: existingCredentials, backfilled: backfilled)

        guard NSApp.delegateTyped.dataClearingPreferences.isLoginDetectionEnabled else {
            notifyDelegate()
            return
        }

        guard let window = view.window else {
            Logger.sync.error("Window is nil")
            notifyDelegate()
            return
        }

        let host = domainLabel.stringValue
        // Don't ask if already fireproofed.
        guard !fireproofDomains.isFireproof(fireproofDomain: host) else {
            notifyDelegate()
            return
        }

        let alert = NSAlert.fireproofAlert(with: host.droppingWwwPrefix())
        alert.beginSheetModal(for: window) { response in
            if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                self.fireproofDomains.add(domain: host)
            }
            notifyDelegate()
        }

    }

    @objc func onNeverPromptClicked() {
        do {
            _ = try AutofillNeverPromptWebsitesManager.shared.saveNeverPromptWebsite(domainLabel.stringValue)
        } catch {
            Logger.sync.error("failed to save never prompt for website \(error.localizedDescription)")
        }
        PixelKit.fire(GeneralPixel.autofillLoginsSaveLoginModalExcludeSiteConfirmed)

        onNotNowClicked(sender: nil)
    }

    @objc func onOpenPasswordManagerClicked(sender: Any?) {
        passwordManagerCoordinator.openPasswordManager()
    }

    @objc func onEditClicked(sender: Any?) {
        updateViewState(editable: true)
    }

    @objc func onDoneClicked(sender: Any?) {
        delegate?.shouldCloseSaveCredentialsViewController(self)
    }

    @objc func onTogglePasswordVisibility(sender: Any?) {
        updatePasswordFieldVisibility(visible: !hiddenPasswordField.isHidden)
    }

    func loadFaviconForDomain(_ domain: String?) {
        guard let domain else {
            faviconImage.image = .web
            return
        }
        faviconImage.image = faviconManagement.getCachedFaviconSafeForRendering(for: domain, sizeCategory: .small)?.image ?? .web
    }

    private func updatePasswordFieldVisibility(visible: Bool) {
        if visible {
            visiblePasswordField.stringValue = hiddenPasswordField.stringValue
            visiblePasswordField.isHidden = false
            hiddenPasswordField.isHidden = true
        } else {
            hiddenPasswordField.stringValue = visiblePasswordField.stringValue
            hiddenPasswordField.isHidden = false
            visiblePasswordField.isHidden = true
        }
    }

    private func subscribeToPasswordManagerState() {
        guard let bitwardenManagement = passwordManagerCoordinator.bitwardenManagement else {
            return
        }

        passwordManagerStateCancellable = bitwardenManagement.statusPublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateViewState(editable: true)
            }
    }

    private func getExistingCredentialsFrom(_ credentials: SecureVaultModels.WebsiteCredentials?) -> SecureVaultModels.WebsiteCredentials? {
        guard let credentials = credentials, let id = credentials.account.id else {
            return nil
        }

        var existingCredentials: SecureVaultModels.WebsiteCredentials?

        if passwordManagerCoordinator.isEnabled {
            guard !passwordManagerCoordinator.isLocked else {
                Logger.sync.debug("Failed to access credentials: Password manager is locked")
                return existingCredentials
            }

            passwordManagerCoordinator.websiteCredentialsFor(accountId: id) { credentials, _ in
                existingCredentials = credentials
            }
        } else {
            if let idInt = Int64(id) {
                existingCredentials = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared).websiteCredentialsFor(accountId: idInt)
            }
        }

        return existingCredentials
    }

    private func isUsernameUpdated(credentials: SecureVaultModels.WebsiteCredentials) -> Bool {
        if credentials.account.username != self.usernameField.stringValue.trimmingWhitespace() {
            return true
        }
        return false
    }

    private func isPasswordUpdated(credentials: SecureVaultModels.WebsiteCredentials) -> Bool {
        if credentials.password != self.passwordData {
            return true
        }
        return false
    }

    private func evaluateCredentialsAndFirePixels(for action: Action, credentials: SecureVaultModels.WebsiteCredentials?, backfilled: Bool) {
        switch action {
        case .displayed:
            if let credentials = credentials {
                if isPasswordUpdated(credentials: credentials) {
                    PixelKit.fire(GeneralPixel.autofillLoginsUpdatePasswordInlineDisplayed, withAdditionalParameters: [backfilledKey: String(describing: backfilled)])
                } else {
                    PixelKit.fire(GeneralPixel.autofillLoginsUpdateUsernameInlineDisplayed, withAdditionalParameters: [backfilledKey: String(describing: backfilled)])
                }
            } else {
                if usernameField.stringValue.trimmingWhitespace().isEmpty {
                    PixelKit.fire(GeneralPixel.autofillLoginsSavePasswordInlineDisplayed, withAdditionalParameters: [backfilledKey: String(describing: backfilled)])
                } else {
                    PixelKit.fire(GeneralPixel.autofillLoginsSaveLoginInlineDisplayed, withAdditionalParameters: [backfilledKey: String(describing: backfilled)])
                }
            }
        case .confirmed, .dismissed:
            if let credentials = credentials {
                if isUsernameUpdated(credentials: credentials) {
                    let backfilled = credentials.account.username.isNilOrEmpty
                    firePixel(for: action,
                              confirmedPixel: GeneralPixel.autofillLoginsUpdateUsernameInlineConfirmed,
                              dismissedPixel: GeneralPixel.autofillLoginsUpdateUsernameInlineDismissed,
                              backfilled: backfilled)
                }
                if isPasswordUpdated(credentials: credentials) {
                    let backfilled = credentials.password.flatMap { String(data: $0, encoding: .utf8) }.isNilOrEmpty
                    firePixel(for: action,
                              confirmedPixel: GeneralPixel.autofillLoginsUpdatePasswordInlineConfirmed,
                              dismissedPixel: GeneralPixel.autofillLoginsUpdatePasswordInlineDismissed,
                              backfilled: backfilled)
                }
            } else {
                if usernameField.stringValue.trimmingWhitespace().isEmpty {
                    firePixel(for: action,
                              confirmedPixel: GeneralPixel.autofillLoginsSavePasswordInlineConfirmed,
                              dismissedPixel: GeneralPixel.autofillLoginsSavePasswordInlineDismissed,
                              backfilled: backfilled)
                } else {
                    firePixel(for: action,
                              confirmedPixel: GeneralPixel.autofillLoginsSaveLoginInlineConfirmed,
                              dismissedPixel: GeneralPixel.autofillLoginsSaveLoginInlineDismissed,
                              backfilled: backfilled)
                }
            }
        }
    }

    private func firePixel(for action: Action, confirmedPixel: PixelKit.Event, dismissedPixel: PixelKit.Event, backfilled: Bool) {
        let pixel = action == .confirmed ? confirmedPixel : dismissedPixel
        PixelKit.fire(pixel, withAdditionalParameters: [backfilledKey: String(describing: backfilled)])
    }
}

extension SaveCredentialsViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: any ThemeStyleProviding) {
        backgroundBox.fillColor = theme.colorsProvider.popoverBackgroundColor
    }
}
