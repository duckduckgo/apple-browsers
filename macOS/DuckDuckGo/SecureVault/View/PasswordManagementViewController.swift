//
//  PasswordManagementViewController.swift
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
import AppKitExtensions
import Carbon.HIToolbox
import BrowserServicesKit
import Combine
import Common
import DesignResourcesKit
import DesignResourcesKitIcons
import DDGSync
import Foundation
import FoundationExtensions
import SecureStorage
import SwiftUI
import SwiftUIExtensions
import PixelKit
import PrivacyConfig
import os.log

protocol PasswordManagementDelegate: AnyObject {

    /// May not be called on main thread.
    func shouldClosePasswordManagementViewController(_: PasswordManagementViewController)

}

final class PasswordManagementViewController: NSViewController {

    static func create(pinningManager: PinningManager) -> Self {
        let controller = Self(nibName: nil, bundle: nil)
        controller.pinningManager = pinningManager
        // Calling loadView() directly won't send viewDidLoad()
        _ = controller.view

        return controller
    }

    private enum LayoutConstants {
        static let contentSize = CGSize(width: 603, height: 510)
        static let innerSize = CGSize(width: 600, height: 510)
        static let headerHeight: CGFloat = 44
        static let inset: CGFloat = 16
        static let toolbarButtonSide: CGFloat = 28
        static let searchFieldWidth: CGFloat = 156
        static let listWidth: CGFloat = 250
        static let panelHeight: CGFloat = 466
        static let emptyStateSize = CGSize(width: 342, height: 464)
        static let emptyStateImageSize = CGSize(width: 128, height: 96)
        static let emptyStateTextWidth: CGFloat = 280
        static let emptyStateMessageHeight: CGFloat = 32
        static let emptyStateButtonWidth: CGFloat = 232
        static let emptyStateButtonHeight: CGFloat = 28
        static let unlockButtonSize = CGSize(width: 170, height: 28)
        static let cornerRadius: CGFloat = 4
    }

    var pinningManager: PinningManager!

    weak var delegate: PasswordManagementDelegate?

    var boxView: NSBox!
    var backgroundView: ColorView!
    var lockMenuItem: NSMenuItem!
    var importPasswordMenuItem: NSMenuItem!
    var exportLoginItem: NSMenuItem!
    var deleteAllPasswordsMenuItem: NSMenuItem!
    var settingsMenuItem: NSMenuItem!
    var unlockYourAutofillLabel: FlatButton!
    var autofillTitleLabel: NSTextField!
    var unlockYourAutofillInfo: NSButtonCell!
    var listContainer: NSView!
    var itemContainer: NSView!
    var addVaultItemButton: NSButton!
    var moreButton: NSButton!
    var searchField: SearchField!
    var divider: NSView!
    var emptyState: NSView!
    var emptyStateImageView: NSImageView!
    var emptyStateTitle: NSTextField!
    var emptyStateMessageHeight: NSLayoutConstraint!
    var emptyStateMessageContainer: NSView!
    var emptyStateImportButton: NSButton!
    var emptyStateSyncButton: NSButton!
    var lockScreen: NSView!
    var lockScreenIconImageView: NSImageView!

    var lockScreenDurationLabel: NSTextField!
    var lockScreenOpenInPreferencesButton: LinkButton!

    var emptyStateCancellable: AnyCancellable?
    var editingCancellable: AnyCancellable?
    var reloadDataAfterSyncCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    var domain: String?
    var isEditing = false
    var pendingRefresh = false
    var isDirty = false {
        didSet {
            listModel?.canChangeCategory = !isDirty
        }
    }

    var listModel: PasswordManagementItemListModel? {
        didSet {
            emptyStateCancellable?.cancel()
            emptyStateCancellable = nil

            emptyStateCancellable = listModel?.$emptyState.dropFirst().sink(receiveValue: { [weak self] newEmptyState in
                self?.updateEmptyState(state: newEmptyState)
            })
        }
    }

    var listView: NSView?

    var itemModel: PasswordManagementItemModel? {
        didSet {
            removeEscapeKeyMonitor()
            editingCancellable?.cancel()
            editingCancellable = nil

            editingCancellable = itemModel?.isEditingPublisher.sink(receiveValue: { [weak self] isEditing in
                guard let self = self else { return }

                self.isEditing = isEditing
                self.divider.isHidden = isEditing
                self.updateEmptyState(state: self.listModel?.emptyState)

                self.searchField.isEditable = !isEditing

                self.recalculateKeyViewLoop()

                if isEditing {
                    self.installEscapeKeyMonitor()
                } else {
                    self.removeEscapeKeyMonitor()
                }

                // If editing ended and we have a pending refresh, do it now
                if !isEditing && self.pendingRefresh {
                    Logger.sync.debug("Editing ended, executing pending refresh")
                    self.pendingRefresh = false
                    self.refreshData()
                }
            })
        }
    }

    var secureVault: (any AutofillSecureVault)? {
        try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared)
    }

    private let passwordManagerCoordinator: PasswordManagerCoordinating = Application.appDelegate.passwordManagerCoordinator

    private let emailManager = EmailManager()
    private let urlMatcher = AutofillDomainNameUrlMatcher()
    private let tld = NSApp.delegateTyped.tld
    private let urlSort = AutofillDomainNameUrlSort()
    private let syncButtonModel = SyncDeviceButtonModel()
    private lazy var privacyConfigurationManager: PrivacyConfigurationManaging = Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager

    private var escapeKeyMonitor: Any?

    private let themeManagerModel: ThemeManager = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?
    var themeManager: ThemeManaging {
        themeManagerModel
    }

    private func makeMoreButtonMenu() -> NSMenu {
        let glyphs = DesignSystemImages.Glyphs.Size12.self
        lockMenuItem = NSMenuItem(title: UserText.passwordManagementLock, action: #selector(toggleLock(_:)), target: self)
            .withImage(glyphs.lock, visibleOnMacOS27: true)
        importPasswordMenuItem = NSMenuItem(title: UserText.importPasswords, action: #selector(openImportBrowserDataWindow(_:)), target: self)
            .withImage(glyphs.import, visibleOnMacOS27: true)
        exportLoginItem = NSMenuItem(title: UserText.exportLogins, action: #selector(openExportLogins(_:)), target: self)
            .withImage(glyphs.export, visibleOnMacOS27: true)
        deleteAllPasswordsMenuItem = NSMenuItem(title: UserText.deleteAllPasswords, action: #selector(onDeleteAllPasswordsClicked(_:)), target: self)
            .withImage(glyphs.trash, visibleOnMacOS27: true)
        settingsMenuItem = NSMenuItem(title: UserText.settingsSuspended, action: #selector(openAutofillPreferences(_:)), target: self, keyEquivalent: ",")
            .withImage(glyphs.settings, visibleOnMacOS27: true)

        let menu = NSMenu {
            lockMenuItem
            importPasswordMenuItem
            exportLoginItem
            NSMenuItem.separator()
            deleteAllPasswordsMenuItem
            NSMenuItem.separator()
            settingsMenuItem
        }
        // menuNeedsUpdate(_:) swaps the Lock item between Lock and Unlock.
        menu.delegate = self
        return menu
    }

    private func makeToolbarButton(image: NSImage, action: Selector) -> MouseOverButton {
        let button = MouseOverButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .center
        button.mouseOverColor = .buttonMouseOver
        button.mouseDownColor = .buttonMouseDown
        button.cornerRadius = LayoutConstants.cornerRadius
        button.target = self
        button.action = action
        return button
    }

    private func makeEmptyStateButton(action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .roundRect
        // applyThemeStyle() fills these through the layer; the non-rebranded path re-enables the bezel.
        button.isBordered = false
        return button
    }

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: LayoutConstants.contentSize))
        view.translatesAutoresizingMaskIntoConstraints = false

        boxView = NSBox()
        boxView.translatesAutoresizingMaskIntoConstraints = false
        boxView.boxType = .custom
        boxView.borderWidth = 0
        boxView.cornerRadius = LayoutConstants.cornerRadius

        let contentView = NSView(frame: NSRect(origin: .zero, size: LayoutConstants.innerSize))
        contentView.translatesAutoresizingMaskIntoConstraints = false

        autofillTitleLabel = NSTextField(labelWithString: "")
        autofillTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        autofillTitleLabel.font = .systemFont(ofSize: 17)
        autofillTitleLabel.lineBreakMode = .byClipping

        addVaultItemButton = makeToolbarButton(image: .add, action: #selector(onNewClicked(_:)))
        moreButton = makeToolbarButton(image: .settings, action: #selector(moreButtonAction(_:)))
        moreButton.menu = makeMoreButtonMenu()

        searchField = SearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.wantsLayer = true
        searchField.focusRingType = .none
        searchField.lineBreakMode = .byClipping
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        searchField.isAutomaticTextCompletionEnabled = false
        searchField.usesSingleLineMode = true
        (searchField.cell as? NSSearchFieldCell)?.isScrollable = true
        searchField.setContentHuggingPriority(.init(750), for: .vertical)
        searchField.delegate = self

        let headerSeparator = NSBox()
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.boxType = .separator

        // These two are sized by frame rather than constraints: the list and detail views are swapped
        // in at runtime and set their own frame from the container's bounds.
        listContainer = NSView(frame: NSRect(x: 0, y: 0, width: LayoutConstants.listWidth, height: 467))
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        itemContainer = NSView(frame: NSRect(x: 249, y: 0, width: 351, height: LayoutConstants.panelHeight))
        itemContainer.translatesAutoresizingMaskIntoConstraints = false

        let dividerBox = NSBox(frame: NSRect(x: 248, y: 0, width: 5, height: LayoutConstants.panelHeight))
        dividerBox.translatesAutoresizingMaskIntoConstraints = false
        dividerBox.boxType = .separator
        dividerBox.setContentHuggingPriority(.init(750), for: .horizontal)
        divider = dividerBox

        // MARK: Empty state
        emptyStateImageView = NSImageView()
        emptyStateImageView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateImageView.setContentHuggingPriority(.init(251), for: .horizontal)
        emptyStateImageView.setContentHuggingPriority(.init(251), for: .vertical)

        emptyStateTitle = NSTextField(labelWithString: "")
        emptyStateTitle.translatesAutoresizingMaskIntoConstraints = false
        emptyStateTitle.alignment = .center
        emptyStateTitle.font = .systemFont(ofSize: 15, weight: .semibold)

        // The hosting view added in setUpEmptyStateMessageView() is frame-positioned against this
        // container, so it starts at the size the nib gave it rather than at zero.
        emptyStateMessageContainer = NSView(frame: NSRect(origin: .zero,
                                                          size: CGSize(width: LayoutConstants.emptyStateTextWidth,
                                                                       height: LayoutConstants.emptyStateMessageHeight)))
        emptyStateMessageContainer.translatesAutoresizingMaskIntoConstraints = false

        emptyStateImportButton = makeEmptyStateButton(action: #selector(onImportClicked(_:)))
        emptyStateSyncButton = makeEmptyStateButton(action: #selector(onSyncClicked(_:)))

        let emptyStateButtonsStack = NSStackView(views: [emptyStateImportButton, emptyStateSyncButton])
        emptyStateButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateButtonsStack.orientation = .vertical
        emptyStateButtonsStack.distribution = .fill
        emptyStateButtonsStack.alignment = .centerX
        emptyStateButtonsStack.spacing = 10
        emptyStateButtonsStack.detachesHiddenViews = true

        let emptyStateStack = NSStackView(views: [emptyStateImageView, emptyStateTitle,
                                                  emptyStateMessageContainer, emptyStateButtonsStack])
        emptyStateStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateStack.orientation = .vertical
        emptyStateStack.distribution = .fill
        emptyStateStack.alignment = .centerX
        emptyStateStack.spacing = 16
        emptyStateStack.detachesHiddenViews = true

        emptyState = NSView()
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(emptyStateStack)

        // MARK: Lock screen
        lockScreenIconImageView = NSImageView()
        lockScreenIconImageView.translatesAutoresizingMaskIntoConstraints = false
        lockScreenIconImageView.setContentHuggingPriority(.init(251), for: .horizontal)
        lockScreenIconImageView.setContentHuggingPriority(.init(251), for: .vertical)
        if DeviceAuthenticator.deviceSupportsBiometrics {
            lockScreenIconImageView.image = themeManager.isAppRebranded ? .lockTouchID128 : .loginsLockTouchIDLegacy
        } else {
            lockScreenIconImageView.image = themeManager.isAppRebranded ? .lockLocked128 : .loginsLockPasswordLegacy
        }

        unlockYourAutofillLabel = FlatButton(frame: .zero)
        unlockYourAutofillLabel.target = self
        unlockYourAutofillLabel.action = #selector(deviceAuthenticationRequested(_:))
        unlockYourAutofillLabel.translatesAutoresizingMaskIntoConstraints = false
        unlockYourAutofillLabel.setButtonType(.momentaryPushIn)
        unlockYourAutofillLabel.bezelStyle = .rounded
        unlockYourAutofillLabel.isBordered = false
        // It only holds first responder to keep the popover key; it should not look focused.
        unlockYourAutofillLabel.focusRingType = .none
        unlockYourAutofillLabel.alignment = .center
        unlockYourAutofillLabel.imageScaling = .scaleProportionallyDown
        unlockYourAutofillLabel.cornerRadius = 5
        unlockYourAutofillLabel.backgroundColor = .blackWhite10
        unlockYourAutofillLabel.horizontalPadding = 8
        unlockYourAutofillLabel.verticalPadding = 5
        unlockYourAutofillLabel.setContentHuggingPriority(.init(750), for: .vertical)
        unlockYourAutofillInfo = unlockYourAutofillLabel.cell as? NSButtonCell

        let lockScreenStack = NSStackView(views: [lockScreenIconImageView, unlockYourAutofillLabel])
        lockScreenStack.translatesAutoresizingMaskIntoConstraints = false
        lockScreenStack.orientation = .vertical
        lockScreenStack.distribution = .fill
        lockScreenStack.alignment = .centerX
        lockScreenStack.spacing = 12
        lockScreenStack.detachesHiddenViews = true

        lockScreenDurationLabel = NSTextField(labelWithString: "")
        lockScreenDurationLabel.translatesAutoresizingMaskIntoConstraints = false
        lockScreenDurationLabel.alignment = .center

        // Sized up front: a zero-width text view lays its text container out at a different width
        // than it is drawn at, which desynchronises the link's cursor rect from its glyphs.
        let preferencesLabel = NSTextField(labelWithString: UserText.pmLockScreenPreferencesLabel)
        preferencesLabel.translatesAutoresizingMaskIntoConstraints = false
        preferencesLabel.font = .systemFont(ofSize: 13)
        preferencesLabel.textColor = .blackWhite60

        lockScreenOpenInPreferencesButton = LinkButton(title: UserText.pmLockScreenPreferencesLink,
                                                       target: self,
                                                       action: #selector(openAutofillPreferences(_:)))
        lockScreenOpenInPreferencesButton.translatesAutoresizingMaskIntoConstraints = false
        lockScreenOpenInPreferencesButton.isBordered = false
        lockScreenOpenInPreferencesButton.font = .systemFont(ofSize: 13)
        lockScreenOpenInPreferencesButton.contentTintColor = NSColor(designSystemColor: .textLink,
                                                                     palette: themeManagerModel.designColorPalette)

        let preferencesStack = NSStackView(views: [preferencesLabel, lockScreenOpenInPreferencesButton])
        preferencesStack.translatesAutoresizingMaskIntoConstraints = false
        preferencesStack.orientation = .horizontal
        preferencesStack.alignment = .firstBaseline
        preferencesStack.spacing = 4

        backgroundView = ColorView(frame: .zero, backgroundColor: .neutralBackground, interceptClickEvents: true)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(lockScreenStack)
        backgroundView.addSubview(lockScreenDurationLabel)
        backgroundView.addSubview(preferencesStack)

        let lockScreenBox = NSBox()
        lockScreenBox.translatesAutoresizingMaskIntoConstraints = false
        lockScreenBox.boxType = .custom
        lockScreenBox.borderWidth = 0
        lockScreenBox.cornerRadius = LayoutConstants.cornerRadius
        lockScreenBox.titlePosition = .noTitle
        // NSBox sets its contentView's frame itself, so that has to be a frame-managed view;
        // `backgroundView` is constrained inside it.
        let lockScreenContentView = NSView()
        lockScreenContentView.addSubview(backgroundView)
        lockScreenBox.contentView = lockScreenContentView
        lockScreen = lockScreenBox

        contentView.addSubview(headerSeparator)
        contentView.addSubview(autofillTitleLabel)
        contentView.addSubview(listContainer)
        contentView.addSubview(itemContainer)
        contentView.addSubview(emptyState)
        contentView.addSubview(addVaultItemButton)
        contentView.addSubview(moreButton)
        contentView.addSubview(searchField)
        contentView.addSubview(divider)
        contentView.addSubview(lockScreen)

        view.addSubview(boxView)
        view.addSubview(contentView)

        emptyStateMessageHeight = emptyStateMessageContainer.heightAnchor
            .constraint(equalToConstant: LayoutConstants.emptyStateMessageHeight)

        NSLayoutConstraint.activate([
            boxView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            boxView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            boxView.widthAnchor.constraint(equalTo: view.widthAnchor),
            boxView.heightAnchor.constraint(equalTo: view.heightAnchor),

            contentView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentView.widthAnchor.constraint(equalToConstant: LayoutConstants.innerSize.width),
            contentView.heightAnchor.constraint(equalToConstant: LayoutConstants.innerSize.height),

            searchField.widthAnchor.constraint(equalToConstant: LayoutConstants.searchFieldWidth),
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            searchField.leadingAnchor.constraint(equalTo: addVaultItemButton.trailingAnchor, constant: 10),

            addVaultItemButton.widthAnchor.constraint(equalToConstant: LayoutConstants.toolbarButtonSide),
            addVaultItemButton.heightAnchor.constraint(equalToConstant: LayoutConstants.toolbarButtonSide),
            addVaultItemButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            moreButton.widthAnchor.constraint(equalToConstant: LayoutConstants.toolbarButtonSide),
            moreButton.heightAnchor.constraint(equalToConstant: LayoutConstants.toolbarButtonSide),
            moreButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 10),
            moreButton.centerYAnchor.constraint(equalTo: addVaultItemButton.centerYAnchor),
            contentView.trailingAnchor.constraint(equalTo: moreButton.trailingAnchor, constant: LayoutConstants.inset),

            autofillTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: LayoutConstants.inset),
            autofillTitleLabel.centerYAnchor.constraint(equalTo: addVaultItemButton.centerYAnchor),

            headerSeparator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: LayoutConstants.headerHeight),
            headerSeparator.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            headerSeparator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            emptyState.widthAnchor.constraint(equalToConstant: LayoutConstants.emptyStateSize.width),
            emptyState.heightAnchor.constraint(equalToConstant: LayoutConstants.emptyStateSize.height),
            emptyState.topAnchor.constraint(equalTo: headerSeparator.topAnchor),
            contentView.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor),

            emptyStateStack.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            emptyStateStack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor, constant: -20),
            emptyStateImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.emptyStateImageSize.width),
            emptyStateImageView.heightAnchor.constraint(equalToConstant: LayoutConstants.emptyStateImageSize.height),
            emptyStateTitle.widthAnchor.constraint(equalToConstant: LayoutConstants.emptyStateTextWidth),
            emptyStateMessageContainer.widthAnchor.constraint(equalToConstant: LayoutConstants.emptyStateTextWidth),
            emptyStateMessageHeight,
            emptyStateImportButton.heightAnchor.constraint(equalToConstant: LayoutConstants.emptyStateButtonHeight),
            emptyStateImportButton.widthAnchor
                .constraint(greaterThanOrEqualToConstant: LayoutConstants.emptyStateButtonWidth),
            emptyStateSyncButton.heightAnchor.constraint(equalToConstant: LayoutConstants.emptyStateButtonHeight),
            emptyStateSyncButton.widthAnchor.constraint(equalTo: emptyStateImportButton.widthAnchor),
            emptyStateImportButton.leadingAnchor.constraint(equalTo: emptyStateButtonsStack.leadingAnchor),
            emptyStateButtonsStack.trailingAnchor.constraint(equalTo: emptyStateImportButton.trailingAnchor),

            lockScreen.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            lockScreen.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: lockScreen.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: lockScreen.bottomAnchor),

            backgroundView.leadingAnchor.constraint(equalTo: lockScreenContentView.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: lockScreenContentView.topAnchor),
            lockScreenContentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            lockScreenContentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            lockScreenStack.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            lockScreenStack.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor, constant: -25),
            unlockYourAutofillLabel.widthAnchor.constraint(equalToConstant: LayoutConstants.unlockButtonSize.width),
            unlockYourAutofillLabel.heightAnchor.constraint(equalToConstant: LayoutConstants.unlockButtonSize.height),

            lockScreenDurationLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
            backgroundView.trailingAnchor.constraint(equalTo: lockScreenDurationLabel.trailingAnchor, constant: 20),

            preferencesStack.topAnchor.constraint(equalTo: lockScreenDurationLabel.bottomAnchor, constant: 2),
            preferencesStack.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: preferencesStack.bottomAnchor, constant: 20),
        ])

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Esc closes the popover. Handled as a key equivalent rather than through the responder
        // chain because displayLockScreen() clears the first responder, so nothing in the view
        // hierarchy is left to receive cancelOperation(_:).
        addKeyEquivalent(.escape, modifierFlags: []) { [weak self] _ in
            guard let self else { return false }
            dismiss()
            return true
        }

        createListView()
        createLoginItemView()
        setupStrings()
        reloadDataAfterSyncCancellable = bindSyncDidFinish()

        emptyStateTitle.attributedStringValue = NSAttributedString.make(emptyStateTitle.stringValue, lineHeight: 1.14, kern: -0.23)

        setUpEmptyStateMessageView()

        addVaultItemButton.toolTip = UserText.addItemTooltip
        moreButton.toolTip = UserText.moreOptionsTooltip

        addVaultItemButton.sendAction(on: .leftMouseDown)
        moreButton.sendAction(on: .leftMouseDown)

        exportLoginItem.title = UserText.exportLogins
        unlockYourAutofillInfo.setAccessibilityIdentifier("Unlock Autofill")
        addVaultItemButton.setAccessibilityIdentifier("add item")
        NotificationCenter.default.publisher(for: .deviceBecameLocked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.displayLockScreen()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dataImportComplete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)

        subscribeToThemeChanges()
        applyThemeStyle()

    }

    private func setUpEmptyStateMessageView() {
        guard let listModel else { return }

        let hostingView = NSHostingView(rootView: PasswordManagementEmptyStateMessage(
            message: listModel.emptyStateMessageDescription,
            image: listModel.emptyStateHideLockIcon ? nil : .lockSolid16,
            linkText: listModel.emptyStateHideLearnMoreLink ? nil : listModel.emptyStateMessageLinkText,
            linkAction: { [weak self] in self?.openEmptyStateLink() }
        ).fixedSize().environmentObject(themeManagerModel))

        hostingView.frame = CGRect(origin: .zero, size: hostingView.intrinsicContentSize)
        for subview in emptyStateMessageContainer.subviews {
            subview.removeFromSuperview()
        }
        emptyStateMessageContainer.addSubview(hostingView)
        emptyStateMessageHeight.constant = hostingView.intrinsicContentSize.height

        syncButtonModel.$shouldShowSyncButton.sink { [weak self] shouldShow in
            if !shouldShow {
                self?.emptyStateSyncButton.isHidden = true
            }
        }.store(in: &cancellables)
    }

    private func setupStrings() {
        unlockYourAutofillLabel.title = UserText.passwordManagerUnlockAutofill
        autofillTitleLabel.stringValue = UserText.passwordManagementTitle
        emptyStateTitle.stringValue = UserText.pmEmptyStateDefaultTitle
        setUpEmptyStateMessageView()
        emptyStateImportButton.title = listModel?.emptyStateImportButtonText ?? UserText.pmEmptyStateDefaultButtonTitle
        emptyStateSyncButton.title = listModel?.emptyStateSyncButtonText ?? UserText.pmEmptyStateSecondaryButtonTitlePasswords
    }

    private func bindSyncDidFinish() -> AnyCancellable? {
        guard let syncDataProviders = NSApp.delegateTyped.syncDataProviders else {
            return nil
        }

        var syncPublishers: [AnyPublisher<Void, Never>] = []
        syncPublishers.append(
            syncDataProviders.credentialsAdapter.syncDidCompletePublisher
                .eraseToAnyPublisher()
        )

        if let creditCardsAdapter = syncDataProviders.creditCardsAdapter {
            syncPublishers.append(
                creditCardsAdapter.syncDidCompletePublisher
                    .eraseToAnyPublisher()
            )
        }

        if let identitiesAdapter = syncDataProviders.identitiesAdapter {
            syncPublishers.append(
                identitiesAdapter.syncDidCompletePublisher
                    .eraseToAnyPublisher()
            )
        }

        return Publishers.MergeMany(syncPublishers)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                if self.isEditing {
                    Logger.sync.debug("Currently editing, deferring refresh")
                    self.pendingRefresh = true
                } else {
                    Logger.sync.debug("Sync completed, refreshing data")
                    self.refreshData()
                }
            }
    }

    private func toggleLockScreen(hidden: Bool) {
        if hidden {
            hideLockScreen()
            requestSync()
        } else {
            displayLockScreen()
        }
    }

    private func displayLockScreen() {
        lockScreen.isHidden = false
        searchField.isEnabled = false
        addVaultItemButton.isEnabled = false
        setContentHidden(true)

        moveFocusIntoPopover()
    }

    /// The popover's window is only key while something inside it holds first responder. With no
    /// first responder AppKit hands it back to the parent main window, which re-targets the WebView.
    private func moveFocusIntoPopover() {
        guard let window = view.window else { return }
        window.makeFirstResponder(lockScreen.isHidden ? searchField : unlockYourAutofillLabel)
    }

    private func hideLockScreen() {
        lockScreen.isHidden = true
        searchField.isEnabled = true
        addVaultItemButton.isEnabled = true
        setContentHidden(false)

        moveFocusIntoPopover()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        lockScreenDurationLabel.stringValue = UserText.pmLockScreenDuration(duration: AutofillPreferences().autoLockThreshold.title)

        if let listView = self.listView {
            listView.frame = listContainer.bounds
            listContainer.addSubview(listView)
        }

        refetchAndPromptForAuthentication(text: "", selectItemMatchingDomain: domain, clearWhenNoMatches: true)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        moveFocusIntoPopover()

        if !isDirty {
            itemModel?.clearSecureVaultModel()
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        listView?.removeFromSuperview()
        removeEscapeKeyMonitor()
    }

    deinit {
        removeEscapeKeyMonitor()
    }

    private func setContentHidden(_ hidden: Bool) {
        listContainer.isHidden = hidden
        itemContainer.isHidden = hidden

        if hidden {
            divider.isHidden = true
            emptyState.isHidden = true
        } else {
            divider.isHidden = isEditing
            updateEmptyState(state: listModel?.emptyState)
        }
    }

    private func refetchAndPromptForAuthentication(text: String, selectItemMatchingDomain: String?, clearWhenNoMatches: Bool) {
        refetchWithText("", selectItemMatchingDomain: domain, clearWhenNoMatches: true) { [weak self] items in
            self?.promptForAuthenticationIfNecessary(items: items)
        }
    }

    private func promptForAuthenticationIfNecessary(items: [SecureVaultItem]) {
        guard AppVersion.runType != .uiTests else {
            toggleLockScreen(hidden: true)
            return
        }
        guard !items.isEmpty else {
            toggleLockScreen(hidden: true)
            return
        }
        promptForAuthentication()
    }

    private func promptForAuthentication() {
        let authenticator = DeviceAuthenticator.shared
        toggleLockScreen(hidden: !authenticator.requiresAuthentication)

        authenticator.authenticateUser(reason: .unlockLogins) { authenticationResult in
            self.toggleLockScreen(hidden: authenticationResult.authenticated)
        }
    }

    @objc func onNewClicked(_ sender: NSButton) {
        let menu = createNewSecureVaultItemMenu()
        let location = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y - (sender.frame.height / 2) + 6)

        menu.popUp(positioning: nil, at: location, in: sender.superview)
    }

    @objc func moreButtonAction(_ sender: NSButton) {
        let location = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y - (sender.frame.height / 2) + 6)
        sender.menu?.popUp(positioning: nil, at: location, in: sender.superview)
    }

    @objc func openAutofillPreferences(_ sender: Any) {
        Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .autofill)
        self.dismiss()
    }

    private func openEmptyStateLink() {
        guard let url = listModel?.emptyStateMessageLinkURL else { return }
        Application.appDelegate.windowControllersManager.showTab(with: .url(url, source: .link))
        dismiss()
    }

    @objc func openImportBrowserDataWindow(_ sender: Any?) {
        self.dismiss()
        ensureMainWindowExists()
        DataImportFlowLauncher(pinningManager: pinningManager).launchDataImport(isDataTypePickerExpanded: true)
    }

    @objc func openExportLogins(_ sender: Any) {
        self.dismiss()
        ensureMainWindowExists()
        NSApp.sendAction(#selector(AppDelegate.openExportLogins(_:)), to: nil, from: sender)
    }

    @objc func onImportClicked(_ sender: NSButton) {
        self.dismiss()
        ensureMainWindowExists()
        DataImportFlowLauncher(pinningManager: pinningManager).launchDataImport(isDataTypePickerExpanded: true)
    }

    @objc func onSyncClicked(_ sender: Any) {
        self.dismiss()
        let source = SyncDeviceButtonTouchpoint.passwordsEmpty
        PixelKit.fire(SyncPromoPixelKitEvent.syncPromoConfirmed, withAdditionalParameters: ["source": source.rawValue])
        DeviceSyncCoordinator()?.startDeviceSyncFlow(source: source, completion: nil)
    }

    @objc func onDeleteAllPasswordsClicked(_ sender: Any) {
        let builder = AutofillDeleteAllPasswordsBuilder()
        guard let autofillDeleteAllPasswordsExecutor = builder.buildExecutor() else { return }
        let presenter = builder.buildPresenter()

        let needsWindow = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window == nil
        if needsWindow {
            self.dismiss()
            ensureMainWindowExists()
        }

        presenter.show(actionExecutor: autofillDeleteAllPasswordsExecutor) {
            self.refreshData {
                self.select(category: .logins)
            }
            PixelKit.fire(GeneralPixel.autofillManagementDeleteAllLogins)
        }
    }

    /// Opens a new browser window if no main window is currently available.
    /// This is needed when actions are triggered from the status bar popover
    /// without any browser window being open.
    private func ensureMainWindowExists() {
        if Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window == nil {
            Application.appDelegate.windowControllersManager.openNewWindow()
        }
    }

    @objc func deviceAuthenticationRequested(_ sender: NSButton) {
        promptForAuthentication()
    }

    @objc func toggleLock(_ sender: Any) {
        if DeviceAuthenticator.shared.requiresAuthentication {
            promptForAuthentication()
        } else {
            DeviceAuthenticator.shared.lock()
        }
    }

    private func refetchWithText(_ text: String,
                                 selectItemMatchingDomain: String? = nil,
                                 clearWhenNoMatches: Bool = false,
                                 completion: (([SecureVaultItem]) -> Void)? = nil) {
        let category = SecureVaultSorting.Category.allItems
        fetchSecureVaultItems(category: category) { [weak self] items in
            self?.listModel?.update(items: items)
            self?.searchField.stringValue = text
            self?.updateFilter()

            if clearWhenNoMatches && self?.listModel?.displayedSections.isEmpty == true {
                self?.searchField.stringValue = ""
                self?.updateFilter()
            } else if self?.isDirty == false {
                if let selectItemMatchingDomain = selectItemMatchingDomain {
                    self?.listModel?.selectLoginWithDomainOrFirst(domain: selectItemMatchingDomain)
                } else if let selectedItem = self?.listModel?.selected {
                    self?.listModel?.select(item: selectedItem)
                } else {
                    self?.listModel?.selectFirst()
                }
            }

            completion?(items)
        }
    }

    func postChange() {
        NotificationCenter.default.post(name: .PasswordManagerChanged, object: isDirty)
    }

    func clear() {
        self.listModel?.clear()
        self.itemModel?.clearSecureVaultModel()
    }

    func select(category: SecureVaultSorting.Category?) {
        guard let category = category else {
            return
        }

        if let descriptor = self.listModel?.sortDescriptor {
            self.listModel?.sortDescriptor = .init(category: category, parameter: descriptor.parameter, order: descriptor.order)
        } else {
            self.listModel?.sortDescriptor = .init(category: category, parameter: .title, order: .ascending)
        }
    }

    func select(websiteAccount: SecureVaultModels.WebsiteAccount) {
        listModel?.selected(item: SecureVaultItem.account(websiteAccount))
        if let descriptor = self.listModel?.sortDescriptor {
            self.listModel?.sortDescriptor = .init(category: .logins, parameter: descriptor.parameter, order: descriptor.order)
        } else {
            self.listModel?.sortDescriptor = .init(category: .logins, parameter: .title, order: .ascending)
        }

    }

    private func syncModelsOnCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, select: Bool = false) {
        self.itemModel?.setSecureVaultModel(credentials)
        self.listModel?.update(item: SecureVaultItem.account(credentials.account))

        if select {
            self.listModel?.selected(item: SecureVaultItem.account(credentials.account))
        }
    }

    private func syncModelsOnIdentity(_ identity: SecureVaultModels.Identity, select: Bool = false) {
        self.itemModel?.setSecureVaultModel(identity)
        self.listModel?.update(item: SecureVaultItem.identity(identity))

        if select {
            self.listModel?.selected(item: SecureVaultItem.identity(identity))
        }
    }

    private func syncModelsOnNote(_ note: SecureVaultModels.Note, select: Bool = false) {
        self.itemModel?.setSecureVaultModel(note)
        self.listModel?.update(item: SecureVaultItem.note(note))

        if select {
            self.listModel?.selected(item: SecureVaultItem.note(note))
        }
    }

    private func syncModelsOnCreditCard(_ card: SecureVaultModels.CreditCard, select: Bool = false) {
        self.itemModel?.setSecureVaultModel(card)
        self.listModel?.update(item: SecureVaultItem.card(card))

        if select {
            self.listModel?.selected(item: SecureVaultItem.card(card))
        }
    }

    private func createLoginItemView() {
        let itemModel = PasswordManagementLoginModel(onSaveRequested: { [weak self] credentials in
            self?.doSaveCredentials(credentials)
        }, onDeleteRequested: { [weak self] credentials in
            self?.promptToDelete(credentials: credentials)
        },
                                                     urlMatcher: urlMatcher,
                                                     emailManager: emailManager,
                                                     tld: tld,
                                                     urlSort: urlSort)

        self.itemModel = itemModel

        let view = NSHostingView(rootView: PasswordManagementLoginItemView().environmentObject(itemModel))
        replaceItemContainerChildView(with: view)
    }

    private func createIdentityItemView() {
        let itemModel = PasswordManagementIdentityModel(onDirtyChanged: { [weak self] isDirty in
            self?.isDirty = isDirty
            self?.postChange()
        }, onSaveRequested: { [weak self] note in
            self?.doSaveIdentity(note)
        }, onDeleteRequested: { [weak self] identity in
            self?.promptToDelete(identity: identity)
        })

        self.itemModel = itemModel

        let view = NSHostingView(rootView: PasswordManagementIdentityItemView().environmentObject(itemModel))
        replaceItemContainerChildView(with: view)
    }

    private func createNoteItemView() {
        let itemModel = PasswordManagementNoteModel(onDirtyChanged: { [weak self] isDirty in
            self?.isDirty = isDirty
            self?.postChange()
        }, onSaveRequested: { [weak self] note in
            self?.doSaveNote(note)
        }, onDeleteRequested: { [weak self] note in
            self?.promptToDelete(note: note)
        })

        self.itemModel = itemModel

        let view = NSHostingView(rootView: PasswordManagementNoteItemView().environmentObject(itemModel))
        replaceItemContainerChildView(with: view)
    }

    private func createCreditCardItemView() {
        let itemModel = PasswordManagementCreditCardModel(onDirtyChanged: { [weak self] isDirty in
            self?.isDirty = isDirty
            self?.postChange()
        }, onSaveRequested: { [weak self] card in
            self?.doSaveCreditCard(card)
        }, onDeleteRequested: { [weak self] card in
            self?.promptToDelete(card: card)
        })

        self.itemModel = itemModel

        let view = NSHostingView(rootView: PasswordManagementCreditCardItemView().environmentObject(itemModel))
        replaceItemContainerChildView(with: view)
    }

    private func clearSelectedItem() {
        itemContainer.subviews.forEach {
            $0.removeFromSuperview()
        }
    }

    private func replaceItemContainerChildView(with view: NSView) {
        emptyState.isHidden = true
        clearSelectedItem()

        view.frame = itemContainer.bounds
        view.wantsLayer = true
        view.layer?.masksToBounds = false

        itemContainer.addSubview(view)
        itemContainer.wantsLayer = true
        itemContainer.layer?.masksToBounds = false

        recalculateKeyViewLoop()
    }

    private func recalculateKeyViewLoop() {
        // Manually call NSWindow.recalculateKeyViewLoop() after the item view changes so that user can tab between text fields. This is necessary because MainWindow sets autorecalculatesKeyViewLoop to false.
        DispatchQueue.main.async {
            self.view.window?.recalculateKeyViewLoop()
        }
    }

    /// Install a local key monitor so Escape cancels the form even before any field has been focused.
    /// SwiftUI's .keyboardShortcut(.cancelAction) on the Cancel button only receives Escape once the
    /// user has focused a field and dismissed the form once. This monitor ensures Escape works
    /// immediately when the edit form is shown.
    private func installEscapeKeyMonitor() {
        guard escapeKeyMonitor == nil else { return }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == kVK_Escape,
                  let ourWindow = view.window else {
                return event
            }

            // Check that our window or parent is focused
            guard let keyWindow = NSApp.keyWindow,
                  keyWindow === ourWindow || keyWindow === ourWindow.parent else {
                return event
            }

            // Check the events are targetted at us or our parent
            guard event.window === ourWindow || event.window === ourWindow.parent else {
                return event
            }

            // Check that no sheets are presented
            let parentSheets = ourWindow.parent?.sheets ?? []
            guard ourWindow.sheets.isEmpty,
                  parentSheets.isEmpty else {
                return event
            }

            itemModel?.cancel()
            removeEscapeKeyMonitor()
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }

    private func doSaveCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) {
        let isNew = credentials.account.id == nil

        let isNoteWithoutDomain = (credentials.account.username?.isEmpty ?? true)
            && (credentials.account.domain?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)

        func showDuplicateAlert() {
            if let window = view.window {
                let alert = isNoteWithoutDomain ? NSAlert.passwordManagerNoteRequiresDomain() : NSAlert.passwordManagerDuplicateLogin()
                alert.beginSheetModal(for: window)
            }
        }

        do {
            if try secureVault?.hasAccountFor(username: credentials.account.username, domain: credentials.account.domain) == true && isNew {
                showDuplicateAlert()
                return
            }
            guard let id = try secureVault?.storeWebsiteCredentials(credentials),
                  let savedCredentials = try secureVault?.websiteCredentialsFor(accountId: id) else {
                return
            }

            itemModel?.cancel()
            if isNew {
                refetchWithText(searchField.stringValue) { [weak self] _ in
                    self?.syncModelsOnCredentials(savedCredentials, select: true)
                }
                NotificationCenter.default.post(name: .autofillSaveEvent, object: nil, userInfo: nil)
                PixelKit.fire(GeneralPixel.autofillManagementSaveLogin)
            } else {
                syncModelsOnCredentials(savedCredentials)
                PixelKit.fire(GeneralPixel.autofillManagementUpdateLogin)
            }
            postChange()
            requestSync()

        } catch {
            if case SecureStorageError.duplicateRecord = error {
                showDuplicateAlert()
            } else {
                PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
                if let window = view.window {
                    NSAlert.passwordManagerSaveError(errorType: error.localizedDescription).beginSheetModal(for: window)
                }
            }
        }
    }

    private func doSaveIdentity(_ identity: SecureVaultModels.Identity) {
        let isNew = identity.id == nil

        do {
            guard let storedIdentityID = try secureVault?.storeIdentity(identity),
                  let storedIdentity = try secureVault?.identityFor(id: storedIdentityID) else { return }

            itemModel?.cancel()
            if isNew {
                refetchWithText(searchField.stringValue) { [weak self] _ in
                    self?.syncModelsOnIdentity(storedIdentity, select: true)
                }
            } else {
                syncModelsOnIdentity(storedIdentity)
            }
            postChange()
            requestSync()

        } catch {
            PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
        }
    }

    private func doSaveNote(_ note: SecureVaultModels.Note) {
        let isNew = note.id == nil

        do {
            guard let storedNoteID = try secureVault?.storeNote(note),
                  let storedNote = try secureVault?.noteFor(id: storedNoteID) else { return }

            itemModel?.cancel()
            if isNew {
                refetchWithText(searchField.stringValue) { [weak self] _ in
                    self?.syncModelsOnNote(storedNote, select: true)
                }
            } else {
                syncModelsOnNote(storedNote)
            }
            postChange()

        } catch {
            // Which errors can occur when saving notes?
        }
    }

    private func doSaveCreditCard(_ card: SecureVaultModels.CreditCard) {
        let isNew = card.id == nil

        do {
            guard let storedCardID = try secureVault?.storeCreditCard(card),
                  let storedCard = try secureVault?.creditCardFor(id: storedCardID) else { return }

            itemModel?.cancel()
            if isNew {
                refetchWithText(searchField.stringValue) { [weak self] _ in
                    self?.syncModelsOnCreditCard(storedCard, select: true)
                }
            } else {
                syncModelsOnCreditCard(storedCard)
            }
            postChange()
            requestSync()

        } catch {
            PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
        }
    }

    private func promptToDelete(credentials: SecureVaultModels.WebsiteCredentials) {
        guard let window = self.view.window,
              let stringId = credentials.account.id,
              let id = Int64(stringId) else { return }

        let alert = NSAlert.passwordManagerConfirmDeleteLogin()
        alert.beginSheetModal(for: window) { response in

            switch response {
            case .alertFirstButtonReturn:
                do {
                    try self.secureVault?.deleteWebsiteCredentialsFor(accountId: id)
                    self.requestSync()
                    self.refreshData()
                    PixelKit.fire(GeneralPixel.autofillManagementDeleteLogin)
                } catch {
                    PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
                }

            default:
                break // cancel, do nothing
            }

        }
    }

    private func promptToDelete(identity: SecureVaultModels.Identity) {
        guard let window = self.view.window,
              let id = identity.id else { return }

        let alert = NSAlert.passwordManagerConfirmDeleteIdentity()
        alert.beginSheetModal(for: window) { response in

            switch response {
            case .alertFirstButtonReturn:
                do {
                    try self.secureVault?.deleteIdentityFor(identityId: id)
                    self.requestSync()
                    self.refreshData()
                } catch {
                    PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
                }

            default:
                break // cancel, do nothing
            }

        }
    }

    private func promptToDelete(note: SecureVaultModels.Note) {
        guard let window = self.view.window,
              let id = note.id else { return }

        let alert = NSAlert.passwordManagerConfirmDeleteNote()
        alert.beginSheetModal(for: window) { response in

            switch response {
            case .alertFirstButtonReturn:
                try? self.secureVault?.deleteNoteFor(noteId: id)
                self.refreshData()

            default:
                break // cancel, do nothing
            }

        }
    }

    private func promptToDelete(card: SecureVaultModels.CreditCard) {
        guard let window = self.view.window,
              let id = card.id else { return }

        let alert = NSAlert.passwordManagerConfirmDeleteCard()
        alert.beginSheetModal(for: window) { response in

            switch response {
            case .alertFirstButtonReturn:
                do {
                    try self.secureVault?.deleteCreditCardFor(cardId: id)
                    self.requestSync()
                    self.refreshData()
                } catch {
                    PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
                }

            default:
                break // cancel, do nothing
            }

        }
    }

    private func refreshData(completion: (() -> Void)? = nil) {
        self.itemModel?.clearSecureVaultModel()
        self.refetchWithText(self.searchField.stringValue) { _ in
            completion?()
        }
        self.postChange()
    }

    var passwordManagerSelectionCancellable: AnyCancellable?
    var syncPromoSelectionCancellable: AnyCancellable?

    private func createListView() {
        let listModel = PasswordManagementItemListModel(passwordManagerCoordinator: self.passwordManagerCoordinator, syncPromoManager: self.syncPromoManager, featureFlagger: Application.appDelegate.featureFlagger, onItemSelected: { [weak self] previousValue, newValue in
            guard let newValue = newValue,
                  let id = newValue.secureVaultID,
                  let window = self?.view.window else {
                self?.itemModel = nil
                self?.clearSelectedItem()

                return
            }

            func loadNewItemWithID() {
                do {
                    switch newValue {
                    case .account:
                        guard let credentials = try self?.secureVault?.websiteCredentialsFor(accountId: id) else { return }
                        self?.createLoginItemView()
                        self?.syncModelsOnCredentials(credentials)
                    case .card:
                        guard let card = try self?.secureVault?.creditCardFor(id: id) else { return }
                        self?.createCreditCardItemView()
                        self?.syncModelsOnCreditCard(card)
                    case .identity:
                        guard let identity = try self?.secureVault?.identityFor(id: id) else { return }
                        self?.createIdentityItemView()
                        self?.syncModelsOnIdentity(identity)
                    case .note:
                        guard let note = try self?.secureVault?.noteFor(id: id) else { return }
                        self?.createNoteItemView()
                        self?.syncModelsOnNote(note)
                    }
                } catch {
                    PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
                }
            }

            if self?.isDirty == true {
                let alert = NSAlert.passwordManagerSaveChangesToLogin()
                alert.beginSheetModal(for: window) { response in

                    switch response {
                    case .alertFirstButtonReturn: // Save
                        if self?.itemModel?.save() == true {
                            loadNewItemWithID()
                        } else {
                            // Validation failed, revert selection
                            if let previousValue {
                                self?.listModel?.select(item: previousValue, notify: false)
                            }
                        }

                    case .alertSecondButtonReturn: // Discard
                        self?.itemModel?.cancel()
                        loadNewItemWithID()

                    default: // Cancel
                        if let previousValue {
                            self?.listModel?.select(item: previousValue, notify: false)
                        }
                    }

                }
            } else {
                loadNewItemWithID()
            }
        }, onAddItemSelected: { [weak self] category in
            switch category {
            case .logins:
                self?.createNewLogin()
            case .identities:
                self?.createNewIdentity()
            case .cards:
                self?.createNewCreditCard()
            default:
                break
            }
        })

        self.listModel = listModel
        self.listView = NSHostingView(rootView: PasswordManagementItemListView()
            .environmentObject(themeManagerModel)
            .environmentObject(listModel))

        passwordManagerSelectionCancellable = listModel.$externalPasswordManagerSelected
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] value in
                if value {
                    self?.displayExternalPasswordManagerView()
                }
            }

        syncPromoSelectionCancellable = listModel.$syncPromoSelected
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] value in
                if value {
                    self?.displaySyncPromoView()
                }
            }

    }

    private func displayExternalPasswordManagerView() {
        let passwordManagerView = PasswordManagementBitwardenItemView(manager: Application.appDelegate.passwordManagerCoordinator) { [weak self] in
            self?.dismiss()
        }

        let view = NSHostingView(rootView: passwordManagerView)
        replaceItemContainerChildView(with: view)
    }

    private lazy var syncPromoManager: SyncPromoManaging = SyncPromoManager()

    private func displaySyncPromoView() {
        let touchpoint: SyncPromoManager.Touchpoint
        switch listModel?.sortDescriptor.category {
        case .allItems:
            touchpoint = .autofill
        case .logins:
            touchpoint = .passwords
        case .cards:
            touchpoint = .creditCards
        case .identities:
            touchpoint = .identities
        default:
            touchpoint = .passwords
        }

        let syncPromoViewModel = SyncPromoViewModel(
            isAppRebranded: themeManager.isAppRebranded,
            touchpointType: touchpoint,
            primaryButtonAction: { [weak self] in
                self?.syncPromoManager.goToSyncSettings(for: touchpoint)
                self?.dismiss()
            },
            dismissButtonAction: { [weak self] in
                self?.syncPromoManager.dismissPromoFor(touchpoint)
                self?.refreshData()
            }
        )

        let syncPromoView = SyncPromoView(viewModel: syncPromoViewModel, layout: .vertical)
        let view = NSHostingView(rootView: syncPromoView)
        replaceItemContainerChildView(with: view)
    }

    private func createNewSecureVaultItemMenu() -> NSMenu {
        return NSMenu {
            NSMenuItem(title: UserText.pmNewLogin, action: #selector(createNewLogin), target: self).withImage(.loginGlyph, visibleOnMacOS27: true)
            NSMenuItem(title: UserText.pmNewIdentity, action: #selector(createNewIdentity), target: self).withImage(.identityGlyph, visibleOnMacOS27: true)
            NSMenuItem(title: UserText.pmNewCard, action: #selector(createNewCreditCard), target: self).withImage(.creditCardGlyph, visibleOnMacOS27: true)
        }
    }

    private func updateFilter() {
        let text = searchField.stringValue.trimmingWhitespace()
        listModel?.filter = text
    }

    private func fetchSecureVaultItems(category: SecureVaultSorting.Category = .allItems, completion: @escaping ([SecureVaultItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [SecureVaultItem] = []

            do {
                switch category {
                case .allItems:
                    let accounts = try self.secureVault?.accounts() ?? []
                    let cards = try self.secureVault?.creditCards() ?? []
                    let notes = try self.secureVault?.notes() ?? []
                    let identities = try self.secureVault?.identities() ?? []

                    items = accounts.map(SecureVaultItem.account) +
                        cards.map(SecureVaultItem.card) +
                        notes.map(SecureVaultItem.note) +
                        identities.map(SecureVaultItem.identity)
                case .logins:
                    let accounts = try self.secureVault?.accounts() ?? []
                    items = accounts.map(SecureVaultItem.account)
                case .identities:
                    let identities = try self.secureVault?.identities() ?? []
                    items = identities.map(SecureVaultItem.identity)
                case .cards:
                    let cards = try self.secureVault?.creditCards() ?? []
                    items = cards.map(SecureVaultItem.card)
                }
            } catch {
                PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
            }

            DispatchQueue.main.async {
                self.emptyState.isHidden = !items.isEmpty
                completion(items)
            }
        }
    }

    @objc
    private func createNewCreditCard() {
        guard let window = view.window else { return }

        func createNew() {
            createCreditCardItemView()

            listModel?.clearSelection()
            itemModel?.createNew()
        }

        if isDirty {
            let alert = NSAlert.passwordManagerSaveChangesToLogin()
            alert.beginSheetModal(for: window) { response in

                switch response {
                case .alertFirstButtonReturn: // Save
                    if self.itemModel?.save() == true {
                        createNew()
                    }

                case .alertSecondButtonReturn: // Discard
                    self.itemModel?.cancel()
                    createNew()

                default: // Cancel
                    break // just do nothing
                }

            }
        } else {
            createNew()
        }
    }

    @objc
    private func createNewLogin() {
        guard let window = view.window else { return }

        func createNew() {
            createLoginItemView()

            listModel?.clearSelection()
            itemModel?.createNew()
        }

        if isDirty {
            let alert = NSAlert.passwordManagerSaveChangesToLogin()
            alert.beginSheetModal(for: window) { response in

                switch response {
                case .alertFirstButtonReturn: // Save
                    if self.itemModel?.save() == true {
                        createNew()
                    }

                case .alertSecondButtonReturn: // Discard
                    self.itemModel?.cancel()
                    createNew()

                default: // Cancel
                    break // just do nothing
                }

            }
        } else {
            createNew()
        }
    }

    @objc
    private func createNewIdentity() {
        guard let window = view.window else { return }

        func createNew() {
            createIdentityItemView()

            listModel?.clearSelection()
            itemModel?.createNew()
        }

        if isDirty {
            let alert = NSAlert.passwordManagerSaveChangesToLogin()
            alert.beginSheetModal(for: window) { response in

                switch response {
                case .alertFirstButtonReturn: // Save
                    if self.itemModel?.save() == true {
                        createNew()
                    }

                case .alertSecondButtonReturn: // Discard
                    self.itemModel?.cancel()
                    createNew()

                default: // Cancel
                    break // just do nothing
                }

            }
        } else {
            createNew()
        }
    }

    // MARK: - Empty State

    private func updateEmptyState(state: PasswordManagementItemListModel.EmptyState?) {
        guard let listModel = listModel else {
            return
        }

        if isEditing || state == nil || state == PasswordManagementItemListModel.EmptyState.none {
            hideEmptyState()
        } else {
            showEmptyState(category: listModel.sortDescriptor.category)
        }
    }

    private func showEmptyState(category: SecureVaultSorting.Category) {
        let isAppRebranded = themeManager.isAppRebranded
        let passwordsAddImage: NSImage = isAppRebranded ? .passwordsAdd128 : .passwordsAddLegacy128

        switch category {
        case .allItems:
            showEmptyState(image: passwordsAddImage, title: UserText.pmEmptyStateDefaultTitle, hideMessage: false, hideImportButton: false, hideSyncButton: false)
        case .logins:
            showEmptyState(image: passwordsAddImage, title: UserText.pmEmptyStateLoginsTitle, hideMessage: false, hideImportButton: false, hideSyncButton: false)
        case .identities:
            let identityAddImage: NSImage = isAppRebranded ? .identityAdd128 : .identityAddLegacy128
            showEmptyState(image: identityAddImage, title: UserText.pmEmptyStateIdentitiesTitle, hideMessage: false, hideImportButton: true, hideSyncButton: !privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.syncIdentities))
        case .cards:
            let creditCardsAddImage: NSImage = isAppRebranded ? .creditCardsAdd128 : .creditCardsAddLegacy128
            showEmptyState(image: creditCardsAddImage, title: UserText.pmEmptyStateCardsTitle, hideMessage: false, hideImportButton: true, hideSyncButton: !privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.syncCreditCards))
        }
    }

    private func hideEmptyState() {
        emptyState.isHidden = true
    }

    private func showEmptyState(image: NSImage, title: String, hideMessage: Bool = true, hideImportButton: Bool = true, hideSyncButton: Bool = true) {
        emptyState.isHidden = false
        emptyStateImageView.image = image
        emptyStateTitle.attributedStringValue = NSAttributedString.make(title, lineHeight: 1.14, kern: -0.23)
        if !hideMessage {
            setUpEmptyStateMessageView()
        }
        emptyStateImportButton.isHidden = hideImportButton
        emptyStateSyncButton.isHidden = hideSyncButton || !syncButtonModel.shouldShowSyncButton
        emptyStateMessageContainer.isHidden = hideMessage

        // Setting title to empty string when hidden since there is a width constraint dependency between the import and sync buttons
        let importTitle = hideImportButton ? "" : (listModel?.emptyStateImportButtonText ?? UserText.pmEmptyStateDefaultButtonTitle)
        let syncTitle = listModel?.emptyStateSyncButtonText ?? UserText.pmEmptyStateSecondaryButtonTitlePasswords

        emptyStateImportButton.title = importTitle
        emptyStateSyncButton.title = syncTitle

        if themeManager.isAppRebranded {
            emptyStateImportButton.layer?.cornerRadius = 14
            emptyStateSyncButton.layer?.cornerRadius = 14
        } else {
            emptyStateImportButton.isBordered = true
            emptyStateSyncButton.isBordered = true
            emptyStateImportButton.bezelStyle = .rounded
            emptyStateSyncButton.bezelStyle = .rounded
        }
    }

    private func requestSync() {
        guard let syncService = NSApp.delegateTyped.syncService else {
            return
        }
        Logger.sync.debug("Requesting sync if enabled")
        syncService.scheduler.requestSyncImmediately()
    }
}

extension PasswordManagementViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        let colorsProvider = theme.colorsProvider
        boxView.fillColor = colorsProvider.passwordManagerBackgroundColor
        backgroundView.backgroundColor = colorsProvider.passwordManagerLockScreenBackgroundColor

        let palette = theme.palette
        searchField.borderColor = palette.controlsBorderPrimary
        searchField.borderHighlightColor = palette.accentPrimary
        searchField.innerBackgroundColor = palette.surfaceTertiary

        guard themeManager.isAppRebranded else {
            return
        }

        NSAppearance.withAppAppearance {
            emptyStateImportButton.wantsLayer = true
            emptyStateSyncButton.wantsLayer = true

            emptyStateImportButton.contentTintColor = palette.accentContentPrimary
            emptyStateSyncButton.contentTintColor = palette.textPrimary

            emptyStateImportButton.layer?.backgroundColor = palette.accentPrimary.cgColor
            emptyStateSyncButton.layer?.backgroundColor = palette.controlsFillPrimary.cgColor
        }
    }
}

extension PasswordManagementViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let lockItem = menu.items.first(where: { $0.action == #selector(toggleLock(_:)) }) {
            let authenticator = DeviceAuthenticator.shared
            if authenticator.shouldAutoLockLogins {
                lockItem.isHidden = false
                lockItem.title = authenticator.requiresAuthentication ? UserText.passwordManagementUnlock : UserText.passwordManagementLock
            } else {
                lockItem.isHidden = true
            }
        }
    }

}

extension PasswordManagementViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        updateFilter()
    }
}

extension PasswordManagementViewController: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(PasswordManagementViewController.onDeleteAllPasswordsClicked(_:)):
            return haveDuckDuckGoPasswords
        default:
            guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return false }
            return appDelegate.validateMenuItem(menuItem)
        }
    }

    private var haveDuckDuckGoPasswords: Bool {
        guard let vault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared) else { return false }
        let accounts = (try? vault.accounts()) ?? []
        return !accounts.isEmpty
    }
}

struct PasswordManagementEmptyStateMessage: View {
    @EnvironmentObject var themeManager: ThemeManager

    let message: String
    let image: ImageResource?

    /// `nil` hides the link.
    let linkText: String?
    let linkAction: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            description
                .multilineTextAlignment(.center)
                .frame(width: 280)

            if let linkText {
                TextButton(linkText,
                           textColor: Color(designSystemColor: .textLink,
                                            palette: themeManager.designColorPalette),
                           action: linkAction)
            }
        }
    }

    private var description: Text {
        let text = Text(.init(message))
            .foregroundColor(.textSecondary)

        guard let image else { return text }

        return Text(Image(image))
            .baselineOffset(-1.0)
            .foregroundColor(.textSecondary)
        + Text(verbatim: " ")
        + text
    }
}
