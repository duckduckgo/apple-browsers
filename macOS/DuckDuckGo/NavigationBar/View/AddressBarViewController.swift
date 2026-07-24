//
//  AddressBarViewController.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Combine
import CombineExtensions
import Lottie
import Common
import FoundationExtensions
import AIChat
import UIComponents
import PixelKit
import PrivacyConfig
import WebExtensions

protocol AddressBarViewControllerDelegate: AnyObject {
    func resizeAddressBarForHomePage(_ addressBarViewController: AddressBarViewController)
    func resizeAddressBarForHomePage(_ addressBarViewController: AddressBarViewController, allowsAsync: Bool)
    func addressBarViewControllerSearchModeToggleChanged(_ addressBarViewController: AddressBarViewController, isAIChatMode: Bool)
    /// Called when the user unfocuses the address bar while duck.ai mode is selected for the current tab.
    /// The panel should stay on screen, but the suggestions row should collapse.
    func addressBarViewControllerDidResignFocusKeepingAIChatMode(_ addressBarViewController: AddressBarViewController)
    /// Called when the user refocuses the address bar while duck.ai mode is the persistent mode for the current tab.
    /// The suggestions row should re-expand and the prompt editor should become first responder.
    func addressBarViewControllerDidRefocusInAIChatMode(_ addressBarViewController: AddressBarViewController)
}

final class AddressBarViewController: NSViewController {

    private let inactiveAddressBarShadowView = ShadowView()

    enum Mode: Equatable {
        enum EditingMode {
            case text
            case url
            case openTabSuggestion
            case aiChat
        }

        case editing(EditingMode)
        case browsing

        var isEditing: Bool {
            return self != .browsing
        }
    }

    /// Represents the selection state of the address bar
    ///
    /// This enum tracks the different active states of the address bar, which determines
    /// UI appearance, keyboard focus behavior, and which input mode is currently active.
    ///
    /// - Note: This is different from `isFirstResponder`, which only tracks whether the
    ///         address bar text field has first responder status. `SelectionState` provides
    ///         a higher-level view of the address bar's interactive state.
    enum SelectionState {
        case inactive
        case active
        case activeWithAIChat
        /// Address bar is unfocused, but duck.ai is the persistent mode for the current tab:
        /// the AI chat panel is hidden and the bar renders identically to `.inactive` (single-line,
        /// no left icon), with the toggle on the duck.ai segment. Clicking the bar re-enters focused
        /// duck.ai (`.activeWithAIChat`); the typed prompt / cursor / tool mode / attachments are preserved.
        case inactiveWithAIChat

        var isSelected: Bool {
            switch self {
            case .inactive, .inactiveWithAIChat: return false
            case .active, .activeWithAIChat: return true
            }
        }

        var isInAIChatMode: Bool {
            switch self {
            case .activeWithAIChat, .inactiveWithAIChat: return true
            case .inactive, .active: return false
            }
        }
    }

    private enum Constants {
        static let switchToTabMinXPadding: CGFloat = 34
        static let defaultActiveTextFieldMinX: CGFloat = 40

        static let maxClickReleaseDistanceToResignFirstResponder: CGFloat = 4
    }

    @IBOutlet var addressBarTextField: AddressBarTextField!
    @IBOutlet var passiveTextField: PassiveAddressBarTextField!
    @IBOutlet var inactiveBackgroundView: ColorView!
    @IBOutlet var activeBackgroundView: ColorView!
    @IBOutlet var activeBackgroundViewWithSuggestions: ColorView!
    @IBOutlet var innerBorderView: ColorView!
    @IBOutlet var bottomSeparatorView: ColorView!
    @IBOutlet var buttonsContainerView: NSView!
    @IBOutlet var switchToTabBox: ColorView!
    @IBOutlet var switchToTabLabel: NSTextField!
    @IBOutlet var shadowView: ShadowView!

    @IBOutlet var activeBackgroundViewTopConstraint: NSLayoutConstraint!
    @IBOutlet var activeBackgroundViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet var activeBackgroundViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var activeBackgroundViewTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var inactiveBackgroundViewTopConstraint: NSLayoutConstraint!
    @IBOutlet var inactiveBackgroundViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet var inactiveBackgroundViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var inactiveBackgroundViewTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var buttonsContainerViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var buttonsContainerViewTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var switchToTabBoxMinXConstraint: NSLayoutConstraint!
    @IBOutlet var passiveTextFieldMinXConstraint: NSLayoutConstraint!
    @IBOutlet var activeTextFieldMinXConstraint: NSLayoutConstraint!
    @IBOutlet var addressBarTextTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var passiveTextFieldTrailingConstraint: NSLayoutConstraint!

    private let popovers: NavigationBarPopovers?
    private(set) var addressBarButtonsViewController: AddressBarButtonsViewController?

    private let tabCollectionViewModel: TabCollectionViewModel
    private let bookmarkManager: BookmarkManager
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let permissionManager: PermissionManagerProtocol
    private let suggestionContainerViewModel: SuggestionContainerViewModel
    private let isBurner: Bool
    private let onboardingPixelReporter: OnboardingAddressBarReporting
    private var tabViewModel: TabViewModel?
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatCoordinator: AIChatCoordinating
    private let searchPreferences: SearchPreferences
    private let tabsPreferences: TabsPreferences
    private let accessibilityPreferences: AccessibilityPreferences
    private let featureFlagger: FeatureFlagger
    private let adBlockingAvailability: AdBlockingAvailabilityProviding

    private var aiChatSettings: AIChatPreferencesStorage

    /// Gets the shared text state from the current tab's view model
    private var sharedTextState: AddressBarSharedTextState? {
        tabViewModel?.addressBarSharedTextState ?? AddressBarSharedTextState()
    }

    /// Deprecated: Remove when `appRebranding` ships
    @IBOutlet var activeOuterBorderView: ColorView!
    @IBOutlet weak var activeOuterBorderTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var activeOuterBorderLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var activeOuterBorderBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var activeOuterBorderTopConstraint: NSLayoutConstraint!

    private var mode: Mode = .editing(.text) {
        didSet {
            addressBarButtonsViewController?.controllerMode = mode
            /// `shouldUseTallAddressBarLayout` keys off `mode.isEditing`, but the height-driving
            /// `resizeAddressBar` only re-runs on tab content changes and focus transitions — not on
            /// mode flips. When a window opens with a stored URL tab, the initial resize reads the
            /// default `mode = .editing(.text)` and locks the bar at the tall focused height; once
            /// the bar's value updates to the loaded URL `mode` flips to `.browsing` but nothing
            /// re-evaluates the height. Trigger a resize on the editing-ness flip so the compact
            /// layout applies immediately on session restore / "Open in New Window".
            if oldValue.isEditing != mode.isEditing {
                requestAddressBarResize()
            }
        }
    }

    private var isSearchOrChatSuggestionsWindowVisible: Bool {
        addressBarTextField.isSuggestionWindowVisible || isAIChatOmnibarVisible
    }

    /// True when the nav bar should render at its tall / focused height
    var shouldUseTallAddressBarLayout: Bool {
        guard themeManager.isAppRebranded else {
            return selectionState.isSelected || selectionState.isInAIChatMode || mode.isEditing
        }

        return selectionState.isSelected && isSearchOrChatSuggestionsWindowVisible
    }

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private(set) var selectionState: SelectionState = .inactive {
        didSet {
            updateView()
            updateSwitchToTabBoxAppearance()
            self.addressBarButtonsViewController?.isTextFieldEditorFirstResponder = selectionState.isSelected
            /// `isAIChatPanelActive` gates the suppression of left-side indicators (privacy shield, permission
            /// center, image button, bookmark). Propagate `isInAIChatMode` so unfocused duck.ai also hides these
            /// — even though the panel itself isn't visible, the bar is logically a prompt input, not a URL
            /// indicator. `isAIChatOmnibarVisible.didSet` also writes this flag; the last write wins, so sequence
            /// the ordering carefully in transitions (flip `isAIChatOmnibarVisible` first, then `selectionState`).
            self.addressBarButtonsViewController?.isAIChatPanelActive = selectionState.isInAIChatMode
            if selectionState == .inactive {
                self.clickPoint = nil // reset click point if the address bar activated during click
            }
        }
    }

    private var displaysTallLayout: Bool = false

    private var isFirstResponder = false {
        didSet {
            handleFirstResponderChange()
        }
    }

    var isSelected: Bool {
        selectionState.isSelected
    }

    private(set) var isHomePage = false {
        didSet {
            updateView()
            suggestionContainerViewModel.isHomePage = isHomePage
        }
    }

    private(set) var isAIChatOmnibarVisible = false {
        didSet {
            addressBarButtonsViewController?.isAIChatPanelActive = isAIChatOmnibarVisible
            if isSelected {
                refreshAppearance(isSuggestionsWindowVisible: addressBarTextField.isSuggestionWindowVisible || isAIChatOmnibarVisible)
            }
        }
    }

    var isInPopUpWindow: Bool {
        tabCollectionViewModel.isPopup
    }

    private var accentColor: NSColor {
        return isBurner ? NSColor.burnerAccent : NSColor.controlAccentColor
    }

    private var cancellables = Set<AnyCancellable>()
    private var tabViewModelCancellables = Set<AnyCancellable>()
    private var shadowWindowFrameObserver: AnyCancellable?

    /// save mouse-down position to handle same-place clicks outside of the Address Bar to remove first responder
    private var clickPoint: NSPoint?

    /// Callback to check if a point (in window coordinates) is within the AI Chat omnibar
    var isPointInAIChatOmnibar: ((NSPoint) -> Bool)?

    /// Called from `escapeKeyDown()` BEFORE any focus-resign work, so the duck.ai omnibar
    /// can swallow Esc when its `@`-mention picker is visible. Returns `true` to indicate
    /// the picker was open and got dismissed; in that case the address bar leaves its
    /// focus / selection state alone. Returns `false` (or nil callback) to fall through
    /// to the regular Esc behavior.
    var aiChatOmnibarHandledEscape: (() -> Bool)?

    weak var delegate: AddressBarViewControllerDelegate?

    // MARK: - View Lifecycle

    required init?(coder: NSCoder) {
        fatalError("AddressBarViewController: Bad initializer")
    }

    init?(coder: NSCoder,
          tabCollectionViewModel: TabCollectionViewModel,
          bookmarkManager: BookmarkManager,
          historyCoordinator: SuggestionContainer.HistoryProvider,
          privacyConfigurationManager: PrivacyConfigurationManaging,
          permissionManager: PermissionManagerProtocol,
          burnerMode: BurnerMode,
          popovers: NavigationBarPopovers?,
          searchPreferences: SearchPreferences,
          tabsPreferences: TabsPreferences,
          accessibilityPreferences: AccessibilityPreferences,
          themeManager: ThemeManaging = NSApp.delegateTyped.themeManager,
          onboardingPixelReporter: OnboardingAddressBarReporting = OnboardingPixelReporter(),
          aiChatSettings: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
          aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
          aiChatCoordinator: AIChatCoordinating,
          featureFlagger: FeatureFlagger,
          adBlockingAvailability: AdBlockingAvailabilityProviding) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.privacyConfigurationManager = privacyConfigurationManager
        self.permissionManager = permissionManager
        self.popovers = popovers
        self.suggestionContainerViewModel = SuggestionContainerViewModel(
            isHomePage: tabViewModel?.tab.content == .newtab,
            isBurner: burnerMode.isBurner,
            suggestionContainer: SuggestionContainer(
                historyProvider: historyCoordinator,
                bookmarkProvider: SuggestionsBookmarkProvider(bookmarkManager: bookmarkManager),
                burnerMode: burnerMode,
                isUrlIgnored: { _ in false }
            ),
            searchPreferences: searchPreferences,
            themeManager: themeManager,
            featureFlagger: featureFlagger
        )
        self.isBurner = burnerMode.isBurner
        self.onboardingPixelReporter = onboardingPixelReporter
        self.aiChatSettings = aiChatSettings
        self.searchPreferences = searchPreferences
        self.tabsPreferences = tabsPreferences
        self.accessibilityPreferences = accessibilityPreferences
        self.themeManager = themeManager
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatCoordinator = aiChatCoordinator
        self.featureFlagger = featureFlagger
        self.adBlockingAvailability = adBlockingAvailability

        super.init(coder: coder)
    }

    @IBSegueAction func createAddressBarButtonsViewController(_ coder: NSCoder) -> AddressBarButtonsViewController? {
        let controller = AddressBarButtonsViewController(coder: coder,
                                                         tabCollectionViewModel: tabCollectionViewModel,
                                                         bookmarkManager: bookmarkManager,
                                                         privacyConfigurationManager: privacyConfigurationManager,
                                                         permissionManager: permissionManager,
                                                         accessibilityPreferences: accessibilityPreferences,
                                                         tabsPreferences: tabsPreferences,
                                                         popovers: popovers,
                                                         aiChatTabOpener: NSApp.delegateTyped.aiChatTabOpener,
                                                         aiChatMenuConfig: aiChatMenuConfig,
                                                         aiChatCoordinator: aiChatCoordinator,
                                                         aiChatSettings: aiChatSettings,
                                                         featureFlagger: featureFlagger,
                                                         adBlockingAvailability: adBlockingAvailability)

        self.addressBarButtonsViewController = controller
        controller?.delegate = self
        return addressBarButtonsViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.masksToBounds = false

        setupBurnerStyleIfNeeded()

        setupAddressBarPlaceHolder()
        addressBarTextField.setAccessibilityIdentifier("AddressBarViewController.addressBarTextField")

        passiveTextField.setAccessibilityIdentifier("AddressBarViewController.passiveTextField")

        passiveTextField.isSelectable = !isInPopUpWindow
        /// Passive Address Bar text field is centered by the constraints
        /// Left alignment is used to prevent jumping of the text field in overflow mode when the buttons width changes
        passiveTextField.alignment = .left
        passiveTextField.lineBreakMode = isInPopUpWindow ? .byTruncatingMiddle : .byTruncatingTail
        passiveTextField.clipsToBounds = true

        switchToTabBox.isHidden = true
        switchToTabLabel.attributedStringValue = SuggestionTableCellView.switchToTabAttributedString

        updateView()
        // only activate active text field leading constraint on its appearance to avoid constraint conflicts
        activeTextFieldMinXConstraint.isActive = false
        addressBarTextField.onboardingDelegate = onboardingPixelReporter

        // allow dropping text to inactive address bar
        inactiveBackgroundView.registerForDraggedTypes( [.string] )

        // disallow dragging window by the background view
        activeBackgroundView.interceptClickEvents = true

        addressBarTextField.focusDelegate = self
        addressBarTextField.searchPreferences = searchPreferences
        addressBarTextField.tabsPreferences = tabsPreferences
        addressBarTextField.aiChatPreferences = aiChatSettings

        setupInactiveShadowView()
        setupActiveOuterBorderSize()
        refreshConstraints()
        refreshSuggestionsAppearance()
    }

    deinit {
#if DEBUG
        addressBarButtonsViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    override func viewWillAppear() {
        if isInPopUpWindow {
            addressBarTextField.isHidden = true
            inactiveBackgroundView.isHidden = true
            activeBackgroundViewWithSuggestions.isHidden = true
            activeOuterBorderView.isHidden = true
            activeBackgroundView.isHidden = true

            shadowView.isHidden = true
            inactiveAddressBarShadowView.removeFromSuperview()
        } else {
            addressBarTextField.suggestionContainerViewModel = suggestionContainerViewModel

            subscribeToAppearanceChanges()
            subscribeToFireproofDomainsChanges()
            addTrackingArea()
            subscribeToMouseEvents()
            subscribeToFirstResponder()
        }
        /// `lastAddressBarTextFieldValue` is now mirrored live from `AddressBarTextField.handleTextDidChange`
        /// (every keystroke writes it into the current tab), so there's no need for a tab-switch snapshot
        /// subscriber here — Combine fires `$selectedTabViewModel` sinks in non-deterministic order, and
        /// any "save outgoing on switch" subscriber would race with `restoreValueIfPossible`'s mutation
        /// of `self.value` and either lose the user's draft or leak it onto a sibling tab.
        addressBarTextField.tabCollectionViewModel = tabCollectionViewModel
        passiveTextField.tabCollectionViewModel = tabCollectionViewModel
        subscribeToSelectedTabViewModel()

        subscribeToAddressBarValue()
        subscribeToButtonsWidth()
        subscribeForShadowViewUpdates()
        subscribeToThemeChanges()

        // Wire the custom toggle control reference to the address bar text field
        // This enables TAB key navigation from text field to toggle
        if let searchModeToggleControl = addressBarButtonsViewController?.searchModeToggleControl {
            addressBarTextField.customToggleControl = searchModeToggleControl
        }
    }

    override func viewWillDisappear() {
        cancellables.removeAll()
        addressBarTextField.tabCollectionViewModel = nil
        passiveTextField.tabCollectionViewModel = nil
    }

    override func viewDidLayout() {
        updateSwitchToTabBoxAppearance()
    }

    // MARK: - Subscriptions

    private func subscribeToAppearanceChanges() {
        guard let window = view.window else {
            assert([.unitTests, .integrationTests].contains(AppVersion.runType),
                   "AddressBarViewController.subscribeToAppearanceChanges: view.window is nil")
            return
        }
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
            .sink { [weak self] _ in
                self?.refreshAddressBarAppearance(nil)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in
                self?.refreshAddressBarAppearance(nil)
            }
            .store(in: &cancellables)

        window.publisher(for: \.childWindows)
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] childWindows in
                guard let childWindows, let self, self.mustDismissSuggestionsWindow(childWindows, titlebarWindow: self.view.window?.titlebarView?.window) else {
                    return
                }

                addressBarTextField.hideSuggestionWindow()
            }
            .store(in: &cancellables) // hide Suggestions on Minimuze/Enter Full Screen

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] _ in
                self?.refreshAddressBarAppearance(nil)
            }
            .store(in: &cancellables)
    }

    /// Determines if the Suggestions Window must be hidden, whenever the specified collection of Child Windows is onscreen
    ///
    private func mustDismissSuggestionsWindow(_ childWindows: [NSWindow], titlebarWindow: NSWindow?) -> Bool {
        childWindows.contains { window in
            !(
                window.windowController is TabPreviewWindowController
                || window.contentViewController is SuggestionViewController
                || window === titlebarWindow
                || window.contentViewController?.identifier == .updateNotificationPopover
            )
        }
    }

    private func subscribeToFireproofDomainsChanges() {
        NotificationCenter.default.publisher(for: FireproofDomains.Constants.allowedDomainsChangedNotification)
            .sink { [weak self] _ in
                self?.refreshAddressBarAppearance(nil)
            }
            .store(in: &cancellables)
    }

    private func subscribeToSelectedTabViewModel() {
        tabCollectionViewModel.$selectedTabViewModel
            .sink { [weak self] tabViewModel in
                guard let self else { return }

                let wasInAIChatMode = self.selectionState.isInAIChatMode

                self.tabViewModel = tabViewModel
                tabViewModelCancellables.removeAll()

                // Update the text field's shared text state for the new tab
                addressBarTextField.sharedTextState = sharedTextState

                subscribeToTabContent()

                // don't resign first responder on tab switching
                clickPoint = nil

                applyIncomingTabAIChatMode(wasInAIChatMode: wasInAIChatMode)
            }
            .store(in: &cancellables)
    }

    /// Reconciles the selection state with the newly selected tab's persistent duck.ai flag.
    /// Per the redesign the unfocused duck.ai bar looks identical to unfocused search (one-line passive text field,
    /// panel hidden). Tab switches always land in the unfocused state: `.inactiveWithAIChat` for duck.ai tabs,
    /// `.inactive` otherwise. The user can click the bar or the toggle to enter focused duck.ai.
    private func applyIncomingTabAIChatMode(wasInAIChatMode: Bool) {
        let incomingIsInDuckAIMode = sharedTextState?.isInDuckAIMode ?? false

        switch (wasInAIChatMode, incomingIsInDuckAIMode) {
        case (true, true), (false, true):
            /// Incoming tab has duck.ai selected — sync toggle + land in unfocused duck.ai without opening the panel.
            /// `isAIChatOmnibarVisible` is flipped BEFORE `selectionState` so `updateView` (triggered by the state
            /// change) sees the panel-hidden flag and drops the suggestions-variant background; otherwise the
            /// unfocused bar renders at the taller focused-with-suggestions height.
            /// `makeFirstResponder(nil)` drops any FR on `addressBarTextField` inherited from the outgoing tab
            /// (e.g. the new-tab NTP path makes it FR). Without it the field editor stays active over the
            /// now-unfocused duck.ai bar and renders the suffix + selected text on top of our plain-looking bar.
            /// `applyDuckAIUnfocusedValue` pushes the incoming tab's preserved prompt onto the bar — otherwise
            /// on a URL-loaded tab the value would still be the URL and the bar would render the URL + shield.
            /// `addressBarViewControllerDidResignFocusKeepingAIChatMode` drives `hideAIChatOmnibarPanelKeepingTabState`
            /// to close the panel container if the outgoing tab had it open (e.g. NTP with Duck.ai, where the focused
            /// panel is the default UX). Without this the incoming tab inherits the expanded panel while `selectionState`
            /// already reads `.inactiveWithAIChat`, rendering a broken focused-looking view. The delegate target guards
            /// on `mainView.isAIChatOmnibarContainerShown`, so it no-ops when the panel was already hidden.
            addressBarButtonsViewController?.syncToggleSegmentToAIChatMode()
            isAIChatOmnibarVisible = false
            addressBarTextField.applyDuckAIUnfocusedValue()
            selectionState = .inactiveWithAIChat
            updateMode()
            view.window?.makeFirstResponder(nil)
            requestAddressBarResize()
            delegate?.addressBarViewControllerDidResignFocusKeepingAIChatMode(self)
        case (true, false):
            /// Incoming tab is in search mode — fully dismiss the duck.ai panel (in case it was up) and reset the toggle.
            delegate?.addressBarViewControllerSearchModeToggleChanged(self, isAIChatMode: false)
            setAIChatOmnibarVisible(false)
            /// On Cmd+T from a Duck.ai tab, the new NTP tab should land in focused search mode (cursor in
            /// the bar, "Search or enter address" placeholder). MainVC's `adjustFirstResponder` chain
            /// normally grabs focus for NTP, but the Duck.ai panel's close + AIChatOmnibarTextContainerVC
            /// resignation race can leave the bar unfocused with `selectionState.isInAIChatMode` lingering
            /// and the wrong placeholder showing. Explicitly making the address bar first responder here
            /// converges the new tab to `.active` via `handleFirstResponderChange`. URL-loaded incoming
            /// tabs are unaffected — they should land unfocused with the URL passively rendered.
            if tabViewModel?.tab.content == .newtab {
                addressBarTextField.makeMeFirstResponder()
            }
        case (false, false):
            break
        }
    }

    private func subscribeToAddressBarValue() {
        addressBarTextField.$value
            .sink { [weak self] value in
                guard let self else { return }

                updateMode(value: value)
                addressBarButtonsViewController?.textFieldValue = value
                updateView()
                updateSwitchToTabBoxAppearance()
            }
            .store(in: &cancellables)
    }

    private func subscribeToTabContent() {
        tabViewModel?.tab.$content
            .map { $0 == .newtab }
            .assign(to: \.isHomePage, onWeaklyHeld: self)
            .store(in: &tabViewModelCancellables)

        /// Navigation within the tab (link click, back/forward, reload) should exit duck.ai mode:
        /// tear the panel down and reset the toggle so the address bar returns to its normal search state.
        /// Triggered from a `Tab.Content` change rather than from the shared state publisher to avoid re-entering
        /// `setAIChatOmnibarVisible` while it is in the process of clearing shared state.
        tabViewModel?.tab.$content
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, selectionState.isInAIChatMode else { return }
                delegate?.addressBarViewControllerSearchModeToggleChanged(self, isAIChatMode: false)
                setAIChatOmnibarVisible(false)
            }
            .store(in: &tabViewModelCancellables)
    }

    private func subscribeToButtonsWidth() {
        guard let addressBarButtonsViewController else {
            assertionFailure("AddressBarViewController.subscribeToButtonsWidth: addressBarButtonsViewController is nil")
            return
        }

        addressBarButtonsViewController.$buttonsWidth
            .sink { [weak self] value in
                self?.layoutTextFields(withMinX: value)
            }
            .store(in: &cancellables)

        addressBarButtonsViewController.$trailingButtonsWidth
            .sink { [weak self] value in
                self?.layoutTextFields(trailingWidth: value)
            }
            .store(in: &cancellables)
    }

    private func subscribeForShadowViewUpdates() {
        addressBarTextField.isSuggestionWindowVisiblePublisher
            .sink { [weak self] isSuggestionsWindowVisible in
                guard let self else { return }
                self.refreshAppearance(isSuggestionsWindowVisible: isSuggestionsWindowVisible || self.isAIChatOmnibarVisible)
                if isSuggestionsWindowVisible || self.isAIChatOmnibarVisible {
                    self.layoutShadowView()
                }
            }
            .store(in: &cancellables)

        view.superview?.publisher(for: \.frame)
            .sink { [weak self] _ in
                self?.layoutShadowView()
            }
            .store(in: &cancellables)
    }

    private func addTrackingArea() {
        let trackingArea = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        self.view.addTrackingArea(trackingArea)
    }

    private func subscribeToMouseEvents() {
        NSEvent.addLocalCancellableMonitor(forEventsMatching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.mouseDown(with: event)
        }.store(in: &cancellables)
        NSEvent.addLocalCancellableMonitor(forEventsMatching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            return self.mouseUp(with: event)
        }.store(in: &cancellables)
        NSEvent.addLocalCancellableMonitor(forEventsMatching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.rightMouseDown(with: event)
        }.store(in: &cancellables)
    }

    private func subscribeToFirstResponder() {
        guard let window = view.window else {
            assert([.unitTests, .integrationTests].contains(AppVersion.runType),
                   "AddressBarViewController.subscribeToFirstResponder: view.window is nil")
            return
        }
        NotificationCenter.default.publisher(for: MainWindow.firstResponderDidChangeNotification, object: window)
            .sink { [weak self] in
                self?.firstResponderDidChange($0)
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    /// Workaround for macOS 26.0 NSTextFieldSimpleLabel rendering bug
    /// Sets the alpha value for internal label views that incorrectly remain visible
    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1211448334620171?focus=true
    @available(macOS 26.0, *)
    private func setInternalTextFieldLabelsAlpha(_ alpha: CGFloat, in textField: NSTextField) {
        guard featureFlagger.isFeatureOn(.blurryAddressBarTahoeFix) else { return }
        for subview in textField.subviews where NSStringFromClass(type(of: subview)).contains("NSTextFieldSimpleLabel") {
            subview.alphaValue = alpha
        }
    }

    /// Workaround for macOS 26.0 NSTextFieldSimpleLabel rendering bug
    /// Aggressively hides internal label views that incorrectly remain visible
    @available(macOS 26.0, *)
    private func forceHideInternalTextFieldLabels(in textField: NSTextField) {
        setInternalTextFieldLabelsAlpha(0, in: textField)
    }

    /// Restore previously hidden NSTextFieldSimpleLabel views when address bar defocuses
    @available(macOS 26.0, *)
    private func restoreInternalTextFieldLabels(in textField: NSTextField) {
        setInternalTextFieldLabelsAlpha(1, in: textField)
    }

    private func updateView() {
        let colorsProvider = theme.colorsProvider

        switch selectionState {
        case .activeWithAIChat:
            /// Focused Duck.ai: the prompt panel covers the address-bar area. Hide both text fields so their
            /// text / suffix doesn't peek out past the panel edges.
            addressBarTextField.isHidden = true
            passiveTextField.isHidden = true
        case .inactiveWithAIChat:
            /// Unfocused Duck.ai: always render via `addressBarTextField` showing the preserved prompt (or empty
            /// for the "Ask anything privately" placeholder). The value is pushed onto the field by the transitions
            /// that enter this state (`resignFocusKeepingAIChatMode`, `applyIncomingTabAIChatMode`, and
            /// `refocusInAIChatMode` when bouncing in/out), not here — calling `applyDuckAIUnfocusedValue` from
            /// inside `updateView` would recurse through the `$value` sink.
            addressBarTextField.isHidden = false
            passiveTextField.isHidden = true
        case .active, .inactive:
            let isPassiveTextFieldHidden = selectionState.isSelected || mode.isEditing
            addressBarTextField.isHidden = isPassiveTextFieldHidden ? false : true
            passiveTextField.isHidden = isPassiveTextFieldHidden ? true : false
        }
        passiveTextField.textColor = colorsProvider.textPrimaryColor

        // Workaround for macOS 26.0 NSTextFieldSimpleLabel rendering bug.
        // The internal labels get `alpha = 0` when the text field is hidden; un-hiding the field (e.g. transitioning
        // out of `.activeWithAIChat` into `.inactiveWithAIChat`) must restore them or the text won't render.
        if #available(macOS 26.0, *), featureFlagger.isFeatureOn(.blurryAddressBarTahoeFix) {
            if addressBarTextField.isHidden {
                forceHideInternalTextFieldLabels(in: addressBarTextField)
            } else {
                restoreInternalTextFieldLabels(in: addressBarTextField)
            }
        }

        updateShadowViewPresence(selectionState.isSelected)
        inactiveBackgroundView.backgroundColor = colorsProvider.inactiveAddressBarBackgroundColor

        /// When duck.ai is active, the extended `activeBackgroundViewWithSuggestions` is the single background
        /// behind the bar (it merges with the panel below). Suppress the regular inactive / active variants to
        /// avoid two layers rendering with different widths — that's the ~1pt edge mismatch and the
        /// "address-bar-like" look on tab-switch back into a Duck.ai tab. `refreshAppearance` (fired off the
        /// suggestion-window publisher) handles the suggestions-visible case; don't duplicate its isHidden flips
        /// here or we risk racing it after first ESC closes the suggestions window.
        inactiveBackgroundView.alphaValue = (selectionState.isSelected || isAIChatOmnibarVisible) ? 0 : 1
        activeBackgroundView.alphaValue = (selectionState.isSelected && !isAIChatOmnibarVisible) ? 1 : 0

        if themeManager.isAppRebranded {
            addressBarButtonsViewController?.trailingButtonsBackgroundColor = .clear
        }

        let isKey = self.view.window?.isKeyWindow == true
        let isToggleFocused = view.window?.firstResponder === addressBarButtonsViewController?.searchModeToggleControl

        /// The outer blue glow is a "prompt the user to type" state — once the user has actually typed
        /// something, drop it so the bar reads as editing-in-progress rather than empty-and-inviting.
        /// Without this the glow reappears after ESC closes the suggestions window (where it had been
        /// visually masked by the merged suggestions background) even though the bar still holds the
        /// user's draft.
        let currentTextFieldValue = addressBarTextField.value
        let hasUserTypedContent = currentTextFieldValue.isUserTyped && !currentTextFieldValue.isEmpty
        activeOuterBorderView.alphaValue = isKey && selectionState.isSelected && !isToggleFocused && !hasUserTypedContent && theme.addressBarStyleProvider.shouldShowOutlineBorder(isHomePage: isHomePage) ? 1 : 0
        activeOuterBorderView.backgroundColor = isBurner ? NSColor.burnerAccent.withAlphaComponent(0.2) : colorsProvider.addressBarOutlineShadow

        if isToggleFocused {
            activeBackgroundView.borderWidth = 1.0
            activeBackgroundView.borderColor = .addressBarBorder
        } else {
            activeBackgroundView.borderWidth = 2.0
            activeBackgroundView.borderColor = isBurner ? colorsProvider.addressBarFireBorderColor : colorsProvider.addressBarActiveBorderColor
        }

        setupBurnerStyleIfNeeded()

        setupAddressBarPlaceHolder()
        refreshAddressBarCornerRadius()
        inactiveAddressBarShadowView.isHidden = selectionState.isSelected
    }

    private func refreshAddressBarCornerRadius() {
        let styleProvider = theme.addressBarStyleProvider
        let isSuggestionsWindowVisible = isSearchOrChatSuggestionsWindowVisible

        activeBackgroundView.cornerRadius = styleProvider.addressBarActiveBackgroundViewRadius
        activeBackgroundViewWithSuggestions.cornerRadius = styleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions
        activeOuterBorderView.cornerRadius = styleProvider.addressBarActiveOuterBorderViewRadius
        inactiveBackgroundView.cornerRadius = styleProvider.addressBarInactiveBackgroundViewRadius
        innerBorderView.cornerRadius = styleProvider.addressBarInnerBorderViewRadius(isSuggestionsWindowVisible: isSuggestionsWindowVisible)

        if themeManager.isAppRebranded {
            let roundedCorners: RoundedCorners = isSuggestionsWindowVisible ? [.topLeft, .topRight] : .all

            innerBorderView.roundedCorners = roundedCorners
            activeBackgroundViewWithSuggestions.roundedCorners = roundedCorners
        }
    }

    private func setupInactiveShadowView() {
        if theme.addressBarStyleProvider.shouldAddAddressBarShadowWhenInactive {
            inactiveAddressBarShadowView.shadowColor = NSColor.shadowPrimary
            inactiveAddressBarShadowView.shadowOpacity = 1
            inactiveAddressBarShadowView.shadowOffset = CGSize(width: 0, height: 0)
            inactiveAddressBarShadowView.shadowRadius = 3
            inactiveAddressBarShadowView.shadowSides = .all
            inactiveAddressBarShadowView.cornerRadius = theme.addressBarStyleProvider.addressBarInactiveBackgroundViewRadius
            inactiveAddressBarShadowView.translatesAutoresizingMaskIntoConstraints = false

            view.addSubview(inactiveAddressBarShadowView, positioned: .below, relativeTo: inactiveBackgroundView)

            NSLayoutConstraint.activate([
                inactiveAddressBarShadowView.leadingAnchor.constraint(equalTo: inactiveBackgroundView.leadingAnchor),
                inactiveAddressBarShadowView.trailingAnchor.constraint(equalTo: inactiveBackgroundView.trailingAnchor),
                inactiveAddressBarShadowView.topAnchor.constraint(equalTo: inactiveBackgroundView.topAnchor),
                inactiveAddressBarShadowView.bottomAnchor.constraint(equalTo: inactiveBackgroundView.bottomAnchor)
            ])
        }
    }

    private func setupActiveOuterBorderSize() {
        activeOuterBorderTrailingConstraint.constant = theme.addressBarStyleProvider.addressBarActiveOuterBorderSize
        activeOuterBorderLeadingConstraint.constant = theme.addressBarStyleProvider.addressBarActiveOuterBorderSize
        activeOuterBorderBottomConstraint.constant = theme.addressBarStyleProvider.addressBarActiveOuterBorderSize
        activeOuterBorderTopConstraint.constant = theme.addressBarStyleProvider.addressBarActiveOuterBorderSize
    }

    private func refreshConstraints() {
        let styleProvider = theme.addressBarStyleProvider

        activeBackgroundViewTopConstraint.constant = styleProvider.addressBarActiveBackgroundViewVerticalPadding
        activeBackgroundViewBottomConstraint.constant = styleProvider.addressBarActiveBackgroundViewVerticalPadding
        inactiveBackgroundViewTopConstraint.constant = styleProvider.addressBarInactiveBackgroundViewVerticalPadding
        inactiveBackgroundViewBottomConstraint.constant = styleProvider.addressBarInactiveBackgroundViewVerticalPadding
        inactiveBackgroundViewLeadingConstraint.constant = styleProvider.addressBarInactiveBackgroundViewLeadingPadding
        inactiveBackgroundViewTrailingConstraint.constant = styleProvider.addressBarInactiveBackgroundViewTrailingPadding
        buttonsContainerViewLeadingConstraint.constant = styleProvider.addressBarButtonsContainerViewLeadingPadding
        buttonsContainerViewTrailingConstraint.constant = styleProvider.addressBarButtonsContainerViewTrailingPadding
    }

    private func setupBurnerStyleIfNeeded() {
        guard isBurner, themeManager.isAppRebranded else { return }

        let style = BurnerAppearanceStyle()
        style.enableDarkModeOverride(in: view)
    }

    private func setupAddressBarPlaceHolder() {
        let isNewTab = tabViewModel?.tab.content == .newtab
        let addressBarPlaceholder: String

        if selectionState.isInAIChatMode {
            /// Duck.ai (focused or unfocused) — the bar represents a prompt input, not an address. Use the
            /// same placeholder as the Duck.ai panel's prompt editor so the empty-state label matches across
            /// focused and unfocused states.
            addressBarPlaceholder = UserText.aiChatOmnibarPlaceholder
        } else {
            /// In search mode the placeholder always reads "Search or enter address". `NSTextField` only
            /// paints it when `stringValue` is empty, so this naturally appears on a fresh NTP and after
            /// the user clears a URL on a loaded page, and stays out of the way while a URL is displayed.
            /// Unfocused URL display is owned by `passiveTextField` and is unaffected by this string.
            addressBarPlaceholder = UserText.addressBarPlaceholder
        }

        let font = NSFont.systemFont(ofSize: isNewTab ? theme.addressBarStyleProvider.newTabOrHomePageAddressBarFontSize : theme.addressBarStyleProvider.defaultAddressBarFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.colorsProvider.textSecondaryColor,
            .font: font
        ]
        addressBarTextField.placeholderAttributedString = NSAttributedString(string: addressBarPlaceholder, attributes: attributes)
    }

    private func updateSwitchToTabBoxAppearance() {
        guard case .editing(.openTabSuggestion) = mode,
              addressBarTextField.isVisible, let editor = addressBarTextField.editor,
              view.frame.size.width > 280 else {
            switchToTabBox.isHidden = true
            switchToTabBox.alphaValue = 0
            return
        }

        if !switchToTabBox.isVisible {
            switchToTabBox.isShown = true
            switchToTabBox.alphaValue = 0
        }
        // update box position on the next pass after text editor layout is updated
        DispatchQueue.main.async {
            self.switchToTabBox.alphaValue = 1
            self.switchToTabBoxMinXConstraint.constant = editor.textSize.width + Constants.switchToTabMinXPadding
        }
    }

    private func updateShadowViewPresence(_ isFirstResponder: Bool) {
        guard isFirstResponder, !isInPopUpWindow else {
            shadowView.removeFromSuperview()
            shadowWindowFrameObserver?.cancel()
            shadowWindowFrameObserver = nil
            return
        }
        if shadowView.superview == nil {
            refreshAppearance(isSuggestionsWindowVisible: addressBarTextField.isSuggestionWindowVisible || isAIChatOmnibarVisible)
            view.window?.contentView?.addSubview(shadowView)
            layoutShadowView()

            if let window = view.window {
                shadowWindowFrameObserver = window.publisher(for: \.frame)
                    .sink { [weak self] _ in
                        self?.layoutShadowView()
                    }
            }
        }
    }

    private func refreshAppearance(isSuggestionsWindowVisible: Bool) {
        let styleProvider = theme.addressBarStyleProvider
        let colorsProvider = theme.colorsProvider

        shadowView.shadowSides = isSuggestionsWindowVisible ? [.left, .top, .right] : []
        shadowView.cornerRadius = styleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions

        NSAppearance.withAppAppearance {
            if themeManager.isAppRebranded {
                shadowView.shadowRadius = styleProvider.suggestionShadowRadius
                shadowView.shadowColor = colorsProvider.addressBarShadowColor
            } else {
                shadowView.shadowRadius = isSuggestionsWindowVisible ? theme.addressBarStyleProvider.suggestionShadowRadius : 0.0
                shadowView.shadowColor = isSuggestionsWindowVisible ? .suggestionsShadow : .clear
            }
        }

        let isToggleFocused = view.window?.firstResponder === addressBarButtonsViewController?.searchModeToggleControl
        activeOuterBorderView.isHidden = isSuggestionsWindowVisible || view.window?.isKeyWindow != true || isToggleFocused
        activeBackgroundView.isHidden = isSuggestionsWindowVisible
        activeBackgroundViewWithSuggestions.isHidden = !isSuggestionsWindowVisible
        inactiveAddressBarShadowView.isHidden = isSuggestionsWindowVisible

        if themeManager.isAppRebranded {
            /// When Search Suggestions (OR) Omnibar are rendered, we'll switch to the Extended Height mode, with different rounded corners
            resizeAddressBarIfNeeded()
            refreshAddressBarCornerRadius()
        }
    }

    private func layoutShadowView() {
        guard let superview = shadowView.superview else { return }

        let winFrame = self.view.convert(self.view.bounds, to: nil)
        var frame = superview.convert(winFrame, from: nil)

        /// Keep the suggestions shadow aligned with the panel by applying the same vertical offset.
        let offset = AddressBarTextField.SuggestionWindowSizes.shadowOffset(isAppRebranded: themeManager.isAppRebranded)
        frame.origin.y += offset
        frame.size.height -= offset

        shadowView.frame = frame
    }

    private func updateMode(value: AddressBarTextField.Value? = nil) {
        /// Whenever the tab is in duck.ai mode (focused or unfocused) the bar represents a prompt input, not an
        /// address — keep `mode` pinned to `.editing(.aiChat)` so downstream button / icon / placeholder logic
        /// treats it as such regardless of what URL / text the underlying `addressBarTextField.value` currently
        /// holds (the sync from shared state happens asynchronously on the main queue).
        if selectionState.isInAIChatMode {
            self.mode = .editing(.aiChat)
            return
        }
        switch value ?? self.addressBarTextField.value {
        case .text: self.mode = .editing(.text)
        case .url(urlString: _, url: _, userTyped: let userTyped): self.mode = userTyped ? .editing(.url) : .browsing
        case .suggestion(let suggestionViewModel):
            switch suggestionViewModel.suggestion {
            case .phrase, .unknown, .askAIChat:
                self.mode = .editing(.text)
            case .website, .bookmark, .historyEntry, .internalPage:
                self.mode = .editing(.url)
            case .openTab:
                self.mode = .editing(.openTabSuggestion)
            }
        }
    }

    @objc private func refreshAddressBarAppearance(_ sender: Any?) {
        self.updateMode()
        self.addressBarButtonsViewController?.updateButtons()

        guard let window = view.window else {
            return
        }

        guard AppVersion.runType != .unitTests else {
            return
        }

        // Hide suggestions when a Sheet is presented (Open panel, Fire dialog…)
        if window.sheets.isEmpty == false {
            addressBarTextField.hideSuggestionWindow()
        }

        addressBarTextField.refreshStyle()
        bottomSeparatorView.isHidden = !themeManager.isAppRebranded

        let colorsProvider = theme.colorsProvider
        let navigationBarBackgroundColor = colorsProvider.navigationBackgroundColor

        NSAppearance.withAppAppearance {
            // Keep selected appearance when AI chat is active (OR) isBurner, even if window loses key status
            let shouldShowActiveState = window.isKeyWindow || selectionState == .activeWithAIChat || isBurner
            let isToggleFocused = window.firstResponder === addressBarButtonsViewController?.searchModeToggleControl

            if shouldShowActiveState {
                if isToggleFocused {
                    activeBackgroundView.borderWidth = 1.0
                    activeBackgroundView.borderColor = .addressBarBorder
                } else {
                    activeBackgroundView.borderWidth = 2.0
                    activeBackgroundView.borderColor = isBurner ? colorsProvider.addressBarFireBorderColor : colorsProvider.addressBarActiveBorderColor
                }
                activeBackgroundView.backgroundColor = theme.colorsProvider.activeAddressBarBackgroundColor
                switchToTabBox.backgroundColor = navigationBarBackgroundColor.blended(with: .addressBarBackground)

                /// Important: `activeOuterBorderView` is hidden when `isAppRedesign` evaluates as true
                activeOuterBorderView.isHidden = isToggleFocused || !theme.addressBarStyleProvider.shouldShowOutlineBorder(isHomePage: isHomePage) || selectionState == .activeWithAIChat
                activeOuterBorderView.backgroundColor = isBurner ? NSColor.burnerAccent.withAlphaComponent(0.2) : theme.colorsProvider.addressBarOutlineShadow

                if !themeManager.isAppRebranded {
                    addressBarButtonsViewController?.trailingButtonsBackgroundColor = theme.colorsProvider.activeAddressBarBackgroundColor
                }

            } else {
                activeBackgroundView.borderWidth = 0
                activeBackgroundView.borderColor = nil
                activeBackgroundView.backgroundColor = theme.colorsProvider.inactiveAddressBarBackgroundColor

                switchToTabBox.backgroundColor = navigationBarBackgroundColor.blended(with: .inactiveSearchBarBackground)

                activeOuterBorderView.isHidden = true

                if !themeManager.isAppRebranded {
                    addressBarButtonsViewController?.trailingButtonsBackgroundColor = theme.colorsProvider.inactiveAddressBarBackgroundColor
                }
            }
        }
    }

    func refreshAddressBarBackgroundWidth() {
        let styleProvider = theme.addressBarStyleProvider
        guard let padding = styleProvider.addressBarHorizontalPadding(focused: shouldUseTallAddressBarLayout) else {
            return
        }

        activeBackgroundViewLeadingConstraint.constant = padding
        activeBackgroundViewTrailingConstraint.constant = padding
    }

    private func refreshSuggestionsAppearance() {
        activeBackgroundViewWithSuggestions.backgroundColor = theme.colorsProvider.suggestionsBackgroundColor
    }

    private func layoutTextFields(withMinX minX: CGFloat) {
        /// Keep the text leading X fixed across focused / unfocused / mode transitions so accepting a suggestion
        /// (which flips `mode` between `.text` / `.url` / `.openTabSuggestion`) doesn't visibly shift the text.
        /// When the toggle feature is on, all editing states have no left icon, so we pin the text at a constant
        /// padding that matches the Duck.ai prompt panel's leading inset. When the buttons container is wider
        /// (e.g. browsing with the privacy dashboard showing), we respect that width so the text clears the button.
        let isToggleFeatureEnabled = aiChatSettings.isAIFeaturesEnabled
        let isToggleVisible = isToggleFeatureEnabled && aiChatSettings.showSearchAndDuckAIToggle

        let styleProvider = theme.addressBarStyleProvider
        let duckAILeadingPadding: CGFloat = styleProvider.addressBarTextFieldLeadingPadding

        if isToggleVisible {
            let effectiveMinX = max(minX, duckAILeadingPadding)
            self.passiveTextFieldMinXConstraint.constant = effectiveMinX
            self.activeTextFieldMinXConstraint.constant = effectiveMinX
            return
        }

        self.passiveTextFieldMinXConstraint.constant = max(minX, duckAILeadingPadding)
        let isAddressBarFocused = view.window?.firstResponder == addressBarTextField.currentEditor()
        let adjustedMinX: CGFloat = (!self.isSelected || self.mode.isEditing) ? max(minX, duckAILeadingPadding) : Constants.defaultActiveTextFieldMinX

        /// The negative offset compensates for the leading padding of the search icon so the typed text sits
        /// flush against it (the buttons side sets a matching positive pad on the privacy-shield constraint —
        /// see `AddressBarButtonsViewController.IconLeadingTuning`). With the redesign, editing states
        /// (`.text`, `.url`, `.openTabSuggestion`, `.aiChat`) no longer render a leading icon — skip the
        /// offset so the text isn't pushed past the (now-narrower) buttons container's left edge on that path.
        if styleProvider.shouldShowNewSearchIcon && !self.mode.isEditing {
            let pullback = isAddressBarFocused
                ? AddressBarButtonsViewController.IconLeadingTuning.textFieldPullback.focused
                : AddressBarButtonsViewController.IconLeadingTuning.textFieldPullback.unfocused
            self.activeTextFieldMinXConstraint.constant = adjustedMinX - pullback
        } else {
            self.activeTextFieldMinXConstraint.constant = adjustedMinX
        }
    }

    private func layoutTextFields(trailingWidth width: CGFloat) {
        addressBarTextTrailingConstraint.constant = width
        passiveTextFieldTrailingConstraint.constant = width
    }

    private func firstResponderDidChange(_ notification: Notification) {
        let firstResponder = view.window?.firstResponder
        let isToggleFocused = firstResponder === addressBarButtonsViewController?.searchModeToggleControl

        if firstResponder === addressBarTextField.currentEditor() || isToggleFocused {
            if !isFirstResponder {
                isFirstResponder = true
            }
            activeTextFieldMinXConstraint.isActive = true
            updateView()
            refreshAddressBarAppearance(nil)
        } else if isFirstResponder {
            isFirstResponder = false

            // Remove suffix when address bar loses focus
            addressBarTextField.refreshStyle()

            // Restore internal text field labels when address bar loses focus
            if #available(macOS 26.0, *), featureFlagger.isFeatureOn(.blurryAddressBarTahoeFix) {
                restoreInternalTextFieldLabels(in: addressBarTextField)
            }

            updateView()
            refreshAddressBarAppearance(nil)

            requestAddressBarResize()
            addressBarButtonsViewController?.setupButtonPaddings(isFocused: false)
        }

        setupAddressBarPlaceHolder()
    }

    private func handleFirstResponderChange() {
        let isToggleFocused = view.window?.firstResponder === addressBarButtonsViewController?.searchModeToggleControl

        switch selectionState {
        case .inactive:
            if isFirstResponder {
                selectionState = .active
                fireAddressBarActivatedPixelIfNeeded()
            }
        case .active:
            if !isFirstResponder && !isToggleFocused {
                selectionState = .inactive
            }
        case .activeWithAIChat:
            // Focused duck.ai mode doesn't use the address bar's first-responder flag — the prompt editor is a
            // separate NSTextView. Focus transitions out of this state are driven explicitly by click-outside/Escape/toggle.
            break
        case .inactiveWithAIChat:
            if isFirstResponder {
                /// User clicked the address bar while duck.ai is the persistent mode for the tab. Don't let
                /// `addressBarTextField` stay first responder (its editor becoming responder is what triggered
                /// this call); bounce back into focused Duck.ai instead so the panel reappears with the preserved
                /// prompt / cursor / tool mode / attachments and the Duck.ai text view takes focus.
                view.window?.makeFirstResponder(nil)
                refocusInAIChatMode()
                fireAddressBarActivatedPixelIfNeeded()
            }
        }

        setupAddressBarPlaceHolder()
    }

    private func fireAddressBarActivatedPixelIfNeeded() {
        guard aiChatSettings.isAIFeaturesEnabled else {
            return
        }

        let isToggleSettingOn = aiChatSettings.showSearchAndDuckAIToggle
        let pixel: AIChatPixel = isToggleSettingOn ? .aiChatAddressBarActivatedToggleOn : .aiChatAddressBarActivatedToggleOff
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    // MARK: - Event handling

    func escapeKeyDown() -> Bool {
        /// Duck.ai's `@`-mention picker gets first crack at Esc. When the picker is
        /// visible, dismissing it is the user's intent — they don't expect Esc to also
        /// resign the omnibar's focus or move the bar out of duck.ai mode. Returning
        /// here short-circuits the entire focus-state machine below.
        if aiChatOmnibarHandledEscape?() == true {
            return true
        }

        /// Second Escape press while unfocused in duck.ai mode: fully exit duck.ai for this tab, mirroring the
        /// "clear content and mode" step search mode performs. `addressBarTextField.escapeKeyDown()` resets the
        /// bar's value to the tab's URL (or empty for NTP) and calls `sharedTextState?.reset(clearingDuckAIState: true)`
        /// via `updateValue`, which clears the preserved prompt / selection / tool mode / attachments / duck.ai flag.
        if selectionState == .inactiveWithAIChat {
            selectionState = .inactive
            addressBarTextField.escapeKeyDown()
            addressBarButtonsViewController?.resetSearchModeToggle()
            updateMode()
            return true
        }

        guard selectionState.isSelected else { return false }

        if selectionState == .activeWithAIChat {
            /// First Escape press in focused duck.ai: just resign focus. The tab stays in duck.ai mode, the prompt
            /// stays in `passiveTextField`, and the tool / attachment state is preserved for the next refocus.
            resignFocusKeepingAIChatMode()
            return true
        }

        if mode.isEditing {
            addressBarTextField.escapeKeyDown()
            return true
        }

        view.window?.makeFirstResponder(nil)

        return true
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isInPopUpWindow else { return }
        NSCursor.iBeam.set()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard event.window === self.view.window, !isInPopUpWindow else { return }

        let point = self.view.convert(event.locationInWindow, from: nil)
        let view = self.view.hitTest(point)

        if view?.shouldShowArrowCursor == true {
            NSCursor.arrow.set()
        } else {
            NSCursor.iBeam.set()
        }

        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseExited(with: event)
    }

    func mouseDown(with event: NSEvent) -> NSEvent? {
        self.clickPoint = nil
        guard let window = self.view.window, event.window === window, window.sheets.isEmpty else { return event }

        if window.isKeyWindow, beginDraggingSessionIfNeeded(with: event, in: window) {
            return nil
        }

        if let point = self.view.mouseLocationInsideBounds(event.locationInWindow) {
            let hitView = self.view.hitTest(point)

            if hitView?.shouldShowArrowCursor == true {
                return event
            }

            // In focused AI chat mode, only block clicks specifically on the address bar text fields
            // Allow clicks elsewhere (like on the AI chat text view).
            if selectionState == .activeWithAIChat {
                return isHitViewInsideAddressBarTextFields(hitView) ? nil : event
            }

            // Unfocused duck.ai renders as a single-line `passiveTextField`; clicking it should refocus into
            // duck.ai (restore panel + prompt + cursor), not make `addressBarTextField` first responder (which
            // would briefly transition to search-focused and flash). Intercept the click and short-circuit into
            // the refocus path. Hits on tool buttons / the toggle fall through above via `shouldShowArrowCursor`.
            if selectionState == .inactiveWithAIChat {
                refocusInAIChatMode()
                return nil
            }

            guard self.view.window?.firstResponder !== addressBarTextField.currentEditor()
            else { return event }

            // bookmark button visibility is usually determined by hover state, but we def need to hide it right now
            self.addressBarButtonsViewController?.bookmarkButton.isHidden = true

            // first activate app and window if needed, then make it first responder
            if self.view.window?.isMainWindow == true {
                self.addressBarTextField.makeMeFirstResponder()
                return nil
            } else {
                DispatchQueue.main.async {
                    self.addressBarTextField.makeMeFirstResponder()
                }
            }

        } else if window.isMainWindow {
            let locationInWindow = event.locationInWindow

            if selectionState.isInAIChatMode,
               let isPointInAIChatOmnibar = isPointInAIChatOmnibar,
               isPointInAIChatOmnibar(locationInWindow) {
                return event
            }

            self.clickPoint = window.convertPoint(toScreen: event.locationInWindow)
        }
        return event
    }

    func rightMouseDown(with event: NSEvent) -> NSEvent? {
        guard event.window === self.view.window else { return event }
        // Convert the point to view system
        let pointInView = view.convert(event.locationInWindow, from: nil)

        // If the view where the touch occurred is outside the AddressBar forward the event
        guard let viewWithinAddressBar = view.hitTest(pointInView) else { return event }

        // If we have an AddressBarMenuButton, forward the event
        guard !(viewWithinAddressBar is AddressBarMenuButton) else { return event }

        // If we have a CustomToggleControl, forward the event to let it handle its context menu
        guard !(viewWithinAddressBar is CustomToggleControl) else { return event }

        // If the farthest view of the point location is a NSButton or LottieAnimationView don't show contextual menu
        guard viewWithinAddressBar.shouldShowArrowCursor == false else { return nil }

        guard !selectionState.isInAIChatMode else { return event }

        if self.view.window?.firstResponder !== addressBarTextField.currentEditor() {
            self.addressBarButtonsViewController?.bookmarkButton.isHidden = true
            self.addressBarTextField.makeMeFirstResponder()
        }

        // The event location is not a button so we can forward the event to the textfield
        addressBarTextField.rightMouseDown(with: event)
        return nil
    }

    func mouseUp(with event: NSEvent) -> NSEvent? {
        guard let window = self.view.window, event.window === window else {
            return event
        }

        /// Handle AI chat mode - click outside: unfocus but keep duck.ai mode, prompt, and toggle segment for this tab.
        if selectionState == .activeWithAIChat,
           let clickPoint,
           clickPoint.distance(to: window.convertPoint(toScreen: event.locationInWindow)) <= Constants.maxClickReleaseDistanceToResignFirstResponder {
            resignFocusKeepingAIChatMode()
            return event
        }

        /// Handle toggle focused - click outside to deselect
        if window.firstResponder === addressBarButtonsViewController?.searchModeToggleControl,
           let clickPoint,
           clickPoint.distance(to: window.convertPoint(toScreen: event.locationInWindow)) <= Constants.maxClickReleaseDistanceToResignFirstResponder {
            self.view.window?.makeFirstResponder(nil)
            return event
        }

        /// Handle normal mode - click (same position down+up) outside of the field: resign first responder
        guard window.firstResponder === addressBarTextField.currentEditor(),
              let clickPoint,
              clickPoint.distance(to: window.convertPoint(toScreen: event.locationInWindow)) <= Constants.maxClickReleaseDistanceToResignFirstResponder else {
            return event
        }

        self.view.window?.makeFirstResponder(nil)

        return event
    }

}

extension AddressBarViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        refreshAddressBarAppearance(nil)
        refreshSuggestionsAppearance()
        updateView()
    }
}

private extension AddressBarViewController {

    func resizeAddressBarIfNeeded() {
        guard isViewLoaded, shouldUseTallAddressBarLayout != displaysTallLayout else {
            return
        }

        requestAddressBarResize(allowsAsync: false)
    }

    func requestAddressBarResize(allowsAsync: Bool = true) {
        displaysTallLayout = shouldUseTallAddressBarLayout
        delegate?.resizeAddressBarForHomePage(self, allowsAsync: allowsAsync)
    }
}

extension AddressBarViewController: AddressBarButtonsViewControllerDelegate {
    func addressBarButtonsViewControllerHideAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController) {
        aiChatSettings.showShortcutInAddressBar = false
    }

    func addressBarButtonsViewControllerHideAskAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController) {
        aiChatSettings.showShortcutInAddressBarWhenTyping = false
    }

    func addressBarButtonsViewControllerHideSearchModeToggleClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController) {
        aiChatSettings.showSearchAndDuckAIToggle = false
    }

    func addressBarButtonsViewControllerCancelButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController) {
        _ = escapeKeyDown()
    }

    func addressBarButtonsViewControllerOpenAIChatSettingsButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController) {
        tabCollectionViewModel.insertOrAppendNewTab(.settings(pane: .aiChat))
    }

    func addressBarButtonsViewControllerAIChatButtonClicked(_ addressBarButtonsViewController: AddressBarButtonsViewController) {
        addressBarTextField.hideSuggestionWindow()
        addressBarTextField.escapeKeyDown()
    }

    func addressBarButtonsViewControllerSearchModeToggleChanged(_ addressBarButtonsViewController: AddressBarButtonsViewController, isAIChatMode: Bool) {
        isAIChatOmnibarVisible = isAIChatMode
        sharedTextState?.setDuckAIMode(isAIChatMode)

        if isAIChatMode {
            /// Capture the address-bar field editor's caret before we transition — search-mode typing doesn't
            /// keep `sharedTextState.selectionRange` in sync, so without this the Duck.ai panel would restore
            /// the prompt cursor to `(0, 0)`. If there's no editor (address bar wasn't focused), leave the
            /// stored value alone and let `focusTextViewRestoringCursorPosition` fall back to end-of-text.
            if let editor = addressBarTextField.currentEditor() {
                sharedTextState?.updateSelection(editor.selectedRange)
            }
            selectionState = .activeWithAIChat
            mode = .editing(.aiChat)
            if isFirstResponder {
                view.window?.makeFirstResponder(nil)
            }
        } else {
            selectionState = .active

            updateMode()
            addressBarTextField.makeMeFirstResponder()
            /// Mirror of the capture in the `if isAIChatMode` branch: restore the selection that
            /// Duck.ai's `textViewDidChangeSelection` persisted, so toggling back doesn't drop the
            /// user's highlight. UTF-16 bounds check matches `focusTextViewRestoringCursorPosition`.
            if let saved = sharedTextState?.selectionRange,
               let editor = addressBarTextField.currentEditor() {
                let utf16Length = (editor.string as NSString).length
                if saved.location <= utf16Length {
                    let clampedLength = min(saved.length, max(0, utf16Length - saved.location))
                    editor.selectedRange = NSRange(location: saved.location, length: clampedLength)
                } else {
                    addressBarTextField.moveCursorToEnd()
                }
            } else {
                addressBarTextField.moveCursorToEnd()
            }

            /// Force layout update after becoming first responder to update in case the window was resized
            layoutTextFields(withMinX: addressBarButtonsViewController.buttonsWidth)

            addressBarTextField.refreshSuggestions()
        }
        sharedTextState?.resetUserInteractionAfterSwitchingModes()
        delegate?.addressBarViewControllerSearchModeToggleChanged(self, isAIChatMode: isAIChatMode)
    }

    func setAIChatOmnibarVisible(_ visible: Bool, shouldKeepSelection: Bool = false) {
        isAIChatOmnibarVisible = visible

        if visible {
            selectionState = .activeWithAIChat
            mode = .editing(.aiChat)
            sharedTextState?.setDuckAIMode(true)
            if isFirstResponder {
                view.window?.makeFirstResponder(nil)
            }
        } else {
            /// Note: we intentionally do NOT clear `sharedTextState?.setDuckAIMode(false)` here. On tab switch,
            /// this method runs with `self.tabViewModel` still pointing at the OUTGOING tab (AddressBarVC's own
            /// $selectedTabViewModel sink fires after MainVC's), so clearing would wipe the wrong tab's flag.
            /// Explicit exit paths (toggle to search, prompt submit, URL navigation, context-menu hide toggle)
            /// call `setDuckAIMode(false)` themselves. In-tab navigation clears via `sharedTextState.reset()`
            /// from `AddressBarTextField.updateValue`.
            if shouldKeepSelection {
                addressBarButtonsViewController?.resetSearchModeToggle()
            } else {
                selectionState = .inactive
                updateMode()
                /// `selectionState`'s didSet ran `updateView` with the stale `.editing(.aiChat)` mode set
                /// from when this tab was Duck.ai-active, which kept `addressBarTextField` visible (and
                /// left-aligned with the full URL) on the incoming search-mode URL tab until the user
                /// focused/unfocused the bar. Re-run the layout now that `updateMode` has flipped `mode`
                /// to its correct browsing/editing value so the active/passive text-field split converges.
                updateView()
                view.window?.makeFirstResponder(nil)
                addressBarButtonsViewController?.resetSearchModeToggle()
            }
        }

        resizeAddressBarIfNeeded()
    }

    /// Transitions from focused duck.ai mode (`.activeWithAIChat`) to unfocused duck.ai mode (`.inactiveWithAIChat`):
    /// resigns first responder, fully hides the Duck.ai panel, and lets the bar revert to its inactive single-line
    /// rendering (with `passiveTextField` showing the preserved prompt). The tab's `isInDuckAIMode` flag and the
    /// shared text state stay intact so clicking the bar or submitting from elsewhere resumes the draft.
    /// `isAIChatOmnibarVisible` flips to false so the buttons VC stops treating the panel as active; the toggle
    /// remains on the duck.ai segment via the tab's preserved mode flag.
    func resignFocusKeepingAIChatMode() {
        guard selectionState == .activeWithAIChat else { return }
        /// Force `addressBarTextField.value` to the duck.ai prompt (or empty for the placeholder) before the
        /// bar becomes visible. On a URL-loaded tab the underlying value is still the URL; without this push,
        /// unfocused duck.ai would render the URL + privacy shield + permission center.
        addressBarTextField.applyDuckAIUnfocusedValue()
        /// Flip `isAIChatOmnibarVisible` FIRST — `selectionState`'s didSet calls `updateView`, which reads
        /// `isAIChatOmnibarVisible` to decide whether the suggestions-variant background (the tall one merged
        /// with the Duck.ai panel) should stay visible. Setting visibility after the state change leaves that
        /// background up, making the unfocused bar look taller than `.inactive` with typed text.
        isAIChatOmnibarVisible = false
        selectionState = .inactiveWithAIChat
        updateMode()
        view.window?.makeFirstResponder(nil)
        requestAddressBarResize()
        delegate?.addressBarViewControllerDidResignFocusKeepingAIChatMode(self)
    }

    /// Whether a hit-test result points at one of the address bar's text fields (active or passive).
    /// Used by `mouseDown` in focused AI-chat mode to block clicks on the address bar while letting
    /// clicks on the AI chat text view through.
    private func isHitViewInsideAddressBarTextFields(_ hitView: NSView?) -> Bool {
        hitView === addressBarTextField
            || hitView?.isDescendant(of: addressBarTextField) == true
            || hitView === passiveTextField
            || hitView?.isDescendant(of: passiveTextField) == true
    }

    /// Transitions from unfocused duck.ai mode (`.inactiveWithAIChat`) back to focused duck.ai mode (`.activeWithAIChat`):
    /// re-shows the Duck.ai panel and returns focus to the prompt editor with the preserved draft / cursor position.
    func refocusInAIChatMode() {
        guard selectionState == .inactiveWithAIChat else { return }
        /// Flip `isAIChatOmnibarVisible` BEFORE `selectionState`. `selectionState`'s didSet calls
        /// `updateView`, which reads `isAIChatOmnibarVisible` to decide `activeBackgroundView.alphaValue`
        /// (`(selectionState.isSelected && !isAIChatOmnibarVisible) ? 1 : 0`). Doing it in the other order
        /// leaves the accent-bordered active background visible behind the Duck.ai panel until the next
        /// `updateView` run, because `isAIChatOmnibarVisible`'s didSet doesn't re-invoke `updateView`.
        /// The other entry paths into `.activeWithAIChat` (`setAIChatOmnibarVisible`,
        /// `addressBarButtonsViewControllerSearchModeToggleChanged`) already sequence it this way, and
        /// `resignFocusKeepingAIChatMode` has the symmetric comment on exit.
        isAIChatOmnibarVisible = true
        selectionState = .activeWithAIChat
        mode = .editing(.aiChat)

        // Important: Resizing the Address Bar must be synchronous. Otherwise we'll observe the Omnibar jumping onscreen
        requestAddressBarResize(allowsAsync: false)
        delegate?.addressBarViewControllerDidRefocusInAIChatMode(self)
    }
}

// MARK: - NSDraggingSource
extension AddressBarViewController: NSDraggingSource, NSPasteboardItemDataProvider {

    private func beginDraggingSessionIfNeeded(with event: NSEvent, in window: NSWindow) -> Bool {
        var isMouseDownOnPassiveTextField: Bool {
            tabViewModel?.tab.content.userEditableUrl != nil
            && passiveTextField.isVisible
            && passiveTextField.withMouseLocationInViewCoordinates(convert: {
                passiveTextField.bounds.insetBy(dx: -2, dy: -2).contains($0)
            }) == true
        }
        var isMouseDownOnActiveTextFieldFavicon: Bool {
            guard let addressBarButtonsViewController else { return false }
            return addressBarTextField.isFirstResponder
            && addressBarButtonsViewController.imageButtonWrapper.withMouseLocationInViewCoordinates(convert: {
                addressBarButtonsViewController.imageButtonWrapper.bounds.insetBy(dx: -2, dy: -2).contains($0)
            }) == true
        }
        var draggedView: NSView? {
            if isMouseDownOnPassiveTextField {
                passiveTextField
            } else if isMouseDownOnActiveTextFieldFavicon {
                addressBarButtonsViewController?.imageButtonWrapper
            } else {
                nil
            }
        }
        guard let draggedView else { return false }

        let initialLocation = event.locationInWindow
        while let nextEvent = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: Date.distantFuture, inMode: .default, dequeue: true) {
            // Let the superclass handle the event if it's not a drag
            guard nextEvent.type == .leftMouseDragged else {
                DispatchQueue.main.async { [weak window] in
                    guard let event = event.makeMouseUpEvent() else { return }
                    // post new event to unblock waiting for nextEvent
                    window?.postEvent(event, atStart: true)
                }
                break
            }
            // If the mouse hasn't moved significantly, don't start dragging
            guard nextEvent.locationInWindow.distance(to: initialLocation) > 3 else { continue }

            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setDataProvider(self, forTypes: [.string, .URL])

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            draggingItem.draggingFrame = passiveTextField.bounds

            draggedView.beginDraggingSession(with: [draggingItem], event: event, source: self)
            return true
        }
        return false
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let url = tabViewModel?.tab.content.userEditableUrl {
            pasteboard?.setString(url.absoluteString, forType: .string)
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        guard let url = tabViewModel?.tab.url else { return }

        // Set URL and title in pasteboard
        session.draggingPasteboard.setString(url.absoluteString, forType: .URL)
        if let title = tabViewModel?.title, !title.isEmpty {
            session.draggingPasteboard.setString(title, forType: .urlName)
        }

        // Create dragging image
        let favicon: NSImage
        if let tabFavicon = tabViewModel?.tab.favicon {
            favicon = tabFavicon
        } else {
            favicon = .web
        }

        session.draggingFormation = .none
        session.setPreviewProvider(URLDragPreviewProvider(url: url, favicon: favicon))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}

// MARK: - NSDraggingDestination
extension AddressBarViewController: NSDraggingDestination {

    func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(draggingInfo)
    }

    func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        // disable dropping url on the same address bar where it came from
        if draggingInfo.draggingSource as? Self === self {
            return .none
        }
        return .copy
    }

    func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        // navigate to dragged url (if available)
        if let url = draggingInfo.draggingPasteboard.url {
            tabCollectionViewModel.selectedTabViewModel?.tab.setUrl(url, source: .userEntered(draggingInfo.draggingPasteboard.string(forType: .string) ?? url.absoluteString))
            return true

        } else {
            // activate the address bar and replace its string value
            return addressBarTextField.performDragOperation(draggingInfo)
        }
    }
}

extension AddressBarViewController: AddressBarTextFieldFocusDelegate {
    func addressBarDidFocus(_ addressBarTextField: AddressBarTextField) {
        requestAddressBarResize()
        addressBarButtonsViewController?.setupButtonPaddings(isFocused: true)
    }

    func addressBarDidLoseFocus(_ addressBarTextField: AddressBarTextField) {
        requestAddressBarResize()
        addressBarButtonsViewController?.setupButtonPaddings(isFocused: false)

        // Restore internal text field labels when address bar loses focus
        if #available(macOS 26.0, *), featureFlagger.isFeatureOn(.blurryAddressBarTahoeFix) {
            restoreInternalTextFieldLabels(in: addressBarTextField)
        }
    }
}

fileprivate extension NSView {

    var shouldShowArrowCursor: Bool {
        self is NSButton || self is LottieAnimationView || self is CustomToggleControl
    }

}
