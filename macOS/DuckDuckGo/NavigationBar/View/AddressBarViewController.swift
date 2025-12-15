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

import BrowserServicesKit
import Cocoa
import Combine
import Lottie
import Common
import AIChat
import UIComponents
import PixelKit

protocol AddressBarViewControllerDelegate: AnyObject {
    func resizeAddressBarForHomePage(_ addressBarViewController: AddressBarViewController)
    func addressBarViewControllerSearchModeToggleChanged(_ addressBarViewController: AddressBarViewController, isAIChatMode: Bool)
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

        var isSelected: Bool {
            self != .inactive
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
    @IBOutlet var activeOuterBorderView: ColorView!
    @IBOutlet var activeBackgroundViewWithSuggestions: ColorView!
    @IBOutlet var innerBorderView: ColorView!
    @IBOutlet var progressIndicator: LoadingProgressView!
    @IBOutlet var buttonsContainerView: NSView!
    @IBOutlet var switchToTabBox: ColorView!
    @IBOutlet var switchToTabLabel: NSTextField!
    @IBOutlet var shadowView: ShadowView!

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
    private let aiChatSidebarPresenter: AIChatSidebarPresenting
    private let searchPreferences: SearchPreferences
    private let tabsPreferences: TabsPreferences
    private let accessibilityPreferences: AccessibilityPreferences
    private let featureFlagger: FeatureFlagger

    private var aiChatSettings: AIChatPreferencesStorage

    /// Gets the shared text state from the current tab's view model
    private var sharedTextState: AddressBarSharedTextState? {
        tabViewModel?.addressBarSharedTextState ?? AddressBarSharedTextState()
    }

    @IBOutlet weak var activeOuterBorderTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var activeOuterBorderLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var activeOuterBorderBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var activeOuterBorderTopConstraint: NSLayoutConstraint!

    private var mode: Mode = .editing(.text) {
        didSet {
            addressBarButtonsViewController?.controllerMode = mode
        }
    }

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private(set) var selectionState: SelectionState = .inactive {
        didSet {
            updateView()
            updateSwitchToTabBoxAppearance()
            self.addressBarButtonsViewController?.isTextFieldEditorFirstResponder = selectionState.isSelected
            if selectionState == .inactive {
                self.clickPoint = nil // reset click point if the address bar activated during click
            }
        }
    }

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
            if isSelected {
                updateShadowView(addressBarTextField.isSuggestionWindowVisible || isAIChatOmnibarVisible)
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
          aiChatSidebarPresenter: AIChatSidebarPresenting,
          featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
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
        self.aiChatSidebarPresenter = aiChatSidebarPresenter
        self.featureFlagger = featureFlagger

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
                                                         aiChatSidebarPresenter: aiChatSidebarPresenter,
                                                         aiChatSettings: aiChatSettings)

        self.addressBarButtonsViewController = controller
        controller?.delegate = self
        return addressBarButtonsViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.masksToBounds = false

        setupAddressBarPlaceHolder()
        addressBarTextField.setAccessibilityIdentifier("AddressBarViewController.addressBarTextField")

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

        addressBarTextField.aiChatTogglePopoverCoordinator = addressBarButtonsViewController?.aiChatTogglePopoverCoordinator
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

        // hide Suggestions when child window is shown (Suggestions, Bookmarks, Downloads etc…, excluding Tab Previews and Suggestions)
        window.publisher(for: \.childWindows)
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] childWindows in
                guard let self, let childWindows, childWindows.contains(where: {
                    !(
                        $0.windowController is TabPreviewWindowController
                        || $0.contentViewController is SuggestionViewController
                        || $0 === self.view.window?.titlebarView?.window // fullscreen titlebar owning window
                    )
                }) else { return }

                addressBarTextField.hideSuggestionWindow()
            }
            .store(in: &cancellables) // hide Suggestions on Minimuze/Enter Full Screen

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] _ in
                self?.refreshAddressBarAppearance(nil)
            }
            .store(in: &cancellables)
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

                self.tabViewModel = tabViewModel
                tabViewModelCancellables.removeAll()

                // Update the text field's shared text state for the new tab
                addressBarTextField.sharedTextState = sharedTextState

                subscribeToTabContent()
                subscribeToProgressEventsIfNeeded()

                // don't resign first responder on tab switching
                clickPoint = nil

                if selectionState == .activeWithAIChat {
                    delegate?.addressBarViewControllerSearchModeToggleChanged(self, isAIChatMode: false)
                    setAIChatOmnibarVisible(false)
                }
            }
            .store(in: &cancellables)
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
    }

    private let displaysTabsProgressIndicator: Bool = NSApp.delegateTyped.displaysTabsProgressIndicator == false

    private func subscribeToProgressEventsIfNeeded() {
        guard let tabViewModel, displaysTabsProgressIndicator else {
            progressIndicator.hide(animated: false)
            return
        }

        func shouldShowLoadingIndicator(for tabViewModel: TabViewModel, isLoading: Bool, error: Error?) -> Bool {
            if isLoading,
               let url = tabViewModel.tab.content.urlForWebView,
               url.navigationalScheme?.isHypertextScheme == true,
               !url.isDuckDuckGoSearch, !url.isDuckPlayer,
               error == nil {
                return true
            } else {
                return false
            }
        }

        if shouldShowLoadingIndicator(for: tabViewModel, isLoading: tabViewModel.isLoading, error: tabViewModel.tab.error) {
            progressIndicator.show(progress: tabViewModel.progress, startTime: tabViewModel.loadingStartTime)
        } else {
            progressIndicator.hide(animated: false)
        }

        tabViewModel.$progress
            .sink { [weak self] value in
                guard tabViewModel.isLoading,
                      let progressIndicator = self?.progressIndicator,
                      progressIndicator.isProgressShown
                else { return }

                progressIndicator.increaseProgress(to: value)
            }
            .store(in: &tabViewModelCancellables)

        tabViewModel.$isLoading.combineLatest(tabViewModel.tab.$error)
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [weak self] isLoading, error in
                guard let progressIndicator = self?.progressIndicator else { return }

                if shouldShowLoadingIndicator(for: tabViewModel, isLoading: isLoading, error: error) {
                    progressIndicator.show(progress: tabViewModel.progress, startTime: tabViewModel.loadingStartTime)

                } else if progressIndicator.isProgressShown {
                    progressIndicator.finishAndHide()
                }
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
                self.updateShadowView(isSuggestionsWindowVisible || self.isAIChatOmnibarVisible)
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
        if selectionState == .activeWithAIChat {
            addressBarTextField.isHidden = true
            passiveTextField.isHidden = true
        } else {
            let isPassiveTextFieldHidden = selectionState.isSelected || mode.isEditing
            addressBarTextField.isHidden = isPassiveTextFieldHidden ? false : true
            passiveTextField.isHidden = isPassiveTextFieldHidden ? true : false
        }
        passiveTextField.textColor = theme.colorsProvider.textPrimaryColor

        // Workaround for macOS 26.0 NSTextFieldSimpleLabel rendering bug
        if #available(macOS 26.0, *), featureFlagger.isFeatureOn(.blurryAddressBarTahoeFix) {
            if addressBarTextField.isHidden {
                forceHideInternalTextFieldLabels(in: addressBarTextField)
            }
        }

        updateShadowViewPresence(selectionState.isSelected)
        inactiveBackgroundView.backgroundColor = theme.colorsProvider.inactiveAddressBarBackgroundColor
        inactiveBackgroundView.alphaValue = selectionState.isSelected ? 0 : 1
        activeBackgroundView.alphaValue = selectionState.isSelected ? 1 : 0

        let isKey = self.view.window?.isKeyWindow == true
        let isToggleFocused = view.window?.firstResponder === addressBarButtonsViewController?.searchModeToggleControl

        activeOuterBorderView.alphaValue = isKey && selectionState.isSelected && !isToggleFocused && theme.addressBarStyleProvider.shouldShowOutlineBorder(isHomePage: isHomePage) ? 1 : 0
        activeOuterBorderView.backgroundColor = isBurner ? NSColor.burnerAccent.withAlphaComponent(0.2) : theme.colorsProvider.addressBarOutlineShadow

        if isToggleFocused {
            activeBackgroundView.borderWidth = 1.0
            activeBackgroundView.borderColor = .addressBarBorder
        } else {
            activeBackgroundView.borderWidth = 2.0
            activeBackgroundView.borderColor = isBurner ? NSColor.burnerAccent.withAlphaComponent(0.8) : theme.colorsProvider.accentPrimaryColor
        }

        setupAddressBarPlaceHolder()
        setupAddressBarCornerRadius()
        inactiveAddressBarShadowView.isHidden = selectionState.isSelected
    }

    private func setupAddressBarCornerRadius() {
        activeBackgroundView.setCornerRadius(theme.addressBarStyleProvider.addressBarActiveBackgroundViewRadius)
        inactiveBackgroundView.setCornerRadius(theme.addressBarStyleProvider.addressBarInactiveBackgroundViewRadius)
        innerBorderView.setCornerRadius(theme.addressBarStyleProvider.addressBarInnerBorderViewRadius)
        activeOuterBorderView.setCornerRadius(theme.addressBarStyleProvider.addressBarActiveOuterBorderViewRadius)
        activeBackgroundViewWithSuggestions.setCornerRadius(theme.addressBarStyleProvider.addressBarActiveBackgroundViewRadius)
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

    private func setupAddressBarPlaceHolder() {
        let isNewTab = tabViewModel?.tab.content == .newtab
        let addressBarPlaceholder: String

        if isNewTab {
            addressBarPlaceholder = UserText.addressBarPlaceholder
        } else {
            addressBarPlaceholder = ""
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
            updateShadowView(addressBarTextField.isSuggestionWindowVisible || isAIChatOmnibarVisible)
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

    private func updateShadowView(_ isSuggestionsWindowVisible: Bool) {
        shadowView.shadowSides = isSuggestionsWindowVisible ? [.left, .top, .right] : []
        shadowView.shadowColor = isSuggestionsWindowVisible ? .suggestionsShadow : .clear
        shadowView.shadowRadius = isSuggestionsWindowVisible ? theme.addressBarStyleProvider.suggestionShadowRadius : 0.0
        shadowView.cornerRadius = theme.addressBarStyleProvider.addressBarActiveBackgroundViewRadius

        let isToggleFocused = view.window?.firstResponder === addressBarButtonsViewController?.searchModeToggleControl
        activeOuterBorderView.isHidden = isSuggestionsWindowVisible || view.window?.isKeyWindow != true || isToggleFocused
        activeBackgroundView.isHidden = isSuggestionsWindowVisible
        activeBackgroundViewWithSuggestions.isHidden = !isSuggestionsWindowVisible
        inactiveAddressBarShadowView.isHidden = isSuggestionsWindowVisible
    }

    private func layoutShadowView() {
        guard let superview = shadowView.superview else { return }

        let winFrame = self.view.convert(self.view.bounds, to: nil)
        var frame = superview.convert(winFrame, from: nil)

        /// Extend shadow upward when AI Chat omnibar toggle is enabled to vertically align the toggle
        if featureFlagger.isFeatureOn(.aiChatOmnibarToggle) {
            let offset = AddressBarTextField.SuggestionWindowSizes.aiChatToggleVerticalOffset
            frame.origin.y += offset
            frame.size.height -= offset
        }

        shadowView.frame = frame
    }

    private func updateMode(value: AddressBarTextField.Value? = nil) {
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

        guard let window = view.window, window.sheets.isEmpty else {
            // Hide suggestions when a Sheet is presented (Open panel, Fire dialog…)
            addressBarTextField.hideSuggestionWindow()
            return
        }
        guard AppVersion.runType != .unitTests else { return }
        let navigationBarBackgroundColor = theme.colorsProvider.navigationBackgroundColor

        NSAppearance.withAppAppearance {
            // Keep selected appearance when AI chat is active, even if window loses key status
            let shouldShowActiveState = window.isKeyWindow || selectionState == .activeWithAIChat
            let isToggleFocused = window.firstResponder === addressBarButtonsViewController?.searchModeToggleControl

            if shouldShowActiveState {
                if isToggleFocused {
                    activeBackgroundView.borderWidth = 1.0
                    activeBackgroundView.borderColor = .addressBarBorder
                } else {
                    activeBackgroundView.borderWidth = 2.0
                    activeBackgroundView.borderColor = isBurner ? NSColor.burnerAccent.withAlphaComponent(0.8) : theme.colorsProvider.accentPrimaryColor
                }
                activeBackgroundView.backgroundColor = theme.colorsProvider.activeAddressBarBackgroundColor
                addressBarButtonsViewController?.trailingButtonsBackground.backgroundColor = theme.colorsProvider.activeAddressBarBackgroundColor
                switchToTabBox.backgroundColor = navigationBarBackgroundColor.blended(with: .addressBarBackground)

                activeOuterBorderView.isHidden = isToggleFocused || !theme.addressBarStyleProvider.shouldShowOutlineBorder(isHomePage: isHomePage) || selectionState == .activeWithAIChat
                activeOuterBorderView.backgroundColor = isBurner ? NSColor.burnerAccent.withAlphaComponent(0.2) : theme.colorsProvider.addressBarOutlineShadow
            } else {
                activeBackgroundView.borderWidth = 0
                activeBackgroundView.borderColor = nil
                activeBackgroundView.backgroundColor = theme.colorsProvider.inactiveAddressBarBackgroundColor
                addressBarButtonsViewController?.trailingButtonsBackground.backgroundColor = theme.colorsProvider.inactiveAddressBarBackgroundColor
                switchToTabBox.backgroundColor = navigationBarBackgroundColor.blended(with: .inactiveSearchBarBackground)

                activeOuterBorderView.isHidden = true
            }
        }
    }

    private func refreshSuggestionsAppearance() {
        activeBackgroundViewWithSuggestions.backgroundColor = theme.colorsProvider.suggestionsBackgroundColor
    }

    private func layoutTextFields(withMinX minX: CGFloat) {
        self.passiveTextFieldMinXConstraint.constant = minX
        // adjust min-x to passive text field when "Search or enter" placeholder is displayed (to prevent placeholder overlapping buttons)

        let isAddressBarFocused = view.window?.firstResponder == addressBarTextField.currentEditor()
        let adjustedMinX: CGFloat = (!self.isSelected || self.mode.isEditing) ? minX : Constants.defaultActiveTextFieldMinX

        let isOmnibarToggleFeatureEnabled = isAddressBarFocused && featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && aiChatSettings.isAIFeaturesEnabled
        let isToggleVisible = isOmnibarToggleFeatureEnabled && aiChatSettings.showSearchAndDuckAIToggle
        let textMargin: CGFloat = 20

        if theme.addressBarStyleProvider.shouldShowNewSearchIcon {
            if isAddressBarFocused {
                self.activeTextFieldMinXConstraint.constant = isToggleVisible ? textMargin : adjustedMinX - 5
            } else {
                self.activeTextFieldMinXConstraint.constant = adjustedMinX - 6
            }
        } else {
            self.activeTextFieldMinXConstraint.constant = isToggleVisible ? textMargin : adjustedMinX
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

            // Restore internal text field labels when address bar loses focus
            if #available(macOS 26.0, *), featureFlagger.isFeatureOn(.blurryAddressBarTahoeFix) {
                restoreInternalTextFieldLabels(in: addressBarTextField)
            }

            updateView()
            refreshAddressBarAppearance(nil)

            delegate?.resizeAddressBarForHomePage(self)
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
            break
        }

        setupAddressBarPlaceHolder()
    }

    private func fireAddressBarActivatedPixelIfNeeded() {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarToggle),
              aiChatSettings.isAIFeaturesEnabled else {
            return
        }

        let isToggleSettingOn = aiChatSettings.showSearchAndDuckAIToggle
        let pixel: AIChatPixel = isToggleSettingOn ? .aiChatAddressBarActivatedToggleOn : .aiChatAddressBarActivatedToggleOff
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    // MARK: - Event handling

    func escapeKeyDown() -> Bool {
        guard selectionState.isSelected else { return false }

        if selectionState == .activeWithAIChat {
            delegate?.addressBarViewControllerSearchModeToggleChanged(self, isAIChatMode: false)
            setAIChatOmnibarVisible(false)
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

        if beginDraggingSessionIfNeeded(with: event, in: window) {
            return nil
        }

        if let point = self.view.mouseLocationInsideBounds(event.locationInWindow) {
            let hitView = self.view.hitTest(point)

            if hitView?.shouldShowArrowCursor == true {
                return event
            }

            // In AI chat mode, only block clicks specifically on the address bar text fields
            // Allow clicks elsewhere (like on the AI chat text view)
            if selectionState == .activeWithAIChat {
                let isClickOnAddressBarTextField = hitView === addressBarTextField ||
                hitView?.isDescendant(of: addressBarTextField) == true ||
                hitView === passiveTextField ||
                hitView?.isDescendant(of: passiveTextField) == true
                if isClickOnAddressBarTextField {
                    return nil
                }
                return event
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

            if selectionState == .activeWithAIChat,
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

        guard selectionState != .activeWithAIChat else { return event }

        // The event location is not a button so we can forward the event to the textfield
        addressBarTextField.rightMouseDown(with: event)
        return nil
    }

    func mouseUp(with event: NSEvent) -> NSEvent? {
        guard let window = self.view.window, event.window === window else {
            return event
        }

        /// Handle AI chat mode - click outside to dismiss
        if selectionState == .activeWithAIChat,
           let clickPoint,
           clickPoint.distance(to: window.convertPoint(toScreen: event.locationInWindow)) <= Constants.maxClickReleaseDistanceToResignFirstResponder {
            delegate?.addressBarViewControllerSearchModeToggleChanged(self, isAIChatMode: false)
            setAIChatOmnibarVisible(false)
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

        if isAIChatMode {
            selectionState = .activeWithAIChat
            mode = .editing(.aiChat)
            if isFirstResponder {
                view.window?.makeFirstResponder(nil)
            }
        } else {
            selectionState = .active

            updateMode()
            addressBarTextField.makeMeFirstResponder()
            addressBarTextField.moveCursorToEnd()

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
            if isFirstResponder {
                view.window?.makeFirstResponder(nil)
            }
        } else {
            if shouldKeepSelection {
                addressBarButtonsViewController?.resetSearchModeToggle()
            } else {
                selectionState = .inactive
                updateMode()
                view.window?.makeFirstResponder(nil)
                addressBarButtonsViewController?.resetSearchModeToggle()
            }
        }
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
        delegate?.resizeAddressBarForHomePage(self)
        addressBarButtonsViewController?.setupButtonPaddings(isFocused: true)
    }

    func addressBarDidLoseFocus(_ addressBarTextField: AddressBarTextField) {
        delegate?.resizeAddressBarForHomePage(self)
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
