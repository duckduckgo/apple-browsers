//
//  RootDebugViewController.swift
//  DuckDuckGo
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
import Common
import Configuration
import Core
import Crashes
import DDGSync
import Kingfisher
import LinkPresentation
import NetworkProtection
import Persistence
import SwiftUI
import UIKit
import WebKit

// MARK: Please Use DebugScreensViewController to add new debug views - do not add anything else this as it will be removed, thanks.")
class RootDebugViewController: UITableViewController {

    enum Row: Int {
        case resetAutoconsentPrompt = 665
        case crashFatalError = 666
        case crashMemory = 667
        case crashException = 673
        case crashCxxException = 675
        case toggleInspectableWebViews = 668
        case toggleInternalUserState = 669
        case openVanillaBrowser = 670
        case resetSendCrashLogs = 671
        case refreshConfig = 672
        case newTabPageSections = 674
        case onboarding = 676
        case resetSyncPromoPrompts = 677
        case resetTipKit = 681
        case aiChat = 682
        case webViewStateRestoration = 683
        case featureFlags = 684
    }

    @IBOutlet weak var shareButton: UIBarButtonItem!

    weak var reportGatheringActivity: UIView?

    @IBAction func onShareTapped() {
        presentShareSheet(withItems: [DiagnosticReportDataSource(delegate: self, fireproofing: fireproofing)], fromButtonItem: shareButton)
    }

    private let bookmarksDatabase: CoreDataDatabase
    private let sync: DDGSyncing
    private let internalUserDecider: InternalUserDecider
    let tabManager: TabManager
    private let tipKitUIActionHandler: TipKitDebugOptionsUIActionHandling
    private let fireproofing: Fireproofing

    @UserDefaultsWrapper(key: .lastConfigurationRefreshDate, defaultValue: .distantPast)
    private var lastConfigurationRefreshDate: Date

    init?(coder: NSCoder,
          sync: DDGSyncing,
          bookmarksDatabase: CoreDataDatabase,
          internalUserDecider: InternalUserDecider,
          tabManager: TabManager,
          tipKitUIActionHandler: TipKitDebugOptionsUIActionHandling = TipKitDebugOptionsUIActionHandler(),
          fireproofing: Fireproofing) {

        self.sync = sync
        self.bookmarksDatabase = bookmarksDatabase
        self.internalUserDecider = internalUserDecider
        self.tabManager = tabManager
        self.tipKitUIActionHandler = tipKitUIActionHandler
        self.fireproofing = fireproofing

        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // This might be annoying but I want to flush out any missing functionality before removing it.
        let controller = UIAlertController(title: "Something missing?", message: "Something you need in here that isn't in the other screen?  Let us know by dropping a task in the iOS App Development project.", preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: "OK!", style: .default))

        present(controller: controller, fromView: self.view)

        view.backgroundColor = UIColor(designSystemColor: .background)
    }

    // Brindy - migrated
    @IBSegueAction func onCreateImageCacheDebugScreen(_ coder: NSCoder) -> ImageCacheDebugViewController? {
        guard let controller = ImageCacheDebugViewController(coder: coder,
                                                             bookmarksDatabase: self.bookmarksDatabase,
                                                             fireproofing: fireproofing) else {
            fatalError("Failed to create controller")
        }

        return controller
    }

    // Brindy - migrated
    @IBSegueAction func onCreateSyncDebugScreen(_ coder: NSCoder, sender: Any?, segueIdentifier: String?) -> SyncDebugViewController {
        guard let controller = SyncDebugViewController(coder: coder,
                                                       sync: self.sync,
                                                       bookmarksDatabase: self.bookmarksDatabase) else {
            fatalError("Failed to create controller")
        }

        return controller
    }

    // brindy - migrated
    @IBSegueAction func onCreateNetPDebugScreen(_ coder: NSCoder, sender: Any?, segueIdentifier: String?) -> NetworkProtectionDebugViewController {
        guard let controller = NetworkProtectionDebugViewController(coder: coder) else {
            fatalError("Failed to create controller")
        }

        return controller
    }

    // brindy - migrated
    @IBSegueAction func onCreateCookieDebugScreen(_ coder: NSCoder) -> CookieDebugViewController? {
        guard let controller = CookieDebugViewController(coder: coder, fireproofing: fireproofing) else {
            fatalError("Failed to create controller")
        }

        return controller
    }

    // brindy - migrated
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if cell.tag == Row.toggleInspectableWebViews.rawValue {
            cell.accessoryType = AppUserDefaults().inspectableWebViewEnabled ? .checkmark : .none
        } else if cell.tag == Row.toggleInternalUserState.rawValue {
            cell.accessoryType = (internalUserDecider.isInternalUser) ? .checkmark : .none
        }

        cell.backgroundColor = UIColor(designSystemColor: .background)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        defer {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        if let rowTag = tableView.cellForRow(at: indexPath)?.tag,
           let row = Row(rawValue: rowTag),
           let cell = tableView.cellForRow(at: indexPath) {

            switch row {
            case .openVanillaBrowser: // brindy migrated
                openVanillaBrowser(nil)

            case .resetTipKit: // brindy - migrated
                tipKitUIActionHandler.resetTipKitTapped()

            case .resetSyncPromoPrompts: // brindy - migrated
                let syncPromoPresenter = SyncPromoManager(syncService: sync)
                syncPromoPresenter.resetPromos()
                ActionMessageView.present(message: "Sync Promos reset")

            case .resetAutoconsentPrompt: // Brindy - migrated
                AppUserDefaults().clearAutoconsentUserSetting()

            case .crashFatalError: // brindy - migrated to crash screen
                fatalError(#function)

            case .crashMemory: // brindy - migrated to crash screen
                var arrays = [String]()
                while 1 != 2 {
                    arrays.append(UUID().uuidString)
                }

            case .crashException: // brindy - migrated to crash screen - created alterantive div/0 error
                tableView.beginUpdates()
                tableView.deleteRows(at: [indexPath], with: .automatic)
                tableView.endUpdates()

            case .crashCxxException: // brindy to crash screen - migrated
                throwTestCppException()

            case .toggleInspectableWebViews: // brindy - migrated
                let defaults = AppUserDefaults()
                defaults.inspectableWebViewEnabled.toggle()
                cell.accessoryType = defaults.inspectableWebViewEnabled ? .checkmark : .none
                NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.inspectableWebViewsToggled))

            case .toggleInternalUserState: // brindy - migrated
                let newState = !internalUserDecider.isInternalUser
                (internalUserDecider as? DefaultInternalUserDecider)?.debugSetInternalUserState(newState)
                cell.accessoryType = newState ? .checkmark : .none
                NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.inspectableWebViewsToggled))

            case .resetSendCrashLogs: // migrated to crash screen
                AppUserDefaults().crashCollectionOptInStatus = .undetermined

            case .refreshConfig: // brindy - migrated to config info screen
                fetchAssets()

            case .newTabPageSections: // brindy - migrated
                let controller = UIHostingController(rootView: NewTabPageSectionsDebugView())
                show(controller, sender: nil)

            case .onboarding: // brindy - migrated
                let action = { [weak self] in
                    guard let self else { return }
                    self.showOnboardingIntro()
                }
                let controller = UIHostingController(rootView: OnboardingDebugView(onNewOnboardingIntroStartAction: action))
                show(controller, sender: nil)

            case .aiChat: // Brindy - migrated
                let controller = UIHostingController(rootView: AIChatDebugView())
                navigationController?.pushViewController(controller, animated: true)
            case .webViewStateRestoration: // brindy - migrated
                let controller = UIHostingController(rootView: WebViewStateRestorationDebugView())
                navigationController?.pushViewController(controller, animated: true)
            case .featureFlags: // Brindy - migrated
                let hostingController = UIHostingController(rootView: FeatureFlagsMenuView())
                navigationController?.pushViewController(hostingController, animated: true)
            }
        }
    }

    // brindy - migrated to configuration refresh info screen
    func fetchAssets() {
        self.lastConfigurationRefreshDate = Date.distantPast
        AppConfigurationFetch().start(isDebug: true) { [weak tableView] result in
            switch result {
            case .assetsUpdated(let protectionsUpdated):
                if protectionsUpdated {
                    ContentBlocking.shared.contentBlockingManager.scheduleCompilation()
                }
                DispatchQueue.main.async {
                    tableView?.reloadData()
                }

            case .noData:
                break
            }
        }
    }
}

// Brindy - migrated to debug screen
extension RootDebugViewController: DiagnosticReportDataSourceDelegate {

    func dataGatheringStarted() {
        DispatchQueue.main.async {
            let background = UIView()
            background.frame = self.view.window?.frame ?? .zero
            background.center = self.view.window?.center ?? .zero
            background.backgroundColor = .black.withAlphaComponent(0.5)
            self.view.window?.addSubview(background)
            self.reportGatheringActivity = background

            let activity = UIActivityIndicatorView()
            activity.startAnimating()
            activity.style = .large
            activity.center = background.center
            background.addSubview(activity)
        }
    }

    func dataGatheringComplete() {
        DispatchQueue.main.async {
            self.reportGatheringActivity?.removeFromSuperview()
        }
    }

}
