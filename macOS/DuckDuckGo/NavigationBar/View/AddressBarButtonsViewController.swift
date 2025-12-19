//
//  AddressBarButtonsViewController.swift
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
import Cocoa
import Combine
import Common
import Lottie
import os.log
import PrivacyConfig
import PrivacyDashboard
import PixelKit
import AppKitExtensions
import AIChat
import UIComponents
import DesignResourcesKitIcons

// MARK: - Toggle Interaction Tracking

extension UserDefaults {
    private static let hasInteractedWithToggleKey = "aichat.hasInteractedWithSearchDuckAIToggle"

    var hasInteractedWithSearchDuckAIToggle: Bool {
        get { bool(forKey: Self.hasInteractedWithToggleKey) }
        set { set(newValue, forKey: Self.hasInteractedWithToggleKey) }
    }

    static func resetToggleInteractionFlag() {
        UserDefaults.standard.hasInteractedWithSearchDuckAIToggle = false
    }
}

protocol AddressBarButtonsViewControllerDelegate: AnyObject {

    func addressBarButtonsViewControllerCancelButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerHideAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerHideAskAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerHideSearchModeToggleClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerOpenAIChatSettingsButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController)
    func addressBarButtonsViewControllerSearchModeToggleChanged(_ addressBarButtonsViewController: AddressBarButtonsViewController, isAIChatMode: Bool)
}

final class AddressBarButtonsViewController: NSViewController {

    private enum Constants {
        static let askAiChatButtonHorizontalPadding: CGFloat = 6
        static let askAiChatButtonAnimationDuration: TimeInterval = 0.2
    }

    weak var delegate: AddressBarButtonsViewControllerDelegate?

    private let accessibilityPreferences: AccessibilityPreferences
    private let tabsPreferences: TabsPreferences
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let permissionManager: PermissionManagerProtocol

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private var permissionAuthorizationPopover: PermissionAuthorizationPopover?
    private func permissionAuthorizationPopoverCreatingIfNeeded() -> PermissionAuthorizationPopover {
        return permissionAuthorizationPopover ?? {
            let popover = PermissionAuthorizationPopover(featureFlagger: featureFlagger)
            NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose), name: NSPopover.didCloseNotification, object: popover)
            NotificationCenter.default.addObserver(self, selector: #selector(popoverWillShow), name: NSPopover.willShowNotification, object: popover)
            self.permissionAuthorizationPopover = popover
            popover.setAccessibilityIdentifier("AddressBarButtonsViewController.permissionAuthorizationPopover")
            return popover
        }()
    }

    private var permissionCenterPopover: PermissionCenterPopover?

    private var popupBlockedPopover: PopupBlockedPopover?
    private func popupBlockedPopoverCreatingIfNeeded() -> PopupBlockedPopover {
        return popupBlockedPopover ?? {
            let popover = PopupBlockedPopover(featureFlagger: featureFlagger)
            popover.delegate = self
            self.popupBlockedPopover = popover
            return popover
        }()
    }

    @IBOutlet weak var zoomButton: AddressBarButton!
    @IBOutlet weak var privacyDashboardButton: MouseOverAnimationButton!
    @IBOutlet weak var separator: NSView!
    @IBOutlet weak var bookmarkButton: AddressBarButton!
    @IBOutlet weak var imageButtonWrapper: NSView!
    @IBOutlet weak var imageButton: NSButton!
    @IBOutlet weak var cancelButton: AddressBarButton!
    @IBOutlet private weak var buttonsContainer: NSStackView!
    @IBOutlet weak var permissionCenterButton: AddressBarButton!
    @IBOutlet private weak var trailingButtonsContainer: NSStackView!
    @IBOutlet weak var aiChatButton: AddressBarMenuButton!
    @IBOutlet weak var askAIChatButton: AddressBarMenuButton!
    @IBOutlet weak var trailingButtonsBackground: ColorView!

    @IBOutlet weak var animationWrapperView: NSView!
    var shieldAnimationView: LottieAnimationView!
    var shieldDotAnimationView: LottieAnimationView!
    private var hasShieldAnimationCompleted = false
    @IBOutlet weak var privacyShieldLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var animationWrapperViewLeadingConstraint: NSLayoutConstraint!

    @IBOutlet weak var leadingAIChatDivider: NSImageView!
    @IBOutlet weak var trailingAIChatDivider: NSImageView!
    @IBOutlet weak var trailingStackViewTrailingViewConstraint: NSLayoutConstraint!

    private(set) var searchModeToggleControl: CustomToggleControl?
    private var searchModeToggleWidthConstraint: NSLayoutConstraint?
    private var wasToggleVisible: Bool = false
    @IBOutlet weak var notificationAnimationView: NavigationBarBadgeAnimationView!
    @IBOutlet weak var bookmarkButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var bookmarkButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var cancelButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var cancelButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var aiChatButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var aiChatButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var askAIChatButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var permissionCenterButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var askAIChatButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var privacyShieldButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var privacyShieldButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var imageButtonLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var zoomButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var geolocationButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var microphoneButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var cameraButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var popupsButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var externalSchemeButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var permissionButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet private weak var permissionButtons: NSView!
    @IBOutlet weak var cameraButton: PermissionButton! {
        didSet {
            cameraButton.isHidden = true
            cameraButton.target = self
            cameraButton.action = #selector(cameraButtonAction(_:))
        }
    }
    @IBOutlet weak var microphoneButton: PermissionButton! {
        didSet {
            microphoneButton.isHidden = true
            microphoneButton.target = self
            microphoneButton.action = #selector(microphoneButtonAction(_:))
        }
    }
    @IBOutlet weak var geolocationButton: PermissionButton! {
        didSet {
            geolocationButton.isHidden = true
            geolocationButton.target = self
            geolocationButton.action = #selector(geolocationButtonAction(_:))
        }
    }
    @IBOutlet weak var popupsButton: PermissionButton! {
        didSet {
            popupsButton.isHidden = true
            popupsButton.target = self
            popupsButton.action = #selector(popupsButtonAction(_:))
        }
    }
    @IBOutlet weak var externalSchemeButton: PermissionButton! {
        didSet {
            externalSchemeButton.isHidden = true
            externalSchemeButton.target = self
            externalSchemeButton.action = #selector(externalSchemeButtonAction(_:))
        }
    }
    @IBOutlet weak var notificationButton: PermissionButton? {
        didSet {
            notificationButton?.isHidden = true
            notificationButton?.target = self
            notificationButton?.action = #selector(notificationButtonAction(_:))
        }
    }
    @IBOutlet weak var notificationButtonHeightConstraint: NSLayoutConstraint?

    /// Width of the left buttons container (Privacy Dashboard button, Permissions buttons…)
    /// Used to adjust the Passive Address Bar leading constraint
    @Published private(set) var buttonsWidth: CGFloat = 0
    /// Width of the right buttons container (Bookmark button, AI Chat button…)
    /// Used to adjust the Passive Address Bar trailing constraint
    @Published private(set) var trailingButtonsWidth: CGFloat = 0

    private let onboardingPixelReporter: OnboardingAddressBarReporting

    private var tabCollectionViewModel: TabCollectionViewModel
    private var tabViewModel: TabViewModel? {
        didSet {
            popovers?.closeZoomPopover()
            subscribeToTabZoomLevel()
        }
    }

    private let popovers: NavigationBarPopovers?
    private let bookmarkManager: BookmarkManager

    var controllerMode: AddressBarViewController.Mode? {
        didSet {
            updateButtons()
        }
    }
    var isTextFieldEditorFirstResponder = false {
        didSet {
            updateButtons()
            stopHighlightingPrivacyShield()
            if isTextFieldEditorFirstResponder {
                // Hide shield when address bar is focused
                updatePrivacyEntryPointIcon()
            } else {
                // Restore shield when address bar loses focus
                hasShieldAnimationCompleted = false
                shieldAnimationView?.currentFrame = 1
                updatePrivacyEntryPointIcon()
            }
        }
    }
    var textFieldValue: AddressBarTextField.Value? {
        didSet {
            updateButtons()
        }
    }
    var isMouseOverNavigationBar = false {
        didSet {
            if isMouseOverNavigationBar != oldValue {
                updateBookmarkButtonVisibility()
            }
        }
    }

    var shouldShowDaxLogInAddressBar: Bool {
        self.tabViewModel?.tab.content == .newtab && theme.addressBarStyleProvider.shouldShowNewSearchIcon
    }

    private var isInPopUpWindow: Bool {
        tabCollectionViewModel.isPopup
    }

    private var cancellables = Set<AnyCancellable>()
    private var urlCancellable: AnyCancellable?
    private var zoomLevelCancellable: AnyCancellable?
    private var permissionsCancellables = Set<AnyCancellable>()
    private var trackerAnimationTriggerCancellable: AnyCancellable?
    private var privacyEntryPointIconUpdateCancellable: AnyCancellable?

    private var lastNotificationType: NavigationBarBadgeAnimationView.AnimationType?
    private var lastNotifiedURL: URL?

    private lazy var buttonsBadgeAnimator = {
        let animator = NavigationBarBadgeAnimator()
        animator.delegate = self
        return animator
    }()

    private var hasPrivacyInfoPulseQueuedAnimation = false

    required init?(coder: NSCoder) {
        fatalError("AddressBarButtonsViewController: Bad initializer")
    }

    private let aiChatTabOpener: AIChatTabOpening
    private let aiChatAddressBarPromptExtractor: AIChatAddressBarPromptExtractor
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatSidebarPresenter: AIChatSidebarPresenting
    private let aiChatSettings: AIChatPreferencesStorage

    private(set) lazy var aiChatTogglePopoverCoordinator: AIChatTogglePopoverCoordinating? = {
        AIChatTogglePopoverCoordinator(windowControllersManager: NSApp.delegateTyped.windowControllersManager)
    }()

    init?(coder: NSCoder,
          tabCollectionViewModel: TabCollectionViewModel,
          bookmarkManager: BookmarkManager,
          privacyConfigurationManager: PrivacyConfigurationManaging,
          permissionManager: PermissionManagerProtocol,
          accessibilityPreferences: AccessibilityPreferences,
          tabsPreferences: TabsPreferences,
          popovers: NavigationBarPopovers?,
          onboardingPixelReporter: OnboardingAddressBarReporting = OnboardingPixelReporter(),
          aiChatTabOpener: AIChatTabOpening,
          aiChatAddressBarPromptExtractor: AIChatAddressBarPromptExtractor = AIChatAddressBarPromptExtractor(),
          aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
          aiChatSidebarPresenter: AIChatSidebarPresenting,
          aiChatSettings: AIChatPreferencesStorage,
          themeManager: ThemeManaging = NSApp.delegateTyped.themeManager,
          featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.accessibilityPreferences = accessibilityPreferences
        self.tabsPreferences = tabsPreferences
        self.popovers = popovers
        self.onboardingPixelReporter = onboardingPixelReporter
        self.aiChatTabOpener = aiChatTabOpener
        self.aiChatAddressBarPromptExtractor = aiChatAddressBarPromptExtractor
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatSidebarPresenter = aiChatSidebarPresenter
        self.aiChatSettings = aiChatSettings
        self.themeManager = themeManager
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.permissionManager = permissionManager
        super.init(coder: coder)
    }

    deinit {
#if DEBUG
        if isLazyVar(named: "buttonsBadgeAnimator", initializedIn: self) {
            buttonsBadgeAnimator.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        }
        permissionAuthorizationPopover?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        popupBlockedPopover?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        notificationAnimationView?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        shieldAnimationView?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        shieldDotAnimationView?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        animationWrapperView?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupAnimationViews()
        setupNotificationAnimationView()
        setupSearchModeToggleControl()
        subscribeToSelectedTabViewModel()
        subscribeToBookmarkList()
        subscribeToEffectiveAppearance()
        subscribeToIsMouseOverAnimationVisible()
        updateBookmarkButtonVisibility()
        subscribeToPrivacyEntryPointIsMouseOver()
        subscribeToButtonsVisibility()
        subscribeToAIChatPreferences()
        subscribeToAIChatSidebarPresenter()
        subscribeToThemeChanges()

        applyThemeStyle()

        (view as? AddressBarButtonsView)?.onMouseDown = { [weak self] in
            self?.stopAnimations()
        }
    }

    private func setupButtons() {
        if isInPopUpWindow {
            privacyDashboardButton.position = .free
            cameraButton.position = .free
            geolocationButton.position = .free
            popupsButton.position = .free
            microphoneButton.position = .free
            externalSchemeButton.position = .free
            bookmarkButton.isHidden = true
            trailingButtonsContainer.isHidden = true
            trailingButtonsBackground.isHidden = true
        } else {
            bookmarkButton.position = .right
            privacyDashboardButton.position = .left
        }

        privacyDashboardButton.sendAction(on: .leftMouseUp)

        (imageButton.cell as? NSButtonCell)?.highlightsBy = NSCell.StyleMask(rawValue: 0)

        cameraButton.sendAction(on: .leftMouseDown)
        cameraButton.setAccessibilityIdentifier("AddressBarButtonsViewController.cameraButton")
        cameraButton.setAccessibilityTitle(UserText.permissionCamera)
        microphoneButton.sendAction(on: .leftMouseDown)
        microphoneButton.setAccessibilityIdentifier("AddressBarButtonsViewController.microphoneButton")
        microphoneButton.setAccessibilityTitle(UserText.permissionMicrophone)
        geolocationButton.sendAction(on: .leftMouseDown)
        geolocationButton.setAccessibilityIdentifier("AddressBarButtonsViewController.geolocationButton")
        geolocationButton.setAccessibilityTitle(UserText.permissionGeolocation)
        popupsButton.sendAction(on: .leftMouseDown)
        popupsButton.setAccessibilityTitle(UserText.permissionPopups)
        popupsButton.setAccessibilityIdentifier("AddressBarButtonsViewController.popupsButton")
        externalSchemeButton.sendAction(on: .leftMouseDown)
        // externalSchemeButton.accessibilityTitle is set in `updatePermissionButtons`
        externalSchemeButton.setAccessibilityIdentifier("AddressBarButtonsViewController.externalSchemeButton")

        privacyDashboardButton.setAccessibilityRole(.button)
        privacyDashboardButton.setAccessibilityElement(true)
        privacyDashboardButton.setAccessibilityIdentifier("AddressBarButtonsViewController.privacyDashboardButton")
        privacyDashboardButton.setAccessibilityTitle(UserText.privacyDashboardButton)
        privacyDashboardButton.toolTip = UserText.privacyDashboardTooltip

        bookmarkButton.sendAction(on: .leftMouseDown)
        bookmarkButton.setAccessibilityIdentifier("AddressBarButtonsViewController.bookmarkButton")
        // bookmarkButton.accessibilityTitle is set in `updateBookmarkButtonImage`

        configureAIChatButton()
        configureAskAIChatButton()
        configureContextMenuForAIChatButtons()

        setupButtonsCornerRadius()
        setupButtonsSize()
        setupButtonIcons()
        setupButtonPaddings()
    }

    func setupButtonPaddings(isFocused: Bool = false) {
        guard theme.addressBarStyleProvider.shouldAddPaddingToAddressBarButtons else { return }

        imageButtonLeadingConstraint.constant = isFocused ? 2 : 1
        animationWrapperViewLeadingConstraint.constant = 1

        if let superview = privacyDashboardButton.superview {
            privacyDashboardButton.translatesAutoresizingMaskIntoConstraints = false
            privacyShieldLeadingConstraint.constant = isFocused ? 6 : 5
            NSLayoutConstraint.activate([
                privacyDashboardButton.topAnchor.constraint(equalTo: superview.topAnchor, constant: 2),
                privacyDashboardButton.bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -2)
            ])
        }

        if let superview = aiChatButton.superview {
            aiChatButton.translatesAutoresizingMaskIntoConstraints = false
            if featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
                /// When the toggle is enabled we need a fixed constant, otherwise the stackview feels wobbly
                trailingStackViewTrailingViewConstraint.constant = 4
            } else {
                trailingStackViewTrailingViewConstraint.constant = isFocused ? 4 : 3
            }
            NSLayoutConstraint.activate([
                aiChatButton.topAnchor.constraint(equalTo: superview.topAnchor, constant: 2),
                aiChatButton.bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -2)
            ])
        }
    }

    override func viewWillAppear() {
        setupButtons()

        // Store reference to DraggingDestinationView for popup window dragging
        if isInPopUpWindow {
            guard let customView = view as? AddressBarButtonsView else {
                assertionFailure("AddressBarButtonsViewController.view should be AddressBarButtonsView")
                return
            }
            assert(type(of: view.superview) == NSView?.self)
            guard let nextResponder = view.superview?.nextResponder as? DraggingDestinationView else {
                assertionFailure("Expected DraggingDestinationView as next responder, got \(view.superview?.nextResponder ??? "<nil>")")
                return
            }
            customView.draggingDestinationView = nextResponder
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        // The permission popover leaks when its parent window is closed while it's still visible, so this workaround
        // forces it to deallocate when the window is closing. This workaround can be removed if the true source of
        // the leak is found.
        if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
            permissionAuthorizationPopover.close()
        }

        for case let .some(animationView) in [shieldDotAnimationView, shieldAnimationView] {
            animationView.stop()
        }
        notificationAnimationView?.removeAnimation()
    }

    func showBadgeNotification(_ type: NavigationBarBadgeAnimationView.AnimationType) {
        let priority: NavigationBarBadgeAnimator.AnimationPriority
        switch type {
        case .trackersBlocked:
            priority = .high
        case .cookiePopupManaged, .cookiePopupHidden:
            priority = .low
        }

        // Disable hover animation while badge/shield animations are playing
        privacyDashboardButton.isAnimationEnabled = false

        // Use priority queue system - animator tracks the current animation type
        buttonsBadgeAnimator.enqueueAnimation(
            type,
            priority: priority,
            tab: tabViewModel?.tab,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationAnimationView
        )
    }

    /// Shows a tracker notification with the count of trackers blocked
    /// - Parameter count: Number of trackers blocked
    func showTrackerNotification(count: Int) {
        guard count > 0 else { return }
        showBadgeNotification(.trackersBlocked(count: count))
    }

    private func playPrivacyInfoHighlightAnimationIfNecessary() {
        if hasPrivacyInfoPulseQueuedAnimation {
            hasPrivacyInfoPulseQueuedAnimation = false
            // Give a bit of delay to have a better animation effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                ViewHighlighter.highlight(view: self.privacyDashboardButton, inParent: self.view)
            }
        }
    }

    var mouseEnterExitTrackingArea: NSTrackingArea?

    override func viewDidLayout() {
        super.viewDidLayout()
        if !isInPopUpWindow {
            updateTrackingAreaForHover()
        }
        self.buttonsWidth = buttonsContainer.frame.size.width + 10.0
        self.trailingButtonsWidth = trailingButtonsContainer.frame.size.width + 14.0
    }

    func updateTrackingAreaForHover() {
        if let previous = mouseEnterExitTrackingArea {
            view.removeTrackingArea(previous)
        }
        let trackingArea = NSTrackingArea(rect: view.frame, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: view, userInfo: nil)
        view.addTrackingArea(trackingArea)
        mouseEnterExitTrackingArea = trackingArea
    }

    private func subscribeToSelectedTabViewModel() {
        tabCollectionViewModel.$selectedTabViewModel.sink { [weak self] tabViewModel in
            guard let self else { return }
            // Stop visual animations but let the animator handle queue management
            // The animator's handleTabSwitch preserves animations for the current tab
            stopAnimations(badgeAnimations: false)
            if let tab = tabViewModel?.tab {
                buttonsBadgeAnimator.handleTabSwitch(to: tab)
            } else {
                // No tab selected, clear all pending animations
                buttonsBadgeAnimator.cancelPendingAnimations()
            }
            closePrivacyDashboard()
            closePermissionPopovers()

            self.tabViewModel = tabViewModel
            subscribeToUrl()
            subscribeToPermissions()
            subscribeToPrivacyEntryPointIconUpdateTrigger()

            updatePrivacyEntryPointIcon()
            updateAIChatButtonState()
        }.store(in: &cancellables)
    }

    private func subscribeToUrl() {
        guard let tabViewModel else {
            urlCancellable = nil
            return
        }
        urlCancellable = tabViewModel.tab.$content
            .combineLatest(tabViewModel.tab.$error)
            .sink { [weak self] _ in
                guard let self else { return }

                // Cancel all animations and reset state on navigation
                stopAnimations()
                lastNotifiedURL = nil
                lastNotificationType = nil
                hasShieldAnimationCompleted = false
                updateBookmarkButtonImage()
                updateButtons()
                updatePrivacyEntryPointIcon()
                configureAIChatButton()
                subscribeToTrackerAnimationTrigger()
            }
    }

    private func subscribeToTrackerAnimationTrigger() {
        trackerAnimationTriggerCancellable = tabViewModel?.trackersAnimationTriggerPublisher
            .sink { [weak self] _ in
                self?.animateTrackers()
            }
    }

    private func subscribeToPermissions() {
        permissionsCancellables.removeAll(keepingCapacity: true)

        // Dispatch to next run loop to ensure UI updates after Combine propagation
        tabViewModel?.$usedPermissions.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateAllPermissionButtons()
        }.store(in: &permissionsCancellables)
        tabViewModel?.tab.popupHandling?.pageInitiatedPopupPublisher.sink { [weak self] _ in
            self?.updateAllPermissionButtons()
        }.store(in: &permissionsCancellables)
        tabViewModel?.$permissionAuthorizationQuery
            .receive(on: DispatchQueue.main)
            .dropFirst().sink { [weak self] _ in
                self?.updateAllPermissionButtons()
        }.store(in: &permissionsCancellables)
    }

    private func subscribeToPrivacyEntryPointIconUpdateTrigger() {
        privacyEntryPointIconUpdateCancellable = tabViewModel?.privacyEntryPointIconUpdateTrigger
            .sink { [weak self] _ in
                self?.updatePrivacyEntryPointIcon()
            }
    }

    private func subscribeToBookmarkList() {
        bookmarkManager.listPublisher.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            updateBookmarkButtonImage()
            updateBookmarkButtonVisibility()
        }.store(in: &cancellables)
    }

    // update Separator on Privacy Entry Point and other buttons appearance change
    private func subscribeToButtonsVisibility() {
        privacyDashboardButton.publisher(for: \.isHidden).asVoid()
            .merge(with: permissionButtons.publisher(for: \.frame).asVoid())
            .merge(with: zoomButton.publisher(for: \.isHidden).asVoid())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateSeparator()
            }
            .store(in: &cancellables)
    }

    private func subscribeToAIChatPreferences() {
        aiChatMenuConfig.valuesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] in
                self?.updateAIChatButtonVisibility()
                self?.updateAskAIChatButtonVisibility()
                self?.configureAIChatButton()
                self?.updateButtons()
            }).store(in: &cancellables)
    }

    private func subscribeToAIChatSidebarPresenter() {
        aiChatSidebarPresenter.sidebarPresenceWillChangePublisher
            .sink { [weak self] change in
                guard let self, change.tabID == tabViewModel?.tab.uuid else {
                    return
                }
                updateAIChatButtonStateForSidebar(change.isShown)
                updateAskAIChatButtonVisibility(isSidebarOpen: change.isShown)
            }
            .store(in: &cancellables)
    }

    private func updateLegacyPermissionButtons() {
        // Prevent crash if Combine subscriptions outlive view lifecycle
        guard isViewLoaded else { return }
        guard let tabViewModel else { return }

        guard !featureFlagger.isFeatureOn(.newPermissionView) else {
            permissionButtons.isShown = false
            return
        }

        // Show permission buttons when there's a requested permission on NTP even if address bar is focused,
        // since NTP has the address bar focused by default
        let hasRequestedPermission = tabViewModel.usedPermissions.values.contains(where: { $0.isRequested })
        let shouldShowWhileFocused = (tabViewModel.tab.content == .newtab) && hasRequestedPermission

        permissionButtons.isShown = (shouldShowWhileFocused || !isTextFieldEditorFirstResponder)
        && !tabViewModel.isShowingErrorPage
        defer {
            showOrHidePermissionPopoverIfNeeded()
        }

        geolocationButton.buttonState = tabViewModel.usedPermissions.geolocation

        let (camera, microphone) = PermissionState?.combineCamera(tabViewModel.usedPermissions.camera,
                                                                  withMicrophone: tabViewModel.usedPermissions.microphone)
        cameraButton.buttonState = camera
        microphoneButton.buttonState = microphone

        // Show pop-up button when there's a blocked pop-up (permission is requested)
        if tabViewModel.usedPermissions.popups?.isRequested == true {
            popupsButton.buttonState = tabViewModel.usedPermissions.popups
        } else if featureFlagger.isFeatureOn(.popupBlocking),
                  featureFlagger.isFeatureOn(.popupPermissionButtonPersistence) {
            let pageInitiatedPopupOpened = tabViewModel.tab.popupHandling?.pageInitiatedPopupOpened ?? false
            // Keep button visible (as .inactive) when a page-initiated pop-up was allowed or opened by the current page (always allowed)
            popupsButton.buttonState = pageInitiatedPopupOpened ? .inactive : tabViewModel.usedPermissions.popups // .inactive or nil
        } else {
            popupsButton.buttonState = nil
        }
        externalSchemeButton.buttonState = tabViewModel.usedPermissions.externalScheme
        let title = String(format: UserText.permissionExternalSchemeOpenFormat, tabViewModel.usedPermissions.first(where: { $0.key.isExternalScheme })?.key.localizedDescription ?? "")
        externalSchemeButton.setAccessibilityTitle(title)

        notificationButton?.buttonState = tabViewModel.usedPermissions.notification
        notificationButton?.setAccessibilityTitle(UserText.permissionNotification)
    }

    private func showOrHidePermissionPopoverIfNeeded() {
        guard let tabViewModel else { return }

        for permission in tabViewModel.usedPermissions.keys {
            guard case .requested(let query) = tabViewModel.usedPermissions[permission] else { continue }
            let permissionAuthorizationPopover = permissionAuthorizationPopoverCreatingIfNeeded()
            guard !permissionAuthorizationPopover.isShown else {
                if permissionAuthorizationPopover.viewController.query === query { return }
                permissionAuthorizationPopover.close()
                return
            }
            openPermissionAuthorizationPopover(for: query)
            return
        }
        if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
            permissionAuthorizationPopover.close()
        }

    }

    private func updateAllPermissionButtons() {
        // Legacy permission buttons
        updateLegacyPermissionButtons()

        // New permission button
        updatePermissionCenterButton()
    }

    // MARK: - Permission Center

    private func updatePermissionCenterButton() {
        // Prevent crash if Combine subscriptions outlive view lifecycle
        guard isViewLoaded else { return }
        guard let tabViewModel else { return }

        guard featureFlagger.isFeatureOn(.newPermissionView) else {
            permissionCenterButton.isShown = false
            return
        }

        // Only update icon if no authorization popover is currently shown
        // (icon updates during active popover are handled by openPermissionAuthorizationPopover)
        let isAuthorizationPopoverShown = permissionAuthorizationPopover?.isShown == true || popupBlockedPopover?.isShown == true
        if !isAuthorizationPopoverShown {
            // Find the first requested permission type (authorization will be shown)
            let requestedPermissionType = tabViewModel.usedPermissions.first { $0.value.isRequested }?.key
            // Show permission-specific icon if authorization popover will be presented
            updatePermissionCenterButtonIcon(forRequestedPermission: requestedPermissionType)
        }

        // Check if there are any persisted permissions for the current domain
        let domain = tabViewModel.tab.content.urlForWebView?.host ?? ""
        let hasAnyPersistedPermissions = permissionManager.hasAnyPermissionPersisted(forDomain: domain)

        permissionCenterButton.isShown = tabViewModel.shouldShowPermissionCenterButton(
            isTextFieldEditorFirstResponder: isTextFieldEditorFirstResponder,
            hasAnyPersistedPermissions: hasAnyPersistedPermissions
        )

        showOrHidePermissionCenterPopoverIfNeeded()
    }

    private func updatePermissionCenterButtonIcon(forRequestedPermission permissionType: PermissionType? = nil) {
        guard featureFlagger.isFeatureOn(.newPermissionView) else { return }
        permissionCenterButton.image = permissionType?.icon ?? DesignSystemImages.Glyphs.Size16.permissions
    }

    private func showOrHidePermissionCenterPopoverIfNeeded() {
        guard let tabViewModel else { return }

        // Collect all requested permissions
        var requestedQueries: [(PermissionType, PermissionAuthorizationQuery)] = []
        for permission in tabViewModel.usedPermissions.keys {
            if case .requested(let query) = tabViewModel.usedPermissions[permission] {
                requestedQueries.append((permission, query))
            }
        }

        // If no requested permissions, close popover if shown
        guard let (_, query) = requestedQueries.first else {
            if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
                // Don't close if authorization is still in progress (e.g., waiting for user to click Allow/Deny in two-step flow)
                guard !permissionAuthorizationPopover.viewController.isAuthorizationInProgress else { return }
                permissionAuthorizationPopover.close()
            }
            return
        }

        let permissionAuthorizationPopover = permissionAuthorizationPopoverCreatingIfNeeded()

        // If popover is not shown, open it
        guard permissionAuthorizationPopover.isShown else {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        // If showing the same query, nothing to do
        if permissionAuthorizationPopover.viewController.query === query { return }

        // Don't close if authorization is still in progress (e.g., waiting for user to click Allow/Deny in two-step flow)
        if permissionAuthorizationPopover.viewController.isAuthorizationInProgress { return }

        // Close old popover and immediately open new one for the pending query
        permissionAuthorizationPopover.close()
        openPermissionAuthorizationPopover(for: query)
    }

    private func updateBookmarkButtonImage(isUrlBookmarked: Bool = false) {
        let bookmarksIconsProvider = theme.iconsProvider.bookmarksIconsProvider
        let colorsProvider = theme.colorsProvider
        let palette = theme.palette

        if let url = tabViewModel?.tab.content.userEditableUrl,
           isUrlBookmarked || bookmarkManager.isAnyUrlVariantBookmarked(url: url)
        {
            bookmarkButton.image = bookmarksIconsProvider.bookmarkFilledIcon
            bookmarkButton.mouseOverTintColor = palette.iconsPrimary
            bookmarkButton.toolTip = UserText.editBookmarkTooltip
            bookmarkButton.setAccessibilityValue("Bookmarked")
            bookmarkButton.setAccessibilityTitle(UserText.editBookmarkTooltip)
        } else {
            bookmarkButton.mouseOverTintColor = nil
            bookmarkButton.image = bookmarksIconsProvider.bookmarkIcon
            bookmarkButton.contentTintColor = colorsProvider.iconsColor
            bookmarkButton.toolTip = ShortcutTooltip.bookmarkThisPage.value
            bookmarkButton.setAccessibilityValue("Unbookmarked")
            bookmarkButton.setAccessibilityTitle(UserText.addBookmarkTooltip)
        }
    }

    private func updateImageButton() {
        guard let tabViewModel else { return }

        imageButton.contentTintColor = theme.colorsProvider.iconsColor
        imageButton.image = nil
        switch controllerMode {
        case .browsing where tabViewModel.isShowingErrorPage:
            imageButton.image = .web
        case .browsing:
            // When editing (address bar focused), show favicon if available
            // When browsing (not editing), show globe for local HTTP sites
            // Privacy dashboard button would be shown for non-local sites
            if isTextFieldEditorFirstResponder, let favicon = tabViewModel.favicon {
                imageButton.image = favicon
            } else {
                imageButton.image = .web
            }
        case .editing(.url):
            imageButton.image = .web
        case .editing(.text):
            let addressBarStyleProvider = theme.addressBarStyleProvider
            if addressBarStyleProvider.shouldShowNewSearchIcon {
                imageButton.image = addressBarStyleProvider.addressBarLogoImage
            } else {
                imageButton.image = .search
            }
        case .editing(.openTabSuggestion):
            imageButton.image = .openTabSuggestion
        case .editing(.aiChat):
            imageButton.image = .aiChat
        default:
            imageButton.image = nil
        }
    }

    private func updatePrivacyDashboardButton() {
        guard let tabViewModel else { return }

        let url = tabViewModel.tab.content.userEditableUrl
        let isNewTabOrOnboarding = [.newtab, .onboarding].contains(tabViewModel.tab.content)
        let isHypertextUrl = url?.navigationalScheme?.isHypertextScheme == true && url?.isDuckPlayer == false
        let isEditingMode = controllerMode?.isEditing ?? false
        let isTextFieldValueText = textFieldValue?.isText ?? false
        let isLocalUrl = url?.isLocalURL ?? false

        // Privacy entry point button
        let isFlaggedAsMalicious = (tabViewModel.tab.privacyInfo?.malicousSiteThreatKind != .none)
        privacyDashboardButton.isAnimationEnabled = !isFlaggedAsMalicious
        privacyDashboardButton.normalTintColor = isFlaggedAsMalicious ? .fireButtonRedPressed : .privacyEnabled
        privacyDashboardButton.mouseOverTintColor = isFlaggedAsMalicious ? .alertRedHover : privacyDashboardButton.mouseOverTintColor
        privacyDashboardButton.mouseDownTintColor = isFlaggedAsMalicious ? .alertRedPressed : privacyDashboardButton.mouseDownTintColor

        privacyDashboardButton.isShown = !isEditingMode
        && !isTextFieldEditorFirstResponder
        && isHypertextUrl
        && !tabViewModel.isShowingErrorPage
        && !isTextFieldValueText
        && !isLocalUrl

        // Hide the left icon when the toggle is visible
        let isToggleFeatureEnabled = isTextFieldEditorFirstResponder && featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && aiChatSettings.isAIFeaturesEnabled
        let shouldShowToggle = isToggleFeatureEnabled && aiChatSettings.showSearchAndDuckAIToggle

        imageButtonWrapper.isShown = imageButton.image != nil
        && !isInPopUpWindow
        && (isHypertextUrl || isTextFieldEditorFirstResponder || isEditingMode || isNewTabOrOnboarding)
        && privacyDashboardButton.isHidden
        && !shouldShowToggle
    }

    private func updatePrivacyEntryPointIcon() {
        let privacyShieldStyle = theme.addressBarStyleProvider.privacyShieldStyleProvider
        guard AppVersion.runType.requiresEnvironment else { return }

        guard let tabViewModel else {
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = true
            return
        }

        // Hide shields when user is typing in the address bar
        if textFieldValue?.isText ?? false {
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = true
            return
        }

        // Hide shields when address bar is focused
        if isTextFieldEditorFirstResponder {
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = true
            return
        }

        // Don't change icon while shield animation is playing
        guard !isAnyShieldAnimationPlaying else { return }

        switch tabViewModel.tab.content {
        case .url(let url, _, _), .identityTheftRestoration(let url), .subscription(let url), .aiChat(let url):
            guard let host = url.host else { break }

            let isNotSecure = url.scheme == URL.NavigationalScheme.http.rawValue
            let isCertificateInvalid = tabViewModel.tab.isCertificateInvalid
            let isFlaggedAsMalicious = (tabViewModel.tab.privacyInfo?.malicousSiteThreatKind != .none)
            let configuration = privacyConfigurationManager.privacyConfig
            let isUnprotected = configuration.isUserUnprotected(domain: host)

            let isShieldDotVisible = isNotSecure || isUnprotected || isCertificateInvalid

            if isFlaggedAsMalicious {
                shieldAnimationView.isHidden = true
                shieldDotAnimationView.isHidden = true
                privacyDashboardButton.isAnimationEnabled = false
                privacyDashboardButton.image = .redAlertCircle16
                privacyDashboardButton.normalTintColor = .alertRed
                privacyDashboardButton.mouseOverTintColor = .alertRedHover
                privacyDashboardButton.mouseDownTintColor = .alertRedPressed
            } else if isShieldDotVisible {
                shieldAnimationView.isHidden = true
                shieldDotAnimationView.isHidden = true
                privacyDashboardButton.isAnimationEnabled = true
                privacyDashboardButton.image = privacyShieldStyle.iconWithDot

                let animationNames = MouseOverAnimationButton.AnimationNames(
                    aqua: privacyShieldStyle.hoverAnimationWithDot(forLightMode: true),
                    dark: privacyShieldStyle.hoverAnimationWithDot(forLightMode: false)
                )
                privacyDashboardButton.animationNames = animationNames
            } else {
                // Protected site - show Lottie shield
                privacyDashboardButton.image = nil
                privacyDashboardButton.isAnimationEnabled = true
                shieldAnimationView.isHidden = false
                shieldDotAnimationView.isHidden = true

                if !hasShieldAnimationCompleted {
                    shieldAnimationView.currentFrame = 1
                }

                let animationNames = MouseOverAnimationButton.AnimationNames(
                    aqua: privacyShieldStyle.hoverAnimation(forLightMode: true),
                    dark: privacyShieldStyle.hoverAnimation(forLightMode: false)
                )
                privacyDashboardButton.animationNames = animationNames
            }
        default:
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = true
        }
    }

    private func updateSeparator() {
        separator.isShown = privacyDashboardButton.isVisible && (
            (permissionButtons.subviews.contains(where: { $0.isVisible })) || zoomButton.isVisible
        )
    }

    // MARK: - AI Chat Action Helpers

    @IBAction func aiChatButtonAction(_ sender: Any) {
        guard let tab = tabViewModel?.tab else { return }

        // Close the sidebar if it's currently open and the user preference is set to open AI chat in new tabs
        // This ensures consistent behavior when the sidebar is unexpectedly open but shouldn't be the default action
        if !aiChatMenuConfig.shouldOpenAIChatInSidebar && aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid) {
            aiChatSidebarPresenter.toggleSidebar()

            if aiChatButton == sender as? AddressBarMenuButton {
                return
            }
        }

        let behavior = createAIChatLinkOpenBehavior(for: tab)

        if featureFlagger.isFeatureOn(.aiChatSidebar),
           aiChatMenuConfig.shouldOpenAIChatInSidebar,
           !isTextFieldEditorFirstResponder,
           case .url = tab.content,
           behavior == .currentTab {
            // Toggle (open or close) the sidebar only when feature flag and setting option are enabled and:
            // - address bar text field is not in focus
            // - the current tab is displaying a standard web page (not a special page),
            // - intended link open behavior is to use the current tab
            toggleAIChatSidebar(for: tab)
        } else {
            // Otherwise open Duck.ai in a full tab
            openAIChatTab(for: tab, with: behavior)
        }

        delegate?.addressBarButtonsViewControllerAIChatButtonClicked(self)
        updateAskAIChatButtonVisibility()
    }

    private func createAIChatLinkOpenBehavior(for tab: Tab) -> LinkOpenBehavior {
        let shouldSelectNewTab: Bool = {
            guard let url = tab.url else { return false }
            return !url.isDuckAIURL && tab.content != .newtab
        }()

        return LinkOpenBehavior(event: NSApp.currentEvent,
                                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                                shouldSelectNewTab: shouldSelectNewTab)
    }

    private func toggleAIChatSidebar(for tab: Tab) {
        let isSidebarCurrentlyOpen = aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
        let pixel: AIChatPixel = isSidebarCurrentlyOpen ?
            .aiChatSidebarClosed(source: .addressBarButton) :
            .aiChatSidebarOpened(source: .addressBarButton,
                                 shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                                 minutesSinceSidebarHidden: aiChatSidebarPresenter.sidebarHiddenAt(for: tab.uuid)?.minutesSinceNow())
        PixelKit.fire(pixel, frequency: .dailyAndStandard)
        if !isSidebarCurrentlyOpen {
            PixelKit.fire(AIChatPixel.aiChatAddressBarButtonClicked(action: .sidebar), frequency: .dailyAndStandard)
        }

        aiChatSidebarPresenter.toggleSidebar()
    }

    private func openAIChatTab(for tab: Tab, with behavior: LinkOpenBehavior) {
        // If the AI Chat sidebar is open and the intended behavior is to open in the current tab,
        // close the sidebar before opening Duck.ai in the current tab.
        if aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid) && behavior == .currentTab {
            aiChatSidebarPresenter.collapseSidebar(withAnimation: false)
        }

        if let value = textFieldValue, !value.isEmpty {
            PixelKit.fire(AIChatPixel.aiChatAddressBarButtonClicked(action: .tabWithPrompt), frequency: .dailyAndStandard)
            let query = aiChatAddressBarPromptExtractor.extractAIChatQuery(for: value)
            aiChatTabOpener.openAIChatTab(with: query, behavior: behavior)
        } else {
            PixelKit.fire(AIChatPixel.aiChatAddressBarButtonClicked(action: .tab), frequency: .dailyAndStandard)
            aiChatTabOpener.openNewAIChat(in: behavior)
        }
    }

    func openPrivacyDashboardPopover(entryPoint: PrivacyDashboardEntryPoint = .dashboard) {
        if let permissionAuthorizationPopover, permissionAuthorizationPopover.isShown {
            permissionAuthorizationPopover.close()
        }
        popupBlockedPopover?.close()

        popovers?.togglePrivacyDashboardPopover(for: tabViewModel, from: privacyDashboardButton, entryPoint: entryPoint)
        onboardingPixelReporter.measurePrivacyDashboardOpened()
        PixelKit.fire(NavigationBarPixel.privacyDashboardOpened, frequency: .daily)
    }

    private func setupButtonsCornerRadius() {
        let cornerRadius = theme.addressBarStyleProvider.addressBarButtonsCornerRadius
        aiChatButton.setCornerRadius(cornerRadius)
        askAIChatButton.setCornerRadius(cornerRadius)
        bookmarkButton.setCornerRadius(cornerRadius)
        cancelButton.setCornerRadius(cornerRadius)
        permissionButtons.setCornerRadius(cornerRadius)
        zoomButton.setCornerRadius(cornerRadius)
        privacyDashboardButton.setCornerRadius(cornerRadius)
        permissionCenterButton.setCornerRadius(cornerRadius)
    }

    private func setupButtonsSize() {
        let addressBarButtonSize = theme.addressBarStyleProvider.addressBarButtonSize

        bookmarkButtonWidthConstraint.constant = addressBarButtonSize
        bookmarkButtonHeightConstraint.constant = addressBarButtonSize
        cancelButtonWidthConstraint.constant = addressBarButtonSize
        cancelButtonHeightConstraint.constant = addressBarButtonSize
        aiChatButtonWidthConstraint.constant = addressBarButtonSize
        aiChatButtonHeightConstraint.constant = addressBarButtonSize
        askAIChatButtonWidthConstraint.constant = addressBarButtonSize
        askAIChatButtonHeightConstraint.constant = addressBarButtonSize
        privacyShieldButtonWidthConstraint.constant = addressBarButtonSize
        privacyShieldButtonHeightConstraint.constant = addressBarButtonSize
        zoomButtonHeightConstraint.constant = addressBarButtonSize
        geolocationButtonHeightConstraint.constant = addressBarButtonSize
        microphoneButtonHeightConstraint.constant = addressBarButtonSize
        cameraButtonHeightConstraint.constant = addressBarButtonSize
        popupsButtonHeightConstraint.constant = addressBarButtonSize
        externalSchemeButtonHeightConstraint.constant = addressBarButtonSize
        permissionButtonHeightConstraint.constant = addressBarButtonSize
        permissionCenterButtonWidthConstraint.constant = addressBarButtonSize
    }

    private func setupButtonIcons() {
        let addressBarButtonsIconsProvider = theme.iconsProvider.addressBarButtonsIconsProvider

        geolocationButton.activeImage = addressBarButtonsIconsProvider.locationSolid
        geolocationButton.disabledImage = addressBarButtonsIconsProvider.locationIcon
        geolocationButton.defaultImage = addressBarButtonsIconsProvider.locationIcon
        externalSchemeButton.defaultImage = addressBarButtonsIconsProvider.externalSchemeIcon
        popupsButton.defaultImage = addressBarButtonsIconsProvider.popupsIcon
        updatePermissionCenterButtonIcon()
    }

    private func updateBookmarkButtonVisibility() {
        guard !isInPopUpWindow else { return }

        if case .editing(.aiChat) = controllerMode {
            bookmarkButton.isShown = false
            updateAIChatDividerVisibility()
            return
        }

        if isTextFieldEditorFirstResponder && featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
            bookmarkButton.isShown = false
            updateAIChatDividerVisibility()
            return
        }

        let hasEmptyAddressBar = textFieldValue?.isEmpty ?? true
        var shouldShowBookmarkButton: Bool {
            guard let tabViewModel, tabViewModel.canBeBookmarked else { return false }

            var isUrlBookmarked = false
            if let url = tabViewModel.tab.content.userEditableUrl {
                let urlVariants = url.bookmarkButtonUrlVariants()

                // Check if any of the URL variants is bookmarked
                isUrlBookmarked = urlVariants.contains { variant in
                    return bookmarkManager.isUrlBookmarked(url: variant)
                }
            }

            return cancelButton.isHidden && !hasEmptyAddressBar && (isMouseOverNavigationBar || popovers?.isEditBookmarkPopoverShown == true || isUrlBookmarked)
        }

        bookmarkButton.isShown = shouldShowBookmarkButton
        updateAIChatDividerVisibility()
    }

    private func updateZoomButtonVisibility(animation: Bool = false) {
        let hasURL = tabViewModel?.tab.url != nil
        let isEditingMode = controllerMode?.isEditing ?? false
        let isTextFieldValueText = textFieldValue?.isText ?? false

        enum ZoomState { case zoomedIn, zoomedOut }
        var zoomState: ZoomState?
        if let zoomLevel = tabViewModel?.zoomLevel, zoomLevel != accessibilityPreferences.defaultPageZoom {
            zoomState = (zoomLevel > accessibilityPreferences.defaultPageZoom) ? .zoomedIn : .zoomedOut
        }

        let isPopoverShown = popovers?.isZoomPopoverShown == true
        let shouldShowZoom = hasURL
        && !isEditingMode
        && !isTextFieldValueText
        && !isTextFieldEditorFirstResponder
        && !animation
        && (zoomState != .none || isPopoverShown)

        let moreOptionsMenuIconsProvider = theme.iconsProvider.moreOptionsMenuIconsProvider
        zoomButton.image = (zoomState == .zoomedOut) ? moreOptionsMenuIconsProvider.zoomOutIcon : moreOptionsMenuIconsProvider.zoomInIcon
        zoomButton.backgroundColor = isPopoverShown ? .buttonMouseDown : nil
        zoomButton.mouseOverColor = isPopoverShown ? nil : .buttonMouseOver
        zoomButton.isHidden = !shouldShowZoom
        zoomButton.normalTintColor = theme.colorsProvider.iconsColor
    }

    // Temporarily hide/display AI chat button (does not persist)
    func updateAIChatButtonVisibility(isHidden: Bool) {
        aiChatButton.isHidden = isHidden
        updateAIChatDividerVisibility()
    }

    private func updateAIChatButtonState() {
        guard let tab = tabViewModel?.tab, featureFlagger.isFeatureOn(.aiChatSidebar) else { return }
        let isShowingSidebar = aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
        updateAIChatButtonStateForSidebar(isShowingSidebar)
    }

    private func updateAIChatButtonStateForSidebar(_ isShowingSidebar: Bool) {
        configureContextMenuForAIChatButtons(isSidebarOpen: isShowingSidebar)
        configureAIChatButtonTooltip(isSidebarOpen: isShowingSidebar)

        if isShowingSidebar {
            aiChatButton.setButtonType(.toggle)
            aiChatButton.state = .on
            aiChatButton.mouseOverColor = nil
        } else {
            aiChatButton.setButtonType(.momentaryPushIn)
            aiChatButton.state = .off
            aiChatButton.mouseOverColor = theme.colorsProvider.buttonMouseOverColor
        }
    }

    private func updateAIChatButtonVisibility() {
        let isDuckAIURL = tabViewModel?.tab.url?.isDuckAIURL ?? false

        aiChatButton.isHidden = !shouldShowAIChatButton()
        updateAIChatDividerVisibility()

        // Check if the current tab is in the onboarding state and disable the AI chat button if it is
        guard let tabViewModel else { return }
        let isOnboarding = [.onboarding].contains(tabViewModel.tab.content)
        aiChatButton.isEnabled = !isOnboarding
    }

    private var isAskAIChatButtonExpanded: Bool = false

    private func updateAskAIChatButtonVisibility(isSidebarOpen: Bool? = nil) {
        let isToggleFeatureEnabled = isTextFieldEditorFirstResponder && featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && aiChatSettings.isAIFeaturesEnabled

        if isTextFieldEditorFirstResponder {
            if isToggleFeatureEnabled {
                aiChatButton.isHidden = true
                askAIChatButton.isHidden = true
            } else {
                aiChatButton.isHidden = true
                askAIChatButton.isHidden = !shouldShowAskAIChatButton()
            }
        } else {
            // aiChatButton visibility managed in updateAIChatButtonVisibility
            askAIChatButton.isHidden = true
        }

        updateAIChatDividerVisibility()

        let isSidebarOpen: Bool = isSidebarOpen ?? {
            guard let tabID = tabViewModel?.tab.uuid else { return false }
            return aiChatSidebarPresenter.isSidebarOpen(for: tabID)
        }()

        if shouldExpandAskAIChatButton(isSidebarOpen: isSidebarOpen) {
            expandAskAIChatButton()
        } else {
            contractAskAIChatButton()
        }
    }

    // MARK: - Ask AI Chat Button Helper Methods

    private func shouldSkipShowingAnyAIChatButton() -> Bool {
        let isDuckAIURL = tabViewModel?.tab.url?.isDuckAIURL ?? false
        return isInPopUpWindow || isDuckAIURL || !featureFlagger.isFeatureOn(.aiChatSidebar)
    }

    private func shouldShowAIChatButton() -> Bool {
        aiChatMenuConfig.shouldDisplayAddressBarShortcut && !shouldSkipShowingAnyAIChatButton()
    }

    private func shouldShowAskAIChatButton() -> Bool {
        aiChatMenuConfig.shouldDisplayAddressBarShortcutWhenTyping && !shouldSkipShowingAnyAIChatButton()
    }

    private func shouldExpandAskAIChatButton(isSidebarOpen: Bool) -> Bool {
        guard isTextFieldEditorFirstResponder,
              let textFieldValue = textFieldValue,
              !textFieldValue.isEmpty,
              textFieldValue.isUserTyped || textFieldValue.isSuggestion else {
            return false
        }
        return true
    }

    private func expandAskAIChatButton() {
        guard !isAskAIChatButtonExpanded else {
            // Ignore any subsequent calls to prevent duplicate animations
            return
        }
        isAskAIChatButtonExpanded = true

        askAIChatButton.isEnabled = true
        askAIChatButton.state = .off
        askAIChatButton.toolTip = nil

        refreshAskAIChatButtonStyle(expanded: true)
        animateAskAIChatButtonExpansion()
    }

    private func contractAskAIChatButton() {
        refreshAskAIChatButtonStyle(expanded: false)

        askAIChatButton.toolTip = ShortcutTooltip.askAIChat.value
        askAIChatButton.isEnabled = true
        askAIChatButton.state = .off

        guard isAskAIChatButtonExpanded else {
            // Ignore any subsequent calls if button is already contracted
            return
        }

        isAskAIChatButtonExpanded = false
        animateAskAIChatButtonContraction()
    }

    func refreshAskAIChatButtonStyle() {
        refreshAskAIChatButtonStyle(expanded: isAskAIChatButtonExpanded)
    }

    func refreshAskAIChatButtonStyle(expanded: Bool) {
        let colorsProvider = theme.colorsProvider

        askAIChatButton.backgroundColor = expanded ? colorsProvider.fillButtonBackgroundColor : .clear
        askAIChatButton.mouseOverColor = expanded ? colorsProvider.fillButtonMouseOverColor : colorsProvider.buttonMouseOverColor
    }

    private func animateAskAIChatButtonExpansion() {
        configureAskAIChatButton()
        let targetWidth = calculateExpandedButtonWidth()

        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            context.duration = Constants.askAiChatButtonAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            askAIChatButtonWidthConstraint.animator().constant = targetWidth
        }
    }

    private func calculateExpandedButtonWidth() -> CGFloat {
        let addressBarButtonSize = theme.addressBarStyleProvider.addressBarButtonSize
        let fittingSize = askAIChatButton.sizeThatFits(
            CGSize(width: 1000, height: addressBarButtonSize)
        )

        return max(fittingSize.width, addressBarButtonSize)
    }

    private func animateAskAIChatButtonContraction() {
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = true
            context.duration = Constants.askAiChatButtonAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            askAIChatButtonWidthConstraint.animator().constant = theme.addressBarStyleProvider.addressBarButtonSize
        } completionHandler: {
            guard !self.isAskAIChatButtonExpanded else { return }
            self.askAIChatButton.title = ""
        }
    }

    @objc func openAIChatContextMenuAction(_ sender: NSMenuItem) {
        // Open AI Chat action implementation - behavior opposite to default setting

        if aiChatMenuConfig.shouldOpenAIChatInSidebar {
            // Default is sidebar, menu action forces new tab
            let behavior = LinkOpenBehavior(
                event: NSApp.currentEvent,
                switchToNewTabWhenOpenedPreference: tabsPreferences.switchToNewTabWhenOpened,
                canOpenLinkInCurrentTab: false,
                shouldSelectNewTab: true
            )

            if let value = textFieldValue {
                let query = aiChatAddressBarPromptExtractor.extractAIChatQuery(for: value)
                aiChatTabOpener.openAIChatTab(with: query, behavior: behavior)
            } else {
                aiChatTabOpener.openNewAIChat(in: behavior)
            }
        } else {
            if let tab = tabViewModel?.tab {
                let isSidebarCurrentlyOpen = aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
                let pixel: AIChatPixel = isSidebarCurrentlyOpen ?
                    .aiChatSidebarClosed(source: .contextMenu) :
                    .aiChatSidebarOpened(source: .contextMenu,
                                         shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                                         minutesSinceSidebarHidden: aiChatSidebarPresenter.sidebarHiddenAt(for: tab.uuid)?.minutesSinceNow())
                PixelKit.fire(pixel, frequency: .dailyAndStandard)
            }

            // Default is new tab, menu action forces sidebar
            aiChatSidebarPresenter.toggleSidebar()
        }
    }

    @objc func hideAIChatButtonAction(_ sender: NSMenuItem) {
        delegate?.addressBarButtonsViewControllerHideAIChatButtonClicked(self)
    }

    @objc func hideAskAIChatButtonAction(_ sender: NSMenuItem) {
        delegate?.addressBarButtonsViewControllerHideAskAIChatButtonClicked(self)
    }

    @objc func hideSearchModeToggleAction(_ sender: NSMenuItem) {
        /// If the user is in duck.ai mode, switch back to search mode before hiding the toggle
        if searchModeToggleControl?.selectedSegment == 1 {
            delegate?.addressBarButtonsViewControllerSearchModeToggleChanged(self, isAIChatMode: false)
            searchModeToggleControl?.reset()
        }

        delegate?.addressBarButtonsViewControllerHideSearchModeToggleClicked(self)
        updateButtons()
    }

    @objc func openAIChatSettingsContextMenuAction(_ sender: NSMenuItem) {
        delegate?.addressBarButtonsViewControllerOpenAIChatSettingsButtonClicked(self)
    }

    private func updateAIChatDividerVisibility() {
        // Prevent crash if Combine subscriptions outlive view lifecycle: https://app.asana.com/1/137249556945/project/1199230911884351/task/1210593147082728
        guard isViewLoaded else { return }

        leadingAIChatDivider.isHidden = aiChatButton.isHidden || bookmarkButton.isHidden

        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            trailingAIChatDivider.isHidden = askAIChatButton.isHidden || cancelButton.isHidden
        } else {
            trailingAIChatDivider.isHidden = aiChatButton.isHidden || cancelButton.isHidden
        }
    }

    private func configureAIChatButton() {
        let navigationToolbarIconsProvider = theme.iconsProvider.navigationToolbarIconsProvider
        let colorsProvider = theme.colorsProvider

        aiChatButton.sendAction(on: [.leftMouseUp, .otherMouseDown])
        aiChatButton.image = navigationToolbarIconsProvider.aiChatButtonImage
        aiChatButton.mouseOverColor = colorsProvider.buttonMouseOverColor
        aiChatButton.normalTintColor = colorsProvider.iconsColor
        aiChatButton.setAccessibilityIdentifier("AddressBarButtonsViewController.aiChatButton")

        configureAIChatButtonTooltip()
    }

    private func configureAIChatButtonTooltip(isSidebarOpen: Bool? = nil) {
        if let tab = tabViewModel?.tab, featureFlagger.isFeatureOn(.aiChatSidebar) {
            let isSidebarOpen: Bool = isSidebarOpen ?? {
                guard let tabID = tabViewModel?.tab.uuid else { return false }
                return aiChatSidebarPresenter.isSidebarOpen(for: tabID)
            }()

            if isSidebarOpen {
                aiChatButton.toolTip = UserText.aiChatCloseSidebarButton
                aiChatButton.setAccessibilityTitle(UserText.aiChatCloseSidebarButton)
            } else if aiChatMenuConfig.shouldOpenAIChatInSidebar, case .url = tab.content {
                aiChatButton.toolTip = UserText.aiChatOpenSidebarButton
                aiChatButton.setAccessibilityTitle(UserText.aiChatOpenSidebarButton)
            } else {
                aiChatButton.toolTip = isTextFieldEditorFirstResponder ? ShortcutTooltip.askAIChat.value : ShortcutTooltip.newAIChatTab.value
                aiChatButton.setAccessibilityTitle(UserText.aiChatAddressBarTrustedIndicator)
            }
        } else {
            aiChatButton.toolTip = isTextFieldEditorFirstResponder ? ShortcutTooltip.askAIChat.value : ShortcutTooltip.newAIChatTab.value
            aiChatButton.setAccessibilityTitle(UserText.aiChatAddressBarTrustedIndicator)
        }
    }

    private func configureAskAIChatButton() {
        let navigationToolbarIconsProvider = theme.iconsProvider.navigationToolbarIconsProvider
        let colorsProvider = theme.colorsProvider

        askAIChatButton.image = navigationToolbarIconsProvider.aiChatButtonImage.withPadding(left: Constants.askAiChatButtonHorizontalPadding)

        askAIChatButton.imageHugsTitle = true
        askAIChatButton.imagePosition = .imageLeading
        askAIChatButton.imageScaling = .scaleNone

        let attributedTitle = NSMutableAttributedString(string: " ")

        // Configure text truncation required for smoother animation
        if let buttonCell = askAIChatButton.cell as? NSButtonCell {
            buttonCell.lineBreakMode = .byClipping
            buttonCell.truncatesLastVisibleLine = false
        }

        askAIChatButton.attributedTitle = {
            // Main text in normal color
            let mainAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: colorsProvider.textPrimaryColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]

            // Shortcut text in secondary color
            let shortcutAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: colorsProvider.textTertiaryColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]

            attributedTitle.append(NSAttributedString(string: UserText.askAIChatButtonTitle, attributes: mainAttributes))
            attributedTitle.append(NSAttributedString(string: " "))
            attributedTitle.append(NSAttributedString(string: "⇧↵", attributes: shortcutAttributes))

            // Add invisible character to prevent whitespace trimming which causes animation glitches
            // The trailing whitespace gets trimmed by the system, so we use a clear-colored dot instead to add padding
            let invisibleAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]

            attributedTitle.append(NSAttributedString(string: ".", attributes: invisibleAttributes))

            return attributedTitle
        }()
        askAIChatButton.setAccessibilityIdentifier("AddressBarButtonsViewController.askAIChatButton")
    }

    private func createAIChatContextMenu(hideButtonAction: Selector, isSidebarOpen: Bool? = nil) -> NSMenu {
        let shouldShowOpenAIChatButton: Bool = {
            guard let tabContent = tabViewModel?.tab.content, case .url = tabContent else {
                return false
            }
            return true
        }()

        return NSMenu {
            if shouldShowOpenAIChatButton {
                let contextMenuTitle: String = {
                    if aiChatMenuConfig.shouldOpenAIChatInSidebar {
                        return UserText.aiChatOpenNewTabButton
                    } else {
                        // Check if sidebar is currently open for this tab
                        guard let tab = tabViewModel?.tab else {
                            return UserText.aiChatOpenSidebarButton
                        }
                        let isShowingSidebar = isSidebarOpen ?? aiChatSidebarPresenter.isSidebarOpen(for: tab.uuid)
                        return isShowingSidebar ? UserText.aiChatCloseSidebarButton : UserText.aiChatOpenSidebarButton
                    }
                }()

                NSMenuItem(title: contextMenuTitle,
                           action: #selector(openAIChatContextMenuAction(_:)),
                           keyEquivalent: "")
            }
            NSMenuItem(title: UserText.aiChatAddressBarHideButton,
                       action: hideButtonAction,
                       keyEquivalent: "")
            NSMenuItem.separator()
            NSMenuItem(title: UserText.aiChatOpenSettingsButton,
                       action: #selector(openAIChatSettingsContextMenuAction(_:)),
                       keyEquivalent: "")
        }
    }

    private func configureContextMenuForAIChatButtons(isSidebarOpen: Bool? = nil) {
        guard featureFlagger.isFeatureOn(.aiChatSidebar) else {

            aiChatButton.menu = NSMenu {
                NSMenuItem(title: UserText.aiChatAddressBarHideButton,
                           action: #selector(hideAIChatButtonAction(_:)),
                           keyEquivalent: "")
            }

            return
        }

        aiChatButton.menu = createAIChatContextMenu(hideButtonAction: #selector(hideAIChatButtonAction(_:)), isSidebarOpen: isSidebarOpen)
        askAIChatButton.menu = createAIChatContextMenu(hideButtonAction: #selector(hideAskAIChatButtonAction(_:)), isSidebarOpen: isSidebarOpen)
    }

    // MARK: - Buttons and Actions

    private func updateButtonsPosition() {
        cancelButton.position = .right
        askAIChatButton.position = .center

        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            aiChatButton.position = .right
        } else {
            aiChatButton.position = cancelButton.isShown ? .center : .right
        }

        bookmarkButton.position = aiChatButton.isShown ? .center : .right
    }

    @IBAction func bookmarkButtonAction(_ sender: Any) {
        openBookmarkPopover(setFavorite: false, accessPoint: .button)
    }

    @IBAction func cancelButtonAction(_ sender: Any) {
        delegate?.addressBarButtonsViewControllerCancelButtonClicked(self)
    }

    @IBAction func privacyDashboardButtonAction(_ sender: Any) {
        openPrivacyDashboardPopover()
    }

    func openBookmarkPopover(setFavorite: Bool, accessPoint: GeneralPixel.AccessPoint) {
        guard let popovers else {
            return
        }
        let result = bookmarkForCurrentUrl(setFavorite: setFavorite, accessPoint: accessPoint)
        guard let bookmark = result.bookmark else {
            assertionFailure("Failed to get a bookmark for the popover")
            return
        }

        if popovers.isEditBookmarkPopoverShown {
            updateBookmarkButtonVisibility()
            popovers.closeEditBookmarkPopover()
        } else {
            popovers.showEditBookmarkPopover(with: bookmark, isNew: result.isNew, from: bookmarkButton, withDelegate: self)
        }
    }

    func openPermissionAuthorizationPopover(for query: PermissionAuthorizationQuery) {
        let button: AddressBarButton

        lazy var popover: NSPopover = {
            let popover = self.permissionAuthorizationPopoverCreatingIfNeeded()
            popover.behavior = .applicationDefined
            return popover
        }()

        if featureFlagger.isFeatureOn(.newPermissionView) {
            button = permissionCenterButton
            // Update button icon to match the permission being requested
            updatePermissionCenterButtonIcon(forRequestedPermission: query.permissions.first)
            if query.permissions.first?.isPopups == true {
                guard !query.wasShownOnce else { return }
                popover = popupBlockedPopoverCreatingIfNeeded()
            }
            if query.permissions.first?.isExternalScheme == true {
                query.shouldShowAlwaysAllowCheckbox = true
                query.shouldShowCancelInsteadOfDeny = true
            }
        } else {
            if query.permissions.contains(.camera)
                || (query.permissions.contains(.microphone) && microphoneButton.isHidden && cameraButton.isShown) {
                button = cameraButton
            } else {
                assert(query.permissions.count == 1)
                switch query.permissions.first {
                case .microphone:
                    button = microphoneButton
                case .geolocation:
                    button = geolocationButton
                case .popups:
                    guard !query.wasShownOnce else { return }
                    button = popupsButton
                    popover = popupBlockedPopoverCreatingIfNeeded()
                case .externalScheme:
                    button = externalSchemeButton
                    query.shouldShowAlwaysAllowCheckbox = true
                    query.shouldShowCancelInsteadOfDeny = true
                default:
                    assertionFailure("Unexpected permissions")
                    query.handleDecision(grant: false)
                    return
                }
            }
        }
        guard button.isVisible else { return }

        button.backgroundColor = .buttonMouseDown
        button.mouseOverColor = .buttonMouseDown
        (popover.contentViewController as? PermissionAuthorizationViewController)?.query = query
        (popover.contentViewController as? PopupBlockedViewController)?.query = query
        query.wasShownOnce = true

        // Wait for the button appearance animation to complete before showing popover
        DispatchQueue.main.asyncAfter(deadline: .now() + NSAnimationContext.current.duration) { [weak self] in
            guard let self, let tabViewModel,
                  tabViewModel.tab.permissions.authorizationQueries.contains(where: { $0 === query }),
                  button.isVisible else {
                // Tab is no longer selected or button became hidden - reset button state
                button.backgroundColor = .clear
                button.mouseOverColor = .buttonMouseOver
                return
            }
            popover.show(positionedBelow: button.bounds.insetFromLineOfDeath(flipped: button.isFlipped), in: button)
        }
    }

    func closePrivacyDashboard() {
        popovers?.closePrivacyDashboard()
    }

    private func closePermissionPopovers() {
        permissionAuthorizationPopover?.close()
        popupBlockedPopover?.close()
        permissionCenterPopover?.close()
    }

    func openPrivacyDashboard() {
        guard let tabViewModel else { return }
        popovers?.openPrivacyDashboard(for: tabViewModel, from: privacyDashboardButton, entryPoint: .dashboard)
    }

    func openZoomPopover(source: ZoomPopover.Source) {
        guard let popovers,
              let tabViewModel = tabCollectionViewModel.selectedTabViewModel else { return }

        if let zoomPopover = popovers.zoomPopover, zoomPopover.isShown {
            // reschedule close timer for already shown popover
            zoomPopover.rescheduleCloseTimerIfNeeded()
            return
        }

        zoomButton.isShown = true
        popovers.showZoomPopover(for: tabViewModel, from: zoomButton, addressBar: parent?.view, withDelegate: self, source: source)
        updateZoomButtonVisibility()
    }

    func updateButtons() {
        // Prevent crash if Combine subscriptions outlive view lifecycle
        guard isViewLoaded else { return }

        stopAnimationsAfterFocus()

        let isToggleFeatureEnabled = isTextFieldEditorFirstResponder && featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && aiChatSettings.isAIFeaturesEnabled
        let shouldShowToggle = isToggleFeatureEnabled && aiChatSettings.showSearchAndDuckAIToggle

        // Update key view chain when toggle visibility changes
        updateKeyViewChainForToggle(shouldShowToggle: shouldShowToggle)

        searchModeToggleControl?.isHidden = !shouldShowToggle
        updateToggleExpansionState(shouldShowToggle: shouldShowToggle)

        if isToggleFeatureEnabled {
            aiChatButton.isHidden = true
            cancelButton.isShown = false
        } else {
            if featureFlagger.isFeatureOn(.aiChatSidebar) {
                cancelButton.isShown = isTextFieldEditorFirstResponder
            } else {
                cancelButton.isShown = isTextFieldEditorFirstResponder && !textFieldValue.isEmpty
            }
        }

        updateImageButton()
        updatePrivacyDashboardButton()
        updateAllPermissionButtons()
        updateBookmarkButtonVisibility()
        updateZoomButtonVisibility()
        if !isToggleFeatureEnabled {
            updateAIChatButtonVisibility()
        }
        updateAskAIChatButtonVisibility()
        updateButtonsPosition()
    }

    private func updateToggleExpansionState(shouldShowToggle: Bool) {
        guard let toggleControl = searchModeToggleControl else { return }

        let hasText = !(textFieldValue?.isEmpty ?? true)
        let hasUserTypedText = textFieldValue?.isUserTyped == true && hasText
        let hasInteractedBefore = UserDefaults.standard.hasInteractedWithSearchDuckAIToggle

        if shouldShowToggle && !wasToggleVisible {
            if hasText || hasInteractedBefore {
                toggleControl.setExpanded(false, animated: false)
                searchModeToggleWidthConstraint?.constant = toggleControl.collapsedWidth
            } else {
                toggleControl.setExpanded(true, animated: false)
                searchModeToggleWidthConstraint?.constant = toggleControl.expandedWidth
            }

            // Show the introduction popover when the toggle becomes visible for the first time
            showTogglePopoverIfNeeded(toggleControl: toggleControl)
        } else if shouldShowToggle && hasUserTypedText && toggleControl.isExpanded {
            toggleControl.setExpanded(false, animated: true)
        } else if !shouldShowToggle && toggleControl.isExpanded {
            toggleControl.setExpanded(false, animated: false)
            searchModeToggleWidthConstraint?.constant = toggleControl.collapsedWidth
        }

        wasToggleVisible = shouldShowToggle
    }

    private func showTogglePopoverIfNeeded(toggleControl: NSView) {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarToggle) else { return }

        /// Delay slightly to ensure the toggle is visible and positioned correctly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.aiChatTogglePopoverCoordinator?.showPopoverIfNeeded(
                relativeTo: toggleControl,
                isNewUser: AppDelegate.isNewUser,
                userDidInteractWithToggle: UserDefaults.standard.hasInteractedWithSearchDuckAIToggle
            )
        }
    }

    @IBAction func zoomButtonAction(_ sender: Any) {
        guard let popovers else { return }
        if popovers.isZoomPopoverShown {
            popovers.closeZoomPopover()
        } else {
            openZoomPopover(source: .toolbar)
        }
    }

    @IBAction func permissionCenterButtonAction(_ sender: Any) {
        guard featureFlagger.isFeatureOn(.newPermissionView) else { return }
        guard let tabViewModel else { return }

        // Don't open permission center while authorization or popup blocked dialog is presented
        if let authPopover = permissionAuthorizationPopover, authPopover.isShown {
            return
        }
        if let popupPopover = popupBlockedPopover, popupPopover.isShown {
            return
        }

        // Close existing popover if shown
        if let existingPopover = permissionCenterPopover, existingPopover.isShown {
            existingPopover.close()
            permissionCenterPopover = nil
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = (url.isFileURL ? .localhost : (url.host ?? "")).droppingWwwPrefix()

        // Get popup queries for the Permission Center
        let popupQueries = tabViewModel.tab.permissions.authorizationQueries.filter { $0.permissions.contains(.popups) }

        let viewModel = PermissionCenterViewModel(
            domain: domain,
            usedPermissions: tabViewModel.usedPermissions,
            usedPermissionsPublisher: tabViewModel.$usedPermissions.eraseToAnyPublisher(),
            popupQueries: popupQueries,
            permissionManager: permissionManager,
            featureFlagger: featureFlagger,
            removePermission: { [weak tabViewModel] permissionType in
                tabViewModel?.tab.permissions.remove(permissionType)
            },
            dismissPopover: { [weak self] in
                self?.permissionCenterPopover?.close()
                self?.permissionCenterPopover = nil
            },
            onPermissionRemoved: { [weak self] in
                // Dispatch to next run loop to allow Combine publishers to propagate changes
                DispatchQueue.main.async {
                    self?.updateAllPermissionButtons()
                }
            },
            openPopup: { [weak tabViewModel] query in
                tabViewModel?.tab.permissions.allow(query)
            },
            setTemporaryPopupAllowance: { [weak tabViewModel] in
                tabViewModel?.tab.popupHandling?.setPopupAllowanceForCurrentPage()
            },
            resetTemporaryPopupAllowance: { [weak tabViewModel] in
                tabViewModel?.tab.popupHandling?.clearPopupAllowanceForCurrentPage()
            },
            grantPermission: { [weak tabViewModel] query in
                tabViewModel?.tab.permissions.allow(query)
            },
            hasTemporaryPopupAllowance: tabViewModel.tab.popupHandling?.popupsTemporarilyAllowedForCurrentPage ?? false,
            pageInitiatedPopupOpened: tabViewModel.tab.popupHandling?.pageInitiatedPopupOpened ?? false
        )

        let popover = PermissionCenterPopover(viewModel: viewModel)
        permissionCenterPopover = popover

        // Set button to active/pressed state
        permissionCenterButton.backgroundColor = .buttonMouseDown
        permissionCenterButton.mouseOverColor = .buttonMouseDown

        // Register for close notification to reset button state
        NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose), name: NSPopover.didCloseNotification, object: popover)

        popover.show(positionedBelow: permissionCenterButton.bounds.insetFromLineOfDeath(flipped: permissionCenterButton.isFlipped), in: permissionCenterButton)
    }

    @IBAction func cameraButtonAction(_ sender: NSButton) {
        guard let tabViewModel else {
            assertionFailure("No selectedTabViewModel")
            return
        }
        if case .requested(let query) = tabViewModel.usedPermissions.camera {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        var permissions = Permissions()
        permissions.camera = tabViewModel.usedPermissions.camera
        if microphoneButton.isHidden {
            permissions.microphone = tabViewModel.usedPermissions.microphone
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: permissions.map { ($0, $1) }, domain: domain, delegate: self, featureFlagger: featureFlagger)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func microphoneButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.microphone
        else {
            Logger.general.error("Selected tab view model is nil or no microphone state")
            return
        }
        if case .requested(let query) = state {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: [(.microphone, state)], domain: domain, delegate: self, featureFlagger: featureFlagger)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func geolocationButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.geolocation
        else {
            Logger.general.error("Selected tab view model is nil or no geolocation state")
            return
        }
        if case .requested(let query) = state {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: [(.geolocation, state)], domain: domain, delegate: self, featureFlagger: featureFlagger)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func popupsButtonAction(_ sender: NSButton) {
        guard let tabViewModel else {
            Logger.general.error("Selected tab view model is nil or has no pop-up state")
            return
        }
        guard let state = tabViewModel.usedPermissions.popups ?? {
            // If popup permission button persistence feature flag is enabled and a page-initiated popup was opened for the current page,
            // return .inactive state for the pop-up button
            if featureFlagger.isFeatureOn(.popupBlocking) && featureFlagger.isFeatureOn(.popupPermissionButtonPersistence),
               tabViewModel.tab.popupHandling?.pageInitiatedPopupOpened ?? false { return .inactive } else { return nil }
        }() else {
            return
        }

        let permissions: [(PermissionType, PermissionState)]
        let domain: String
        if case .requested(let query) = state {
            domain = query.domain
            permissions = tabViewModel.tab.permissions.authorizationQueries.reduce(into: .init()) {
                guard $1.permissions.contains(.popups) else { return }
                $0.append( (.popups, .requested($1)) )
            }
        } else {
            let url = tabViewModel.tab.content.urlForWebView ?? .empty
            domain = url.isFileURL ? .localhost : (url.host ?? "")
            permissions = [(.popups, state)]
        }
        PermissionContextMenu(permissionManager: permissionManager,
                              permissions: permissions,
                              domain: domain,
                              delegate: self,
                              featureFlagger: featureFlagger,
                              hasTemporaryPopupAllowance: tabViewModel.tab.popupHandling?.popupsTemporarilyAllowedForCurrentPage ?? false)
        .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func externalSchemeButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let (permissionType, state) = tabViewModel.usedPermissions.first(where: { $0.key.isExternalScheme })
        else {
            Logger.general.error("Selected tab view model is nil or no externalScheme state")
            return
        }

        let permissions: [(PermissionType, PermissionState)]
        if case .requested(let query) = state {
            query.wasShownOnce = false
            openPermissionAuthorizationPopover(for: query)
            return
        }

        permissions = [(permissionType, state)]
        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: permissions, domain: domain, delegate: self, featureFlagger: featureFlagger)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @IBAction func notificationButtonAction(_ sender: NSButton) {
        guard let tabViewModel,
              let state = tabViewModel.usedPermissions.notification
        else {
            Logger.general.error("Selected tab view model is nil or no notification state")
            return
        }
        if case .requested(let query) = state {
            openPermissionAuthorizationPopover(for: query)
            return
        }

        let url = tabViewModel.tab.content.urlForWebView ?? .empty
        let domain = url.isFileURL ? .localhost : (url.host ?? "")

        PermissionContextMenu(permissionManager: permissionManager, permissions: [(.notification, state)], domain: domain, delegate: self, featureFlagger: featureFlagger)
            .popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    // MARK: - Notification Animation

    private var animationViewCache = [String: LottieAnimationView]()
    private func getAnimationView(for animationName: String) -> LottieAnimationView? {
        if let animationView = animationViewCache[animationName] {
            return animationView
        }

        guard let animationView = LottieAnimationView(named: animationName) else {
            assertionFailure("Missing animation file")
            return nil
        }

        animationViewCache[animationName] = animationView
        return animationView
    }

    private func setupNotificationAnimationView() {
        notificationAnimationView.alphaValue = 0.0
    }

    private func setupSearchModeToggleControl() {
        let toggleControl = CustomToggleControl(frame: NSRect(x: 0, y: 0, width: 70, height: 32))
        toggleControl.translatesAutoresizingMaskIntoConstraints = false

        toggleControl.setSelectedImage(DesignSystemImages.Color.Size16.searchFindToggle, forSegment: 0)
        toggleControl.setSelectedImage(DesignSystemImages.Color.Size16.aiChatToggle, forSegment: 1)

        toggleControl.setToolTip(UserText.aiChatSearchTheWebTooltip, forSegment: 0)
        toggleControl.setToolTip(UserText.aiChatChatWithAITooltip, forSegment: 1)

        toggleControl.setLabel(UserText.aiChatToggleSearchLabel, forSegment: 0)
        toggleControl.setLabel(UserText.aiChatToggleAskLabel, forSegment: 1)

        applyThemeToToggleControl(toggleControl)

        toggleControl.selectedSegment = 0

        toggleControl.target = self
        toggleControl.action = #selector(searchModeToggleDidChange(_:))

        toggleControl.onWidthChange = { [weak self] newWidth in
            self?.searchModeToggleWidthConstraint?.constant = newWidth
        }

        toggleControl.menu = createSearchModeToggleContextMenu()

        trailingButtonsContainer.addArrangedSubview(toggleControl)
        toggleControl.isHidden = true

        let widthConstraint = toggleControl.widthAnchor.constraint(equalToConstant: toggleControl.collapsedWidth)
        NSLayoutConstraint.activate([
            widthConstraint,
            toggleControl.heightAnchor.constraint(equalToConstant: 32)
        ])

        self.searchModeToggleWidthConstraint = widthConstraint
        self.searchModeToggleControl = toggleControl
    }

    private func createSearchModeToggleContextMenu() -> NSMenu {
        let menu = NSMenu()

        let hideItem = NSMenuItem(title: UserText.aiChatAddressBarHideToggle,
                                  action: #selector(hideSearchModeToggleAction(_:)),
                                  keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: UserText.aiChatOpenSettingsButton,
                                      action: #selector(openAIChatSettingsContextMenuAction(_:)),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    @objc private func searchModeToggleDidChange(_ sender: CustomToggleControl) {
        let isAIChatMode = sender.selectedSegment == 1
        UserDefaults.standard.hasInteractedWithSearchDuckAIToggle = true
        fireToggleChangedPixel(isAIChatMode: isAIChatMode)
        delegate?.addressBarButtonsViewControllerSearchModeToggleChanged(self, isAIChatMode: isAIChatMode)
    }

    private func fireToggleChangedPixel(isAIChatMode: Bool) {
        let pixel: AIChatPixel = isAIChatMode ? .aiChatAddressBarToggleChangedAIChat : .aiChatAddressBarToggleChangedSearch
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    func resetSearchModeToggle() {
        searchModeToggleControl?.reset()
    }

    func toggleSearchMode() {
        guard let toggleControl = searchModeToggleControl,
              !toggleControl.isHidden,
              toggleControl.isEnabled else {
            return
        }
        toggleControl.selectedSegment = toggleControl.selectedSegment == 0 ? 1 : 0
    }

    private func updateKeyViewChainForToggle(shouldShowToggle: Bool) {
        guard let addressBarViewController = parent as? AddressBarViewController,
              let addressBarTextField = addressBarViewController.addressBarTextField,
              let toggleControl = searchModeToggleControl else {
            return
        }

        if shouldShowToggle {
            if addressBarTextField.nextKeyView != toggleControl {
                toggleControl.nextKeyView = addressBarTextField.nextKeyView
                addressBarTextField.nextKeyView = toggleControl
            }
        } else {
            if addressBarTextField.nextKeyView == toggleControl {
                addressBarTextField.nextKeyView = toggleControl.nextKeyView
            }
        }
    }

    private func applyThemeToToggleControl(_ toggleControl: CustomToggleControl) {
        toggleControl.backgroundColor = NSColor(designSystemColor: .controlsRaisedBackdrop)
        toggleControl.focusedBackgroundColor = NSColor(designSystemColor: .controlsRaisedBackdrop)
        toggleControl.selectionColor = NSColor(designSystemColor: .controlsRaisedFillPrimary)

        if tabCollectionViewModel.isBurner {
            toggleControl.focusBorderColor = NSColor.burnerAccent.withAlphaComponent(0.8)
            toggleControl.outerBorderColor = NSColor.burnerAccent.withAlphaComponent(0.2)
        } else {
            toggleControl.focusBorderColor = theme.colorsProvider.accentPrimaryColor
            toggleControl.outerBorderColor = NSColor(designSystemColor: .controlsRaisedBackdrop)
        }

        toggleControl.outerBorderWidth = 2.0
        toggleControl.selectionInnerBorderColor = NSColor(designSystemColor: .shadowSecondary)

        toggleControl.leftImage = DesignSystemImages.Glyphs.Size16.findSearch.tinted(with: themeManager.theme.colorsProvider.iconsColor)
        toggleControl.rightImage = DesignSystemImages.Glyphs.Size16.aiChat.tinted(with: themeManager.theme.colorsProvider.iconsColor)

        toggleControl.labelColor = NSColor(designSystemColor: .textPrimary)
        toggleControl.selectedLabelColor = NSColor(designSystemColor: .textPrimary)
    }

    private func setupAnimationViews() {

        func addAndLayoutAnimationViewIfNeeded(animationView: LottieAnimationView?,
                                               animationName: String,
                                               // Default use of .mainThread to prevent high WindowServer Usage
                                               // Pending Fix with newer Lottie versions
                                               // https://app.asana.com/0/1177771139624306/1207024603216659/f
                                               renderingEngine: Lottie.RenderingEngineOption = .mainThread,
                                               alignLeft: Bool = false) -> LottieAnimationView {
            if let animationView = animationView, animationView.identifier?.rawValue == animationName {
                return animationView
            }

            animationView?.removeFromSuperview()

            let newAnimationView: LottieAnimationView
            // For unknown reason, this caused infinite execution of various unit tests.
            if AppVersion.runType.requiresEnvironment {
                newAnimationView = getAnimationView(for: animationName) ?? LottieAnimationView()
            } else {
                newAnimationView = LottieAnimationView()
            }
            newAnimationView.configuration = LottieConfiguration(renderingEngine: renderingEngine)

            // Ensure transparent background for all animation views
            newAnimationView.wantsLayer = true
            newAnimationView.layer?.backgroundColor = NSColor.clear.cgColor

            if alignLeft {
                newAnimationView.translatesAutoresizingMaskIntoConstraints = false
                animationWrapperView.addSubview(newAnimationView)

                NSLayoutConstraint.activate([
                    newAnimationView.leadingAnchor.constraint(equalTo: animationWrapperView.leadingAnchor, constant: 0.5),
                    newAnimationView.centerYAnchor.constraint(equalTo: animationWrapperView.centerYAnchor),
                    newAnimationView.widthAnchor.constraint(equalTo: animationWrapperView.heightAnchor, constant: 4),
                    newAnimationView.heightAnchor.constraint(equalTo: animationWrapperView.heightAnchor, constant: 4)
                ])
            } else {
                animationWrapperView.addAndLayout(newAnimationView)
            }
            newAnimationView.isHidden = true
            return newAnimationView
        }

        let isAquaMode = NSApp.effectiveAppearance.name == .aqua
        let style = theme.addressBarStyleProvider.privacyShieldStyleProvider

        shieldAnimationView = addAndLayoutAnimationViewIfNeeded(animationView: shieldAnimationView,
                                                                animationName: style.animationForShield(forLightMode: isAquaMode),
                                                                alignLeft: true)
        shieldDotAnimationView = addAndLayoutAnimationViewIfNeeded(animationView: shieldDotAnimationView,
                                                                   animationName: style.animationForShieldWithDot(forLightMode: isAquaMode),
                                                                   alignLeft: true)

        // Initialize shield animations as hidden - updatePrivacyEntryPointIcon() will show the correct one
        shieldAnimationView.isHidden = true
        shieldAnimationView.currentFrame = 1
        shieldDotAnimationView.isHidden = true
        shieldDotAnimationView.currentFrame = 1
    }

    private func animateTrackers() {
        guard privacyDashboardButton.isShown, let tabViewModel else { return }

        // Show tracker notification only once per URL
        if let trackerInfo = tabViewModel.tab.privacyInfo?.trackerInfo,
           case .url(let url, _, _) = tabViewModel.tab.content {
            let trackerCount = trackerInfo.trackersBlocked.count

            // Only show notification if we haven't shown it for this URL yet
            if trackerCount > 0 && lastNotifiedURL != url {
                lastNotifiedURL = url
                // Reset shield animation flag for new page
                hasShieldAnimationCompleted = false
                showTrackerNotification(count: trackerCount)
            }
        }

        updatePrivacyEntryPointIcon()
        updateAllPermissionButtons()
    }

    /// Stops animations. Shield visibility is managed by `updatePrivacyEntryPointIcon()`.
    private func stopAnimations(shieldAnimations: Bool = true, badgeAnimations: Bool = true) {
        if shieldAnimations {
            shieldAnimationView.stop()
            shieldDotAnimationView.stop()
            buttonsBadgeAnimator.isShieldAnimationInProgress = false
        }

        if badgeAnimations {
            stopNotificationBadgeAnimations()
        }
    }

    private func stopNotificationBadgeAnimations() {
        notificationAnimationView.removeAnimation()
        buttonsBadgeAnimator.cancelPendingAnimations()
        // Re-enable hover animation since animations were cancelled
        privacyDashboardButton.isAnimationEnabled = true
    }

    private var isAnyShieldAnimationPlaying: Bool {
        shieldAnimationView.isAnimationPlaying ||
        shieldDotAnimationView.isAnimationPlaying
    }

    /// Returns true if any shield animation view is visible (playing or showing static frame)
    private var isAnyShieldAnimationVisible: Bool {
        !shieldAnimationView.isHidden ||
        !shieldDotAnimationView.isHidden
    }

    private func stopAnimationsAfterFocus() {
        if isTextFieldEditorFirstResponder {
            stopAnimations()
        }
    }

    private func bookmarkForCurrentUrl(setFavorite: Bool, accessPoint: GeneralPixel.AccessPoint) -> (bookmark: Bookmark?, isNew: Bool) {
        guard let tabViewModel,
              let url = tabViewModel.tab.content.userEditableUrl else {
            assertionFailure("No URL for bookmarking")
            return (nil, false)
        }

        if let bookmark = bookmarkManager.getBookmark(forVariantUrl: url) {
            if setFavorite {
                bookmark.isFavorite = true
                bookmarkManager.update(bookmark: bookmark)
            }

            return (bookmark, false)
        }

        let lastUsedFolder = UserDefaultsBookmarkFoldersStore().lastBookmarkSingleTabFolderIdUsed.flatMap(bookmarkManager.getBookmarkFolder)
        let bookmark = bookmarkManager.makeBookmark(for: url,
                                                    title: tabViewModel.title,
                                                    isFavorite: setFavorite,
                                                    index: nil,
                                                    parent: lastUsedFolder)
        updateBookmarkButtonImage(isUrlBookmarked: bookmark != nil)

        return (bookmark, true)
    }

    private func subscribeToEffectiveAppearance() {
        NSApp.publisher(for: \.effectiveAppearance)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupAnimationViews()
                self?.updatePrivacyEntryPointIcon()
                self?.updateZoomButtonVisibility()
                self?.configureAskAIChatButton()
            }
            .store(in: &cancellables)
    }

    private func subscribeToTabZoomLevel() {
        zoomLevelCancellable = tabViewModel?.zoomLevelSubject
            .sink { [weak self] _ in
                self?.updateZoomButtonVisibility()
            }
    }

    private func subscribeToIsMouseOverAnimationVisible() {
        privacyDashboardButton.$isAnimationViewVisible
            .dropFirst()
            .sink { [weak self] isAnimationViewVisible in
                guard let self = self else { return }

                // Hide the Lottie shield animations when hover animation is visible
                // to prevent overlap and misalignment
                if isAnimationViewVisible {
                    self.shieldAnimationView?.isHidden = true
                    self.shieldDotAnimationView?.isHidden = true
                } else {
                    // Restore shield visibility when hover animation ends
                    self.updatePrivacyEntryPointIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToPrivacyEntryPointIsMouseOver() {
        privacyDashboardButton.publisher(for: \.isMouseOver)
            .first(where: { $0 }) // only interested when mouse is over
            .sink(receiveValue: { [weak self] _ in
                self?.stopHighlightingPrivacyShield()
            })
            .store(in: &cancellables)
    }
}

/// Custom view for AddressBarButtonsViewController that accepts first mouse in popup windows
/// to allow dragging the window when it's inactive
final class AddressBarButtonsView: NSView {
    weak var draggingDestinationView: NSResponder?
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return draggingDestinationView != nil
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        if let draggingDestinationView {
            // Forward to DraggingDestinationView to allow dragging the popup window
            draggingDestinationView.mouseDown(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let draggingDestinationView {
            draggingDestinationView.mouseDragged(with: event)
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let draggingDestinationView {
            draggingDestinationView.mouseUp(with: event)
        } else {
            super.mouseUp(with: event)
        }
    }
}

extension AddressBarButtonsViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        configureAIChatButton()
        updateAIChatButtonState()
        updateBookmarkButtonImage()
        updateImageButton()
        updateZoomButtonVisibility()
        refreshAskAIChatButtonStyle()
        refreshButtonsThemeStyle(theme: theme)

        // Update toggle control theme
        if let toggleControl = searchModeToggleControl {
            applyThemeToToggleControl(toggleControl)
        }
    }

    private func refreshButtonsThemeStyle(theme: ThemeStyleProviding) {
        let colorsProvider = theme.colorsProvider

        bookmarkButton.normalTintColor = colorsProvider.iconsColor
        geolocationButton.normalTintColor = colorsProvider.iconsColor
        cameraButton.normalTintColor = colorsProvider.iconsColor
        microphoneButton.normalTintColor = colorsProvider.iconsColor
    }
}

// MARK: - Contextual Onboarding View Highlight

extension AddressBarButtonsViewController {

    func highlightPrivacyShield() {
        if !isAnyShieldAnimationPlaying && !buttonsBadgeAnimator.isAnimating && buttonsBadgeAnimator.animationQueue.isEmpty {
            ViewHighlighter.highlight(view: privacyDashboardButton, inParent: self.view)
        } else {
            hasPrivacyInfoPulseQueuedAnimation = true
        }
    }

    func stopHighlightingPrivacyShield() {
        hasPrivacyInfoPulseQueuedAnimation = false
        ViewHighlighter.stopHighlighting(view: privacyDashboardButton)
    }

}

// MARK: - NavigationBarBadgeAnimatorDelegate

extension AddressBarButtonsViewController: NavigationBarBadgeAnimatorDelegate {

    func didFinishAnimating(type: NavigationBarBadgeAnimationView.AnimationType) {
        guard case .trackersBlocked = type else {
            // Re-enable hover for non-tracker animations (cookie popup, etc.)
            privacyDashboardButton.isAnimationEnabled = true
            updatePrivacyEntryPointIcon()
            playPrivacyInfoHighlightAnimationIfNecessary()
            return
        }

        guard let tabViewModel = tabViewModel,
              case .url(let url, _, _) = tabViewModel.tab.content else {
            // Re-enable hover when no valid tab/URL
            privacyDashboardButton.isAnimationEnabled = true
            buttonsBadgeAnimator.processNextAnimation()
            updatePrivacyEntryPointIcon()
            playPrivacyInfoHighlightAnimationIfNecessary()
            return
        }

        guard !buttonsBadgeAnimator.isAnimating else {
            // Don't re-enable yet - more animations pending
            playPrivacyInfoHighlightAnimationIfNecessary()
            return
        }

        // Only play shield animation for HTTPS sites
        guard url.navigationalScheme != .http else {
            // Re-enable hover for HTTP sites (no shield animation)
            privacyDashboardButton.isAnimationEnabled = true
            buttonsBadgeAnimator.processNextAnimation()
            updatePrivacyEntryPointIcon()
            playPrivacyInfoHighlightAnimationIfNecessary()
            return
        }

        playShieldAnimation(for: url)
    }

    private func playShieldAnimation(for url: URL) {
        // Ensure shield is visible and button image is hidden before playing
        privacyDashboardButton.image = nil
        shieldAnimationView.isHidden = false
        shieldDotAnimationView.isHidden = true

        // Prevent new badge animations from starting while shield animation plays
        buttonsBadgeAnimator.isShieldAnimationInProgress = true

        let endFrame = shieldAnimationView.animation?.endFrame ?? 0
        shieldAnimationView.play(fromFrame: 1, toFrame: endFrame, loopMode: .playOnce) { [weak self] finished in
            guard finished, let self = self else { return }

            // Compare URLs ignoring fragments (anchor links within same page)
            guard case .url(let currentURL, _, _) = self.tabViewModel?.tab.content,
                  currentURL.host == url.host,
                  currentURL.path == url.path else { return }

            self.shieldAnimationView.pause()
            self.shieldAnimationView.currentFrame = endFrame
            self.hasShieldAnimationCompleted = true
            // Re-enable hover animation after shield animation completes
            self.privacyDashboardButton.isAnimationEnabled = true
            // Allow badge animations to proceed now that shield is done
            self.buttonsBadgeAnimator.isShieldAnimationInProgress = false
            self.buttonsBadgeAnimator.processNextAnimation()
            // Ensure shield visibility state is correct after animation
            self.updatePrivacyEntryPointIcon()
            self.playPrivacyInfoHighlightAnimationIfNecessary()
        }
    }

}

// MARK: - PermissionContextMenuDelegate

extension AddressBarButtonsViewController: PermissionContextMenuDelegate {

    func permissionContextMenu(_ menu: PermissionContextMenu, mutePermissions permissions: [PermissionType]) {
        tabViewModel?.tab.permissions.set(permissions, muted: true)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, unmutePermissions permissions: [PermissionType]) {
        tabViewModel?.tab.permissions.set(permissions, muted: false)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, allowPermissionQuery query: PermissionAuthorizationQuery) {
        tabViewModel?.tab.permissions.allow(query)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, alwaysAllowPermission permission: PermissionType) {
        permissionManager.setPermission(.allow, forDomain: menu.domain, permissionType: permission)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, alwaysDenyPermission permission: PermissionType) {
        permissionManager.setPermission(.deny, forDomain: menu.domain, permissionType: permission)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, resetStoredPermission permission: PermissionType) {
        permissionManager.setPermission(.ask, forDomain: menu.domain, permissionType: permission)
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, resetTemporaryPopupAllowance: Void) {
        tabViewModel?.tab.popupHandling?.clearPopupAllowanceForCurrentPage()
    }
    func permissionContextMenu(_ menu: PermissionContextMenu, setTemporaryPopupAllowance: Void) {
        tabViewModel?.tab.popupHandling?.setPopupAllowanceForCurrentPage()
    }
    func permissionContextMenuReloadPage(_ menu: PermissionContextMenu) {
        tabViewModel?.reload()
    }

}

// MARK: - NSPopoverDelegate

extension AddressBarButtonsViewController: NSPopoverDelegate {

    func popoverWillShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }

        switch popover {
        case let authPopover as PermissionAuthorizationPopover:
            let permissionType = authPopover.viewController.query?.permissions.first
            updatePermissionCenterButtonIcon(forRequestedPermission: permissionType)
        case is PopupBlockedPopover:
            updatePermissionCenterButtonIcon(forRequestedPermission: .popups)
        default:
            break
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popovers, let popover = notification.object as? NSPopover else { return }

        switch popover {
        case popovers.bookmarkPopover:
            if popovers.bookmarkPopover?.isNew == true {
                NotificationCenter.default.post(name: .bookmarkPromptShouldShow, object: nil)
            }
            updateBookmarkButtonVisibility()
        case popovers.zoomPopover:
            updateZoomButtonVisibility()
        case let authPopover as PermissionAuthorizationPopover:
            if let button = popover.positioningView as? AddressBarButton {
                button.backgroundColor = .clear
                button.mouseOverColor = .buttonMouseOver
            } else {
                assertionFailure("Unexpected popover positioningView: \(popover.positioningView?.description ?? "<nil>"), expected PermissionButton")
            }
            // If popover was closed while authorization was no longer in progress (e.g., system permission denied),
            // treat this as a denial of the website permission to prevent the popover from re-appearing
            if !authPopover.viewController.isAuthorizationInProgress,
               let query = authPopover.viewController.query {
                query.handleDecision(grant: false, remember: nil)
            }
            updatePermissionCenterButtonIcon()
            // Check for other pending permission requests after popover closes
            DispatchQueue.main.async { [weak self] in
                self?.updateAllPermissionButtons()
            }
        case is PopupBlockedPopover:
            if let button = popover.positioningView as? AddressBarButton {
                button.backgroundColor = .clear
                button.mouseOverColor = .buttonMouseOver
            } else {
                assertionFailure("Unexpected popover positioningView: \(popover.positioningView?.description ?? "<nil>"), expected PermissionButton")
            }
            updatePermissionCenterButtonIcon()
            // Check for other pending permission requests after popover closes
            DispatchQueue.main.async { [weak self] in
                self?.updateAllPermissionButtons()
            }
        case is PermissionCenterPopover:
            permissionCenterButton.backgroundColor = .clear
            permissionCenterButton.mouseOverColor = .buttonMouseOver
        default:
            break
        }
    }

}

// MARK: - URL Helpers

extension URL {
    private static let localPatterns = [
        "^localhost$",
        "^::1$",
        "^.+\\.local$",
        "^localhost\\.localhost$",
        "^127\\.0\\.0\\.1$",
        "^10\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^172\\.(1[6-9]|2[0-9]|3[0-1])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^192\\.168\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^169\\.254\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$",
        "^fc[0-9a-fA-F]{2}:.+",
        "^fe80:.+"
    ]

    private static var compiledRegexes: [NSRegularExpression] = {
        var regexes: [NSRegularExpression] = []
        for pattern in localPatterns {
            if let newRegex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                regexes.append(newRegex)
            }
        }
        return regexes
    }()

    var isLocalURL: Bool {
        if let host = self.host {
            for regex in Self.compiledRegexes
            where regex.firstMatch(in: host, options: [], range: host.fullRange) != nil {
                return true
            }
        }
        return false
    }
}

extension TabViewModel {

    @MainActor
    func shouldShowPermissionCenterButton(
        isTextFieldEditorFirstResponder: Bool,
        hasAnyPersistedPermissions: Bool
    ) -> Bool {
        // Show permission buttons when there's a requested permission on NTP even if address bar is focused,
        // since NTP has the address bar focused by default
        let hasRequestedPermission = usedPermissions.values.contains(where: { $0.isRequested })
        let shouldShowWhileFocused = (tab.content == .newtab) && hasRequestedPermission
        let isAnyPermissionPresent = !usedPermissions.values.isEmpty
        let pageInitiatedPopupOpened = tab.popupHandling?.pageInitiatedPopupOpened ?? false

        // Also show when a page-initiated popup was auto-allowed (due to "Always Allow" setting)
        // so user can access permission center to change the decision
        return (shouldShowWhileFocused || (!isTextFieldEditorFirstResponder && (isAnyPermissionPresent || pageInitiatedPopupOpened || hasAnyPersistedPermissions)))
        && !isShowingErrorPage
    }

}
