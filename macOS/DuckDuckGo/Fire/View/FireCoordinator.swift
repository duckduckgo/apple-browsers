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
import Common
import History
import HistoryView
import PixelKit

// MARK: - Fire Dialog Presentation Abstractions (for testability)

protocol FireDialogViewPresenting {
    @MainActor
    func present(in window: NSWindow, completion: (() -> Void)?)
}

struct FireDialogViewConfig {
    let viewModel: FireDialogViewModel
    let featureFlagger: FeatureFlagger
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
    private(set) lazy var fireViewModel: FireViewModel = FireViewModel(tld: tld, visualizeFireAnimationDecider: NSApp.delegateTyped.visualizeFireSettingsDecider)
    private(set) var firePopover: FirePopover?
    private let tld: TLD
    private let featureFlagger: FeatureFlagger
    private let historyProvider: HistoryViewDataProviding
    private let fireDialogViewFactory: FireDialogViewFactory
    private let fireproofDomains: FireproofDomains
    private let tabViewModelGetter: (NSWindow) -> TabCollectionViewModel?

    init(tld: TLD, featureFlagger: FeatureFlagger, historyProvider: HistoryViewDataProviding, fireViewModel: FireViewModel? = nil, fireDialogViewFactory: FireDialogViewFactory? = nil, fireproofDomains: FireproofDomains? = nil, tabViewModelGetter: ((NSWindow) -> TabCollectionViewModel?)? = nil) {

        self.tld = tld
        self.featureFlagger = featureFlagger
        self.historyProvider = historyProvider
        self.fireproofDomains = fireproofDomains ?? Application.appDelegate.fireproofDomains
        self.tabViewModelGetter = tabViewModelGetter ?? { window in
            (window.contentViewController as? MainViewController)?.tabCollectionViewModel
        }

        self.fireDialogViewFactory = fireDialogViewFactory ?? { config in
            let view = FireDialogView(
                viewModel: config.viewModel,
                featureFlagger: config.featureFlagger,
                showIndividualSitesLink: config.showIndividualSitesLink,
                onConfirm: config.onConfirm
            )
            return DefaultFireDialogPresenter(view: view)
        }
        if let fireViewModel {
            self.fireViewModel = fireViewModel
        }
    }

    func fireButtonAction() {
        let burningWindow: NSWindow
        let waitForOpening: Bool

        if let lastKeyWindow = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window,
           lastKeyWindow.isVisible {
            burningWindow = lastKeyWindow
            burningWindow.makeKeyAndOrderFront(nil)
            waitForOpening = false
        } else {
            burningWindow = WindowsManager.openNewWindow(fireCoordinator: self)!
            waitForOpening = true
        }

        guard let mainViewController = burningWindow.contentViewController as? MainViewController else {
            assertionFailure("Burning window or its content view controller is nil")
            return
        }

        // Present dialog gated by feature flag; fallback to legacy popover
        if featureFlagger.isFeatureOn(.fireDialog) {
            Task { @MainActor in
                let response = await self.presentFireDialog(mode: .fireButton, in: burningWindow)
                if case .burn(let result?) = response {
                    PixelKit.fire(GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix)
                    switch result.clearingOption {
                    case .currentTab: PixelKit.fire(GeneralPixel.fireButton(option: .tab))
                    case .currentWindow: PixelKit.fire(GeneralPixel.fireButton(option: .window))
                    case .allData: PixelKit.fire(GeneralPixel.fireButton(option: .allSites))
                    }
                }
            }
        } else if waitForOpening {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1/3) {
                self.showFirePopover(relativeTo: mainViewController.tabBarViewController.fireButton,
                                     tabCollectionViewModel: mainViewController.tabCollectionViewModel)
            }
        } else {
            showFirePopover(relativeTo: mainViewController.tabBarViewController.fireButton,
                            tabCollectionViewModel: mainViewController.tabCollectionViewModel)
        }
    }

    func showFirePopover(relativeTo positioningView: NSView, tabCollectionViewModel: TabCollectionViewModel) {
        guard !(firePopover?.isShown ?? false) else {
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
    func presentFireDialog(mode: FireDialogViewModel.Mode, in window: NSWindow? = nil, scopeCookieDomains: Set<String>? = nil, scopeVisits: [Visit]? = nil) async -> FireDialogView.Response {
        let targetWindow = window ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
        guard let parentWindow = targetWindow,
              let tabCollectionViewModel = tabViewModelGetter(parentWindow) else { return .noAction }

        // Use precomputed domains/visits when provided by caller (preferred)
        var initialCookieDomains: Set<String>? = scopeCookieDomains
        var initialVisits: [Visit]? = scopeVisits

        // Fallback to provider if not supplied and mode implies a scope
        if initialCookieDomains == nil || initialVisits == nil {
            let scopeQuery: DataModel.HistoryQueryKind = switch mode {
            case .fireButton, .mainMenuAll, .historyAll, .allHistorySites: .rangeFilter(.all)
            case .historyToday: .rangeFilter(.today)
            case .historyYesterday: .rangeFilter(.yesterday)
            case .historyDate(let date): . dateFilter(date)
            case .historyOlder: .rangeFilter(.older)
            case .historySites(let domains): .domainFilter(domains)
            case .historyVisits: .rangeFilter(.all) // fallback to default, visits should be provided
            }

            if initialVisits == nil {
                assert(mode != .historyVisits, "Expected visits and domains to be non-nil when mode is .historyVisits")
                initialVisits = await historyProvider.visits(matching: scopeQuery)
            }
            if initialCookieDomains == nil {
                initialCookieDomains = await historyProvider.cookieDomains(matching: scopeQuery)
            }
        }

        let vm = FireDialogViewModel(
            fireViewModel: self.fireViewModel,
            tabCollectionViewModel: tabCollectionViewModel,
            historyCoordinating: Application.appDelegate.historyCoordinator,
            fireproofDomains: self.fireproofDomains,
            faviconManagement: Application.appDelegate.faviconManager,
            clearingOption: mode.shouldShowSegmentedControl ? nil /* last selected */ : .allData,
            includeTabsAndWindows: mode.shouldShowCloseTabsToggle ? nil /* last selected */ : false,
            mode: mode,
            scopeCookieDomains: initialCookieDomains,
            scopeVisits: initialVisits,
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
                    featureFlagger: Application.appDelegate.featureFlagger,
                    showIndividualSitesLink: mode == .fireButton,
                    onConfirm: { response in
                        resumeOnce(returning: response)
                    }
                )
            )
            presenter.present(in: parentWindow) {
                resumeOnce(returning: .noAction)
            }
        }
        let isToday = switch mode {
        case .historyToday: true
        default: false
        }

        switch response {
        case .noAction:
            return .noAction
        case .burn(let options):
            guard var options else { return .noAction }
            // Ensure cookie domains from current VM selection are included when not provided
            options.isToday = isToday

            switch mode {
            case .fireButton, .mainMenuAll:
                // Record fire button usage for contextual onboarding flows
                Application.appDelegate.onboardingContextualDialogsManager.fireButtonUsed()
            default: break
            }

            let isAllHistorySelected: Bool
            if scopeCookieDomains != nil || scopeVisits != nil {
                // If there's a specific scope passed from outside, it means we‘re not burning all
                isAllHistorySelected = false
            } else {
                // no specific domains passed initially
                isAllHistorySelected = options.selectedCookieDomains == nil || options.selectedCookieDomains?.count == vm.selectable.count
            }
            if options.selectedCookieDomains == nil {
                // set actual domains to delete
                options.selectedCookieDomains = vm.selectedCookieDomainsForScope
            }

            await self.handleDialogResult(options, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: isAllHistorySelected)
            return .burn(options: options)
        }
    }

    @MainActor
    func handleDialogResult(_ result: FireDialogResult, tabCollectionViewModel: TabCollectionViewModel?, isAllHistorySelected: Bool) async {

        // If specific visits are provided (e.g., deleting for a day or a selection), burn only those visits
        if result.clearingOption == .allData,
           result.includeHistory, !isAllHistorySelected,
           let visits = result.selectedVisits, !visits.isEmpty {
            await fireViewModel.fire.burnVisits(visits,
                                                except: fireViewModel.fire.fireproofDomains,
                                                isToday: result.isToday,
                                                closeWindows: result.includeTabsAndWindows,
                                                clearSiteData: result.includeCookiesAndSiteData,
                                                urlToOpenIfWindowsAreClosed: nil)
            return
        }

        switch result.clearingOption {
        case .currentTab:
            guard let tabCollectionViewModel = tabCollectionViewModel,
                  let tabViewModel = tabCollectionViewModel.selectedTabViewModel else {
                assertionFailure("No tab selected")
                return
            }
            let entity = Fire.BurningEntity.tab(tabViewModel: tabViewModel,
                                                selectedDomains: result.selectedCookieDomains ?? [],
                                                parentTabCollectionViewModel: tabCollectionViewModel,
                                                close: result.includeTabsAndWindows)
            await fireViewModel.fire.burnEntity(entity, includingHistory: result.includeHistory)

        case .currentWindow:
            guard let tabCollectionViewModel else {
                assertionFailure("Missing TabCollectionViewModel for window scope")
                return
            }
            let entity = Fire.BurningEntity.window(tabCollectionViewModel: tabCollectionViewModel,
                                                   selectedDomains: result.selectedCookieDomains ?? [],
                                                   close: result.includeTabsAndWindows)
            await fireViewModel.fire.burnEntity(entity, includingHistory: result.includeHistory)

        case .allData:
            PixelKit.fire(GeneralPixel.fireButton(option: .allSites))
            // "All" implies history too; respect includeHistory by routing via burnAll or burnEntity
            if isAllHistorySelected && result.includeTabsAndWindows && result.includeHistory {
                await fireViewModel.fire.burnAll(isBurnOnExit: false, opening: .newtab)
            } else {
                let entity = Fire.BurningEntity.allWindows(mainWindowControllers: Application.appDelegate.windowControllersManager.mainWindowControllers,
                                                           selectedDomains: result.selectedCookieDomains ?? [],
                                                           customURLToOpen: nil,
                                                           close: result.includeTabsAndWindows)
                await fireViewModel.fire.burnEntity(entity, includingHistory: result.includeHistory)
            }
        }
    }
}
