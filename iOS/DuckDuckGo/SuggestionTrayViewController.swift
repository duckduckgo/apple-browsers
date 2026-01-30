//
//  SuggestionTrayViewController.swift
//  DuckDuckGo
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

import UIKit
import Core
import Bookmarks
import Suggestions
import Persistence
import History
import BrowserServicesKit
import PrivacyConfig
import UIComponents
import AIChat

class SuggestionTrayViewController: UIViewController {
    
    @IBOutlet weak var backgroundView: CompositeShadowView!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet var variableWidthConstraint: NSLayoutConstraint!
    @IBOutlet var fullWidthConstraint: NSLayoutConstraint!
    @IBOutlet var topConstraint: NSLayoutConstraint!
    @IBOutlet var variableHeightConstraint: NSLayoutConstraint!
    @IBOutlet var fullHeightSafeAreaConstraint: NSLayoutConstraint!
    @IBOutlet var fullHeightConstraint: NSLayoutConstraint!

    weak var autocompleteDelegate: AutocompleteViewControllerDelegate?
    weak var newTabPageControllerDelegate: NewTabPageControllerDelegate?

    var dismissHandler: (() -> Void)?

    var isShowingAutocompleteSuggestions: Bool {
        autocompleteController != nil
    }

    var isShowingFavorites: Bool {
        newTabPage != nil
    }

    var isShowing: Bool {
        isShowingAutocompleteSuggestions || isShowingFavorites
    }

    private var autocompleteController: AutocompleteViewController?
    private var newTabPage: NewTabPageViewController?
    private var willRemoveAutocomplete = false
    private let bookmarksDatabase: CoreDataDatabase
    private let favoritesModel: FavoritesListInteracting
    private let historyManager: HistoryManaging
    private let tabsModel: TabsModel
    private let featureFlagger: FeatureFlagger
    private let appSettings: AppSettings
    private let aiChatSettings: AIChatSettingsProvider
    private let featureDiscovery: FeatureDiscovery
    private let hideBorder: Bool

    var coversFullScreen: Bool = false

    var selectedSuggestion: Suggestion? {
        autocompleteController?.selectedSuggestion
    }
    
    enum SuggestionType: Equatable {
    
        case autocomplete(query: String)
        case favorites
        
        func hideOmnibarSeparator() -> Bool {
            switch self {
            case .autocomplete: return true
            case .favorites: return false
            }
        }
        
        static func == (lhs: SuggestionTrayViewController.SuggestionType, rhs: SuggestionTrayViewController.SuggestionType) -> Bool {
            switch (lhs, rhs) {
            case let (.autocomplete(queryLHS), .autocomplete(queryRHS)):
                return queryLHS == queryRHS
            case (.favorites, .favorites):
                return true
            default:
                return false
            }
        }
    }

    let newTabPageDependencies: NewTabPageDependencies

    struct NewTabPageDependencies {
        let favoritesModel: FavoritesListInteracting
        let homePageMessagesConfiguration: HomePageMessagesConfiguration
        let subscriptionDataReporting: SubscriptionDataReporting?
        let newTabDialogFactory: NewTabDaxDialogsProvider
        let newTabDaxDialogManager: NewTabDialogSpecProvider & SubscriptionPromotionCoordinating
        let faviconLoader: FavoritesFaviconLoading
        let remoteMessagingActionHandler: RemoteMessagingActionHandling
        let appSettings: AppSettings
        let internalUserCommands: URLBasedDebugCommands
    }

    let productSurfaceTelemetry: ProductSurfaceTelemetry

    required init?(coder: NSCoder,
                   favoritesViewModel: FavoritesListInteracting,
                   bookmarksDatabase: CoreDataDatabase,
                   historyManager: HistoryManaging,
                   tabsModel: TabsModel,
                   featureFlagger: FeatureFlagger,
                   appSettings: AppSettings,
                   aiChatSettings: AIChatSettingsProvider,
                   featureDiscovery: FeatureDiscovery,
                   newTabPageDependencies: NewTabPageDependencies,
                   productSurfaceTelemetry: ProductSurfaceTelemetry,
                   hideBorder: Bool) {
        self.favoritesModel = favoritesViewModel
        self.bookmarksDatabase = bookmarksDatabase
        self.historyManager = historyManager
        self.tabsModel = tabsModel
        self.featureFlagger = featureFlagger
        self.appSettings = appSettings
        self.aiChatSettings = aiChatSettings
        self.newTabPageDependencies = newTabPageDependencies
        self.featureDiscovery = featureDiscovery
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.hideBorder = hideBorder
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installDismissHandler()
    }

    @IBAction func onDismiss() {
        dismissHandler?()
    }
    
    override var canBecomeFirstResponder: Bool { return true }
    
    func canShow(for type: SuggestionType, animated: Bool = true) -> Bool {
        var canShow = false
        switch type {
        case .autocomplete(let query):
            canShow = canDisplayAutocompleteSuggestions(forQuery: query, animated: animated)
        case.favorites:
            canShow = canDisplayFavorites
        }
        return canShow
    }

    func show(for type: SuggestionType, animated: Bool = true) {
        self.fullHeightSafeAreaConstraint.constant = appSettings.currentAddressBarPosition == .bottom ? 50 : 0

        switch type {
        case .autocomplete(let query):
            displayAutocompleteSuggestions(forQuery: query, animated: animated)
        case .favorites:
            if isPad {
                removeAutocomplete(animated: animated)
                displayFavoritesIfNeeded(animated: animated)
            } else {
                willRemoveAutocomplete = true
                displayFavoritesIfNeeded(animated: animated) { [weak self] in
                    self?.removeAutocomplete(animated: animated)
                    self?.willRemoveAutocomplete = false
                }
            }
        }
    }
        
    var contentFrame: CGRect {
        return containerView.frame
    }

    func didHide(animated: Bool) {
        removeAutocomplete(animated: animated)
        removeNewTabPage(animated: animated)
    }
    
    @objc func keyboardMoveSelectionDown() {
        autocompleteController?.keyboardMoveSelectionDown()
    }

    @objc func keyboardMoveSelectionUp() {
        autocompleteController?.keyboardMoveSelectionUp()
    }
    
    func float(withWidth width: CGFloat) {

        containerView.layer.cornerRadius = 24
        containerView.layer.masksToBounds = true
 
        backgroundView.layer.cornerRadius = 24
        backgroundView.backgroundColor = UIColor(designSystemColor: .background)
        backgroundView.clipsToBounds = false
        backgroundView.applyActiveShadow()

        topConstraint.constant = 4

        let isFirstPresentation = fullHeightConstraint.isActive
        if isFirstPresentation {
            variableHeightConstraint.constant = Constant.suggestionTrayInitialHeight
        }

        variableWidthConstraint.constant = width
        fullWidthConstraint.isActive = false
        fullHeightConstraint.isActive = false
        fullHeightSafeAreaConstraint.isActive = false
    }
    
    func fill(bottomOffset: CGFloat = 0.0) {
        additionalSafeAreaInsets = .init(top: 0, left: 0, bottom: bottomOffset, right: 0)

        containerView.layer.shadowColor = UIColor.clear.cgColor
        containerView.layer.cornerRadius = 0

        containerView.subviews.first?.layer.masksToBounds = false
        containerView.subviews.first?.layer.cornerRadius = 0
        backgroundView.layer.masksToBounds = false
        backgroundView.layer.cornerRadius = 0
        backgroundView.backgroundColor = UIColor.clear

        topConstraint.constant = 0
        fullWidthConstraint.isActive = true
        fullHeightConstraint.isActive = coversFullScreen
        fullHeightSafeAreaConstraint.isActive = !coversFullScreen
    }
    
    private func installDismissHandler() {
        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(onDismiss))
        backgroundTap.cancelsTouchesInView = false
        
        let foregroundTap = UITapGestureRecognizer()
        foregroundTap.cancelsTouchesInView = false
        
        backgroundTap.require(toFail: foregroundTap)
        
        view.addGestureRecognizer(backgroundTap)
        containerView.addGestureRecognizer(foregroundTap)
    }
    
    private var canDisplayFavorites: Bool {
        favoritesModel.favorites.count > 0
    }

    var hasRemoteMessages: Bool {
        return !newTabPageDependencies.homePageMessagesConfiguration.homeMessages.isEmpty
    }

    private func displayFavoritesIfNeeded(animated: Bool, onInstall: @escaping () -> Void = {}) {
        if newTabPage == nil {
            installNewTabPage(animated: animated, onInstall: onInstall)
        } else {
            onInstall()
        }
    }

    private func installNewTabPage(animated: Bool, onInstall: @escaping () -> Void = {}) {
        let dependencies = newTabPageDependencies
        let controller = NewTabPageViewController(
            isFocussedState: true,
            dismissKeyboardOnScroll: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
            tab: Tab(),
            interactionModel: dependencies.favoritesModel,
            homePageMessagesConfiguration: dependencies.homePageMessagesConfiguration,
            subscriptionDataReporting: dependencies.subscriptionDataReporting,
            newTabDialogFactory: dependencies.newTabDialogFactory,
            daxDialogsManager: dependencies.newTabDaxDialogManager,
            faviconLoader: dependencies.faviconLoader,
            remoteMessagingActionHandler: dependencies.remoteMessagingActionHandler,
            appSettings: dependencies.appSettings,
            internalUserCommands: dependencies.internalUserCommands
        )

        controller.delegate = newTabPageControllerDelegate
        if hideBorder {
            controller.hideBorderView()
        }

        install(controller: controller,
                animated: animated,
                completion: onInstall)
        newTabPage = controller
    }
    
    private func canDisplayAutocompleteSuggestions(forQuery query: String, animated: Bool) -> Bool {
        let canDisplay = appSettings.autocomplete && !query.isEmpty
        if !canDisplay {
            removeAutocomplete(animated: animated)
        }
        return canDisplay
    }
    
    private func displayAutocompleteSuggestions(forQuery query: String, animated: Bool) {
        if autocompleteController == nil {
            installAutocompleteSuggestions(animated: animated)
        }
        autocompleteController?.updateQuery(query)
    }
    
    private func installAutocompleteSuggestions(animated: Bool) {
        let controller = AutocompleteViewController(historyManager: historyManager,
                                                    bookmarksDatabase: bookmarksDatabase,
                                                    appSettings: appSettings,
                                                    tabsModel: tabsModel,
                                                    featureFlagger: featureFlagger,
                                                    aiChatSettings: aiChatSettings,
                                                    featureDiscovery: featureDiscovery,
                                                    productSurfaceTelemetry: productSurfaceTelemetry)
        install(controller: controller, animated: animated)
        controller.delegate = autocompleteDelegate
        controller.presentationDelegate = self
        autocompleteController = controller
    }

    private func removeAutocomplete(animated: Bool) {
        guard let controller = autocompleteController else { return }
        removeController(controller, animated: animated)
        autocompleteController = nil
    }

    private func removeNewTabPage(animated: Bool) {
        guard let controller = newTabPage else { return }
        removeController(controller, animated: animated)
        newTabPage = nil
    }

    private func removeController(_ controller: UIViewController, animated: Bool) {
        controller.willMove(toParent: nil)

        let finalize = {
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }

        if animated {
            UIView.animate(withDuration: 0.2) {
                controller.view.alpha = 0.0
            } completion: { _ in
                finalize()
            }
        } else {
            finalize()
        }
    }

    private func install(controller: UIViewController,
                         animated: Bool,
                         additionalInsets: UIEdgeInsets = .zero,
                         completion: @escaping () -> Void = {}) {
        addChild(controller)
        controller.view.frame = containerView.bounds
        containerView.addSubview(controller.view)

        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: -additionalInsets.top),
            containerView.leftAnchor.constraint(equalTo: controller.view.leftAnchor, constant: -additionalInsets.left),
            containerView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: additionalInsets.bottom),
            containerView.rightAnchor.constraint(equalTo: controller.view.rightAnchor, constant: additionalInsets.right)
        ])

        if animated {
            controller.view.alpha = 0
            UIView.animate(withDuration: 0.2, animations: {
                controller.view.alpha = 1
            }, completion: { _ in
                controller.didMove(toParent: self)
                completion()
            })
        } else {
            controller.view.alpha = 1
            controller.didMove(toParent: self)
            completion()
        }
    }

}

extension SuggestionTrayViewController: AutocompleteViewControllerPresentationDelegate {
    
    func autocompleteDidChangeContentHeight(height: CGFloat) {
        guard !fullHeightConstraint.isActive else { return }
        
        if height > Constant.suggestionTrayInitialHeight {
            variableHeightConstraint.constant = height
        }
    }
    
}

extension SuggestionTrayViewController {
    
    // Only gets called if system theme changes while tray is open
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        // only update the color if one has been set
        if backgroundView.backgroundColor != nil {
            backgroundView.backgroundColor = theme.tableCellBackgroundColor
        }
    }
    
}

private extension SuggestionTrayViewController {
    enum Constant {
        static let suggestionTrayInitialHeight = 380.0
    }
}
