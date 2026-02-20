//
//  FireCoordinator.swift
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

import BrowserServicesKit
import Cocoa
import Combine
import Common
import History
import HistoryView
import Persistence
import PixelKit
import PrivacyConfig
import AIChat

// MARK: - Fire Dialog Presentation Abstractions (for testability)

protocol FireDialogViewPresenting {
    @MainActor
    func present(in window: NSWindow, completion: (() -> Void)?)
}

struct FireDialogViewConfig {
    let viewModel: FireDialogViewModel
    let showIndividualSitesLink: Bool
    let onConfirm: (FireDialogView.Response) -> Void
}

typealias FireDialogViewFactory = (_ config: FireDialogViewConfig) -> FireDialogViewPresenting

private struct DefaultFireDialogPresenter: FireDialogViewPresenting {
    let view: any ModalView
    @MainActor
    func present(in window: NSWindow, completion: (() -> Void)?) {
        view.show(in: window, completion: completion)
    }
}

@MainActor
final class FireCoordinator {

    /// This is a lazy var in order to avoid initializing Fire directly at AppDelegate.init
    /// because of a significant number of dependencies that are still singletons.
    private(set) lazy var fireViewModel: FireViewModel = FireViewModel(tld: tld, visualizeFireAnimationDecider: visualizeFireAnimationDecider)
    private(set) var firePopover: FirePopover?
    private let tld: TLD
    private let featureFlagger: FeatureFlagger
    let historyProvider: HistoryViewDataProviding
    private let historyCoordinating: (HistoryCoordinating & HistoryDataSource)
    private let fireDialogViewFactory: FireDialogViewFactory
    private let fireproofDomains: FireproofDomains
    private let faviconManagement: FaviconManagement
    private let onboardingContextualDialogsManager: (() -> ContextualOnboardingStateUpdater)?
    private let windowControllersManager: WindowControllersManagerProtocol
    private let tabViewModelGetter: (NSWindow) -> TabCollectionViewModel?
    private let pixelFiring: PixelFiring?
    private let aiChatSyncCleaner: (() -> AIChatSyncCleaning?)?
    private let visualizeFireAnimationDecider: OverridableVisualizeFireSettingsDecider
    let dataClearingPixelsReporter: DataClearingPixelsReporter

    init(tld: TLD,
         featureFlagger: FeatureFlagger,
         historyCoordinating: (HistoryCoordinating & HistoryDataSource),
         visualizeFireAnimationDecider: VisualizeFireSettingsDecider?,
         onboardingContextualDialogsManager: (() -> ContextualOnboardingStateUpdater)?,
         fireproofDomains: FireproofDomains,
         faviconManagement: FaviconManagement,
         windowControllersManager: WindowControllersManagerProtocol,
         pixelFiring: PixelFiring?,
         aiChatSyncCleaner: (() -> AIChatSyncCleaning?)? = nil,
         historyProvider: HistoryViewDataProviding? = nil, // for testing: created if not provided
         fireViewModel: FireViewModel? = nil, // for testing: created if not provided
         tabViewModelGetter: ((NSWindow) -> TabCollectionViewModel?)? = nil, // for testing: created if not provided
         fireDialogViewFactory: FireDialogViewFactory? = nil, // for testing: created if not provided
    ) {

        self.tld = tld
        self.featureFlagger = featureFlagger
        self.historyCoordinating = historyCoordinating
        self.fireproofDomains = fireproofDomains
        self.faviconManagement = faviconManagement
        self.onboardingContextualDialogsManager = onboardingContextualDialogsManager
        self.windowControllersManager = windowControllersManager
        self.tabViewModelGetter = tabViewModelGetter ?? { window in
            (window.contentViewController as? MainViewController)?.tabCollectionViewModel
        }
        self.pixelFiring = pixelFiring
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.dataClearingPixelsReporter = .init(pixelFiring: self.pixelFiring)
        self.visualizeFireAnimationDecider = OverridableVisualizeFireSettingsDecider(internalDecider: visualizeFireAnimationDecider)

        self.fireDialogViewFactory = fireDialogViewFactory ?? { config in
            let view = FireDialogView(
                viewModel: config.viewModel,
                showIndividualSitesLink: config.showIndividualSitesLink,
                onConfirm: config.onConfirm
            )
            return DefaultFireDialogPresenter(view: view)
        }
        var fireCoordinatorGetter: (() -> FireCoordinator)!
        let historyBurner = FireHistoryBurner(fireproofDomains: self.fireproofDomains,
                                              fire: { fireCoordinatorGetter().fireViewModel.fire },
                                              recordAIChatHistoryClearForSync: { Task { await aiChatSyncCleaner?()?.recordLocalClear(date: Date()) } })
        self.historyProvider = historyProvider ?? HistoryViewDataProvider(historyDataSource: self.historyCoordinating, historyBurner: historyBurner, tld: tld)
        if let fireViewModel {
            self.fireViewModel = fireViewModel
        }
        fireCoordinatorGetter = { [unowned self] in self }
    }

    func fireButtonAction() {
        // Don't open dialog if burn is already in progress
        guard fireViewModel.fire.burningData == nil else {
            return
        }

        // There must be a window when the Fire button is clicked
        guard let lastKeyMainWindowController = windowControllersManager.lastKeyMainWindowController,
              let burningWindow = lastKeyMainWindowController.window else {
            assertionFailure("Burning window or its content view controller is nil")
            return
        }
        burningWindow.makeKeyAndOrderFront(nil)
        let mainViewController = lastKeyMainWindowController.mainViewController

        // Use Fire dialog for regular windows, popover for Fire windows
        if !mainViewController.isBurner {
            Task { @MainActor in
                _=await self.presentFireDialog(mode: .fireButton, in: burningWindow)
            }
        } else {
            // Fire windows continue to use the legacy popover
            showFirePopover(relativeTo: mainViewController.tabBarViewController.fireButton,
                            tabCollectionViewModel: mainViewController.tabCollectionViewModel)
        }
    }

    func showFirePopover(relativeTo positioningView: NSView, tabCollectionViewModel: TabCollectionViewModel) {
        // Don't open popover if burn is already in progress
        guard fireViewModel.fire.burningData == nil else {
            return
        }

        // Close any existing popover before creating a new one
        if firePopover?.isShown ?? false {
            firePopover?.close()
            return
        }

        firePopover = FirePopover(fireViewModel: fireViewModel, tabCollectionViewModel: tabCollectionViewModel)
        firePopover?.show(positionedBelow: positioningView.bounds.insetBy(dx: 0, dy: 3), in: positioningView)
    }

}

extension FireCoordinator {

    /// Unified Fire dialog presenter for all entry points
    @MainActor
    func presentFireDialog(mode: FireDialogViewModel.Mode,
                           in window: NSWindow? = nil,
                           scopeVisits providedVisits: [Visit]? = nil,
                           settings: (any KeyedStoring<FireDialogViewSettings>)? = nil) async -> FireDialogView.Response {
        // Don't open dialog if burn is already in progress
        guard fireViewModel.fire.burningData == nil else {
            return .noAction
        }

        let targetWindow = window ?? windowControllersManager.lastKeyMainWindowController?.window
        guard let parentWindow = targetWindow,
              let tabCollectionViewModel = tabViewModelGetter(parentWindow) else { return .noAction }

        let scopeQuery: DataModel.HistoryQueryKind
        switch mode {
        case .fireButton, .mainMenuAll:
            scopeQuery = .rangeFilter(.all)
        case .historyView(let query):
            scopeQuery = query
            // Disable fire animation for History View requests
            visualizeFireAnimationDecider.isAnimationDisabled = true
        }
        defer {
            visualizeFireAnimationDecider.isAnimationDisabled = false
        }

        let scopeVisits: [Visit]
        // Use precomputed domains/visits when provided by caller (preferred)
        if let providedVisits {
            scopeVisits = providedVisits
        } else {
            // Fallback to querying provider
            scopeVisits = await historyProvider.visits(matching: scopeQuery)
        }
        let scopeCookieDomains = scopeVisits.lazy.compactMap(\.historyEntry?.url.host).convertedToETLDPlus1(tld: tld)

        let vm = FireDialogViewModel(
            fireViewModel: self.fireViewModel,
            tabCollectionViewModel: tabCollectionViewModel,
            historyCoordinating: self.historyCoordinating,
            aiChatHistoryCleaner: AIChatHistoryCleaner(featureFlagger: Application.appDelegate.featureFlagger,
                                                       aiChatMenuConfiguration: Application.appDelegate.aiChatMenuConfiguration,
                                                       featureDiscovery: DefaultFeatureDiscovery(),
                                                       privacyConfig: Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager),
            fireproofDomains: self.fireproofDomains,
            faviconManagement: self.faviconManagement,
            clearingOption: mode.shouldShowSegmentedControl ? nil /* last selected */ : .allData,
            includeTabsAndWindows: mode.shouldShowCloseTabsToggle ? nil /* last selected */ : false,
            includeChatHistory: mode.shouldShowChatHistoryToggle ? nil /* last selected */ : false,
            mode: mode,
            settings: settings,
            scopeCookieDomains: scopeCookieDomains,
            scopeVisits: scopeVisits,
            tld: tld
        )

        let response: FireDialogView.Response = await withCheckedContinuation { (continuation: CheckedContinuation<FireDialogView.Response, Never>) in
            var didResume = false
            func resumeOnce(returning value: FireDialogView.Response) {
                if !didResume {
                    didResume = true
                    continuation.resume(returning: value)
                }
            }

            let presenter = self.fireDialogViewFactory(
                FireDialogViewConfig(
                    viewModel: vm,
                    showIndividualSitesLink: [.fireButton, .mainMenuAll].contains(mode),
                    onConfirm: { response in
                        resumeOnce(returning: response)
                    }
                )
            )
            presenter.present(in: parentWindow) {
                resumeOnce(returning: .noAction)
            }
        }

        switch response {
        case .noAction:
            return .noAction

        case .burn(let options):
            guard var options else {
                assertionFailure("Received nil burn options")
                return .noAction
            }

            options.isToday = (scopeQuery == .rangeFilter(.today))

            let isAllHistorySelected = (options.clearingOption == .allData /* not Current Tab or Window */)
            && (scopeQuery == .rangeFilter(.all) || scopeQuery == .rangeFilter(.allSites))

            if options.includeChatHistory, !tabCollectionViewModel.burnerMode.isBurner {
                Task {
                    await aiChatSyncCleaner?()?.recordLocalClear(date: Date())
                }
            }

            await self.handleDialogResult(options, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: isAllHistorySelected)

            if [.fireButton, .mainMenuAll].contains(mode) {
                // Record fire button usage for contextual onboarding flows
                onboardingContextualDialogsManager?().fireButtonUsed()
            }
            return .burn(options: options)
        }
    }

    @MainActor
    func handleDialogResult(_ result: FireDialogResult, tabCollectionViewModel: TabCollectionViewModel?, isAllHistorySelected: Bool, from startTime: Double = CACurrentMediaTime()) async {
        dataClearingPixelsReporter.fireRetriggerPixelIfNeeded()

        if result.includeChatHistory {
            pixelFiring?.fire(AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount)
        }
        // If specific visits are provided (e.g., deleting for a day or a selection), burn only those visits
        if result.clearingOption == .allData /* not Current Tab or Window */,
           result.includeHistory, !isAllHistorySelected,
           let visits = result.selectedVisits, !visits.isEmpty {
            await fireViewModel.fire.burnVisits(visits,
                                                except: fireViewModel.fire.fireproofDomains,
                                                isToday: result.isToday,
                                                closeWindows: result.includeTabsAndWindows,
                                                clearSiteData: result.includeCookiesAndSiteData,
                                                clearChatHistory: result.includeChatHistory,
                                                urlToOpenIfWindowsAreClosed: nil)
            dataClearingPixelsReporter.fireCompletionPixel(from: startTime, dialogResult: result, path: .burnVisits, autoClear: false)
            return
        }
        pixelFiring?.fire(GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix)
        switch result.clearingOption {
        case .currentTab:
            pixelFiring?.fire(GeneralPixel.fireButton(option: .tab))
            guard let tabCollectionViewModel,
                  let tabViewModel = tabCollectionViewModel.selectedTabViewModel else {
                assertionFailure("No tab selected")
                return
            }
            let entity = Fire.BurningEntity.tab(tabViewModel: tabViewModel,
                                                selectedDomains: result.selectedCookieDomains ?? [],
                                                parentTabCollectionViewModel: tabCollectionViewModel,
                                                close: result.includeTabsAndWindows)
            await fireViewModel.fire.burnEntity(entity,
                                                includingHistory: result.includeHistory,
                                                includeCookiesAndSiteData: result.includeCookiesAndSiteData,
                                                includeChatHistory: result.includeChatHistory)
            dataClearingPixelsReporter.fireCompletionPixel(from: startTime, dialogResult: result, path: .burnEntity, autoClear: false)

        case .currentWindow:
            pixelFiring?.fire(GeneralPixel.fireButton(option: .window))
            guard let tabCollectionViewModel else {
                assertionFailure("Missing TabCollectionViewModel for window scope")
                return
            }
            let entity = Fire.BurningEntity.window(tabCollectionViewModel: tabCollectionViewModel,
                                                   selectedDomains: result.selectedCookieDomains ?? [],
                                                   close: result.includeTabsAndWindows)
            await fireViewModel.fire.burnEntity(entity,
                                                includingHistory: result.includeHistory,
                                                includeCookiesAndSiteData: result.includeCookiesAndSiteData,
                                                includeChatHistory: result.includeChatHistory)
            dataClearingPixelsReporter.fireCompletionPixel(from: startTime, dialogResult: result, path: .burnEntity, autoClear: false)

        case .allData:
            pixelFiring?.fire(GeneralPixel.fireButton(option: .allSites))
            // "All" implies history too; respect includeHistory by routing via burnAll or burnEntity
            if isAllHistorySelected && result.includeTabsAndWindows && result.includeHistory {
                await fireViewModel.fire.burnAll(isBurnOnExit: false,
                                                 opening: .newtab,
                                                 includeCookiesAndSiteData: result.includeCookiesAndSiteData,
                                                 includeChatHistory: result.includeChatHistory)
                dataClearingPixelsReporter.fireCompletionPixel(from: startTime, dialogResult: result, path: .burnAll, autoClear: false)
            } else {
                let entity = Fire.BurningEntity.allWindows(mainWindowControllers: windowControllersManager.mainWindowControllers,
                                                           selectedDomains: result.selectedCookieDomains ?? [],
                                                           customURLToOpen: nil,
                                                           close: result.includeTabsAndWindows)
                await fireViewModel.fire.burnEntity(entity,
                                                    includingHistory: result.includeHistory,
                                                    includeCookiesAndSiteData: result.includeCookiesAndSiteData,
                                                    includeChatHistory: result.includeChatHistory)
                dataClearingPixelsReporter.fireCompletionPixel(from: startTime, dialogResult: result, path: .burnEntity, autoClear: false)
            }
        }
        if result.includeHistory,
           result.clearingOption != .allData || !result.includeTabsAndWindows {
            // History View doesn't currently support having new data pushed to it
            // so we need to instruct all open history tabs to reload themselves.
            let historyTabs = self.windowControllersManager.mainWindowControllers
                .flatMap(\.mainViewController.tabCollectionViewModel.tabCollection.tabs)
                .filter { $0.content.isHistory }
            historyTabs.forEach { $0.reload() }
        }
    }
}
/// Allows locally disabling Fire animation depending on context
final class OverridableVisualizeFireSettingsDecider: VisualizeFireSettingsDecider {
    private let internalDecider: VisualizeFireSettingsDecider?

    var isAnimationDisabled: Bool = false

    var shouldShowFireAnimation: Bool {
        isAnimationDisabled ? false : internalDecider?.shouldShowFireAnimation ?? false
    }

    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> {
        internalDecider?.shouldShowFireAnimationPublisher ?? Empty().eraseToAnyPublisher()
    }

    var isOpenFireWindowByDefaultEnabled: Bool {
        internalDecider?.isOpenFireWindowByDefaultEnabled ?? false
    }

    var shouldShowOpenFireWindowByDefaultPublisher: AnyPublisher<Bool, Never> {
        internalDecider?.shouldShowOpenFireWindowByDefaultPublisher ?? Empty().eraseToAnyPublisher()
    }

    init(internalDecider: VisualizeFireSettingsDecider?) {
        self.internalDecider = internalDecider
    }

}
