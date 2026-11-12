//
//  BrowserWindowManager.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import Core
import FeatureFlags_iOS
import Persistence
import PrivacyConfig
import UIKit
import WebKit

struct BrowserWindowStorage {
    static func directory(in base: URL, windowIdentifier: String?) -> URL {
        guard let windowIdentifier else { return base }
        let component = windowIdentifier.utf8.map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent("BrowserWindows").appendingPathComponent(component)
    }
}

final class BrowserWindowTabsModel: TabsModelReading {
    private var models: [String: TabsModelReading] = [:]

    private struct RestoredTabs: TabsModelReading {
        let tabs: [Tab]
        var count: Int { tabs.count }
    }

    init(restoringSessions: [String] = []) throws {
        for identifier in restoringSessions {
            let persistence = try TabsModelPersistence(windowIdentifier: identifier)
            let tabs = try [persistence.getTabsModel(for: .normal), persistence.getTabsModel(for: .fire)]
                .compactMap { $0 }.flatMap(\.tabs)
            include(RestoredTabs(tabs: tabs), windowIdentifier: identifier)
        }
    }
    var tabs: [Tab] { models.values.flatMap(\.tabs) }
    var count: Int { models.values.reduce(0) { $0 + $1.count } }

    func include(_ model: TabsModelReading, windowIdentifier: String?) {
        models[windowIdentifier ?? "primary"] = model
    }

    func remove(windowIdentifier: String?) {
        models.removeValue(forKey: windowIdentifier ?? "primary")
    }
}

@MainActor
final class BrowserWindowManager {
    static let activityType = "com.duckduckgo.browser.new-window"
    static let primarySessionKey = "com.duckduckgo.browser.primary-window"
    private static let sessionsKey = "com.duckduckgo.browser.windows"

    let allowsMultipleWindows: Bool
    var allowsAdditionalWindows: Bool {
        allowsMultipleWindows && !primaryCoordinator.controller.isStartupOnboardingPending
    }
    private(set) weak var focusedWindow: UIWindow?
    private let primaryCoordinator: MainCoordinator
    private let makeCoordinator: (String?, HistoryManaging?) throws -> MainCoordinator
    private var coordinators: [String: MainCoordinator] = [:]
    private var stateMachines: [String: AppStateMachine] = [:]
    private var menuSubscriptions: [ObjectIdentifier: AnyCancellable] = [:]
    private var foregroundWindows: Set<String> = []
    private var dependencies: AppDependencies?
    private var lastBackgroundDateStorage: (any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>)?
    private let fireCoordinator = BrowserWindowFireCoordinator()
    private var launchAutoClearClaimed = false
    private var hasConnectedWindow = false
    private var primarySessionIdentifier: String?
    private var knownSessionIdentifiers: Set<String>
    private var clearingOverlays: [UIView] = []

    static func isEnabled(using featureFlagger: FeatureFlagger) -> Bool {
        if #available(iOS 17, *) {
            return featureFlagger.isFeatureOn(.iPadMultiWindow)
        }
        return false
    }

    init(primaryCoordinator: MainCoordinator,
         allowsMultipleWindows: Bool,
         makeCoordinator: @escaping (String?, HistoryManaging?) throws -> MainCoordinator) {
        self.primaryCoordinator = primaryCoordinator
        self.allowsMultipleWindows = allowsMultipleWindows
        self.makeCoordinator = makeCoordinator
        primarySessionIdentifier = UserDefaults.app.string(forKey: Self.primarySessionKey)
        let storedSessions = UserDefaults.app.stringArray(forKey: Self.sessionsKey)
        knownSessionIdentifiers = Set(storedSessions ?? [])
        if storedSessions == nil, let primarySessionIdentifier {
            knownSessionIdentifiers.insert(primarySessionIdentifier)
            knownSessionIdentifiers.formUnion(UIApplication.shared.openSessions.map(\.persistentIdentifier))
        }
        register(primaryCoordinator)
    }

    func configure(dependencies: AppDependencies,
                   lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        self.dependencies = dependencies
        self.lastBackgroundDateStorage = lastBackgroundDateStorage
    }

    static func canConnect(identifier: String, knownIdentifiers: Set<String>, hasConnectedWindow: Bool, allowsAdditionalWindows: Bool) -> Bool {
        !hasConnectedWindow || knownIdentifiers.contains(identifier) || allowsAdditionalWindows
    }

    func canConnect(identifier: String) -> Bool {
        Self.canConnect(identifier: identifier, knownIdentifiers: knownSessionIdentifiers,
                        hasConnectedWindow: hasConnectedWindow, allowsAdditionalWindows: allowsAdditionalWindows)
    }

    private func saveSessionIdentifiers() {
        UserDefaults.app.set(Array(knownSessionIdentifiers).sorted(), forKey: Self.sessionsKey)
    }

    func connect(window: UIWindow, session: UISceneSession, options: UIScene.ConnectionOptions) throws -> AppStateMachine {
        guard var dependencies, let lastBackgroundDateStorage else {
            preconditionFailure("Window dependencies missing")
        }
        let identifier = session.persistentIdentifier
        let coordinator = try coordinator(for: identifier)
        dependencies.mainCoordinator = coordinator
        if hasConnectedWindow { dependencies.launchTaskManager = LaunchTaskManager() }
        hasConnectedWindow = true
        dependencies.windowIdentifier = identifier
        _ = coordinator.controller.appWidthObserver.willResize(toWidth: window.bounds.width)
        let activity = options.userActivities.first ?? session.stateRestorationActivity
        restoreMode(from: activity, coordinator: coordinator)
        let action: AppAction?
        if let item = options.shortcutItem {
            action = .handleShortcutItem(item)
        } else if let url = options.urlContexts.first?.url {
            action = .openURL(url)
        } else if let activity, activity.activityType != Self.activityType {
            action = .handleUserActivity(activity)
        } else {
            action = nil
        }
        let connected = Connected(stateContext: .init(didFinishLaunchingStartTime: 0, appDependencies: dependencies),
                                  actionToHandle: action, window: window,
                                  lastBackgroundDateStorage: lastBackgroundDateStorage)
        let machine = AppStateMachine(initialState: .connected(connected))
        if let action { machine.handle(action) }
        stateMachines[identifier] = machine
        if fireCoordinator.isBurning { cover(window) }
        return machine
    }

    private func restoreMode(from activity: NSUserActivity?, coordinator: MainCoordinator) {
        guard activity?.activityType == Self.activityType, activity?.userInfo?["fireMode"] as? Bool == true,
              coordinator.controller.fireModeCapability.isFireModeEnabled else { return }
        coordinator.tabManager.setBrowsingMode(.fire, source: .tabSelection)
        if coordinator.tabManager.currentTabsModel.isEmpty {
            _ = coordinator.tabManager.add(url: nil, inheritedAttribution: nil)
        }
    }

    private func coordinator(for identifier: String) throws -> MainCoordinator {
        if let coordinator = coordinators[identifier] { return coordinator }
        if primarySessionIdentifier == nil {
            primarySessionIdentifier = identifier
            UserDefaults.app.set(identifier, forKey: Self.primarySessionKey)
        }
        let coordinator: MainCoordinator
        if identifier == primarySessionIdentifier {
            coordinator = primaryCoordinator
        } else {
            coordinator = try makeCoordinator(identifier, primaryCoordinator.historyManager)
            register(coordinator)
        }
        coordinators[identifier] = coordinator
        knownSessionIdentifiers.insert(identifier)
        saveSessionIdentifiers()
        return coordinator
    }

    private func register(_ coordinator: MainCoordinator) {
        coordinator.controller.browserWindowsForFireAnimation = { [weak self, weak coordinator] request in
            if case .all = request.scope { try? self?.restoreStoredWindows() }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }.flatMap(\.windows)
                .filter { $0.accessibilityIdentifier == "Browser.Window.Main" && !$0.isHidden }
            return Self.animationWindows(for: request, origin: coordinator?.controller.viewIfLoaded?.window, windows: windows)
        }
        menuSubscriptions[ObjectIdentifier(coordinator)] = coordinator.controller.menuRebuildRequests.sink { [weak self] in
            self?.dependencies?.services.mainMenuService.requestRebuild()
        }
        if allowsMultipleWindows {
            coordinator.controller.browserWindowRequest = { [weak self, weak coordinator] mode in
                guard self?.allowsAdditionalWindows == true, let scene = coordinator?.controller.view.window?.windowScene else { return }
                let activity = Self.activity(fireMode: mode == .fire)
                let options = UIScene.ActivationRequestOptions()
                options.requestingScene = scene
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: options)
            }
        }
        (coordinator.controller.fireExecutor as? FireExecutor)?.windowBurnHandler = { [weak self, weak coordinator] request, state in
            guard let self, let coordinator else { return }
            await self.burn(request: request, state: state, origin: coordinator)
        }
    }

    static func activity(fireMode: Bool) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.userInfo = ["fireMode": fireMode]
        return activity
    }

    func claimLaunchAutoClear() -> Bool {
        defer { launchAutoClearClaimed = true }
        return !launchAutoClearClaimed
    }

    func waitForBurn() async {
        await fireCoordinator.waitForBurn()
    }

    func enterForeground(_ identifier: String) -> Bool {
        let wasEmpty = foregroundWindows.isEmpty
        foregroundWindows.insert(identifier)
        return wasEmpty
    }

    func focus(window: UIWindow?, identifier: String) {
        focusedWindow = window
        guard let coordinator = coordinators[identifier], let dependencies else { return }
        AppWidthObserver.shared.update(from: coordinator.controller.appWidthObserver)
        dependencies.services.syncService.presenter = coordinator.controller
        dependencies.services.remoteMessagingService.messageNavigator = DefaultMessageNavigator(delegate: coordinator.controller)
        dependencies.services.systemSettingsPiPTutorialService.setPresenter(coordinator)
        dependencies.services.vpnService.focus(on: coordinator)
        dependencies.services.mainMenuService.requestRebuild()
    }

    func leaveForeground(_ identifier: String) -> Bool {
        foregroundWindows.remove(identifier)
        return foregroundWindows.isEmpty
    }

    func disconnect(_ identifier: String) {
        guard let machine = stateMachines[identifier] else { return }
        switch machine.currentState {
        case .foreground, .connected: machine.handle(.didEnterBackground)
        default: break
        }
    }

    func discard(_ sessions: Set<UISceneSession>) {
        Task {
            await fireCoordinator.waitForBurn()
            for session in sessions {
                let identifier = session.persistentIdentifier
                guard knownSessionIdentifiers.contains(identifier),
                      let coordinator = try? coordinator(for: identifier) else { continue }
                let request = FireRequest(options: .all, trigger: .fireModeAutoClear, scope: .fireMode, source: .autoClear)
                guard let executor = coordinator.controller.fireExecutor as? FireExecutor else { continue }
                try? await fireCoordinator.burn(request: request, state: .inactive, origin: executor, allWindows: { [] }, afterBurn: {
                    _ = coordinator.tabManager.removeAll()
                    coordinator.discardWindowTabs()
                    self.menuSubscriptions.removeValue(forKey: ObjectIdentifier(coordinator))
                    self.coordinators.removeValue(forKey: identifier)
                    self.stateMachines.removeValue(forKey: identifier)
                    self.foregroundWindows.remove(identifier)
                    self.knownSessionIdentifiers.remove(identifier)
                    self.saveSessionIdentifiers()
                    await self.retireFireContainer(for: identifier)
                })
            }
        }
    }

    private func retireFireContainer(for identifier: String) async {
        guard #available(iOS 17, *) else { return }
        let manager = identifier == primarySessionIdentifier ? DataStoreIDManager.shared : DataStoreIDManager(windowIdentifier: identifier)
        manager.invalidateCurrentFireModeID()
        let baseURLs = [FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Global.appConfigurationGroupName)].compactMap { $0 }
        for id in manager.pendingRemovalFireModeIDs {
            for base in baseURLs {
                try? FileManager.default.removeItem(at: base.appendingPathComponent("DuckAiNativeStorage-fireMode").appendingPathComponent(id.uuidString))
            }
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                manager.removePendingRemovalFireModeID(id)
            } catch {
                Logger.general.error("Could not retire a closed window's Fire container: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func burn(request: FireRequest, state: DataStoreWarmup.ApplicationState, origin: MainCoordinator) async {
        guard let executor = origin.controller.fireExecutor as? FireExecutor else { return }
        do {
            try await fireCoordinator.burn(request: request, state: state, origin: executor, allWindows: {
                try self.restoreStoredWindows()
                return ([self.primaryCoordinator] + Array(self.coordinators.values)).compactMap {
                    $0.controller.fireExecutor as? FireExecutor
                }
            }, willBurnAll: {
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    for window in scene.windows where window.accessibilityIdentifier == "Browser.Window.Main" { self.cover(window) }
                }
            }, didBurnAll: {
                self.clearingOverlays.forEach { $0.removeFromSuperview() }
                self.clearingOverlays.removeAll()
            })
        } catch {
            if let window = origin.controller.view.window {
                Terminating(error: error).alertAndTerminate(window: window)
            }
        }
    }

    private func cover(_ window: UIWindow) {
        clearingOverlays.append(Self.addClearingOverlay(to: window))
    }

    private func restoreStoredWindows() throws {
        let identifiers = knownSessionIdentifiers.union(UIApplication.shared.openSessions.map(\.persistentIdentifier))
        for identifier in identifiers {
            _ = try coordinator(for: identifier)
        }
    }

    static func animationWindows(for request: FireRequest, origin: UIWindow?, windows: [UIWindow]) -> [UIWindow] {
        let origin = [origin].compactMap { $0 }
        guard case .all = request.scope else { return origin }
        var seen: Set<ObjectIdentifier> = []
        return (origin + windows).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    static func addClearingOverlay(to window: UIWindow) -> UIView {
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .systemBackground
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.accessibilityIdentifier = "Browser.Window.Clearing"
        if let animation = window.subviews.first(where: { $0.accessibilityIdentifier == FireButtonAnimator.overlayIdentifier }) {
            window.insertSubview(overlay, belowSubview: animation)
        } else {
            window.addSubview(overlay)
        }
        return overlay
    }
}

@MainActor
protocol BrowserWindowFireExecuting: AnyObject {
    func prepare(for request: FireRequest)
    func burnInWindow(request: FireRequest, applicationState: DataStoreWarmup.ApplicationState) async
}

extension FireExecutor: BrowserWindowFireExecuting {}

@MainActor
final class BrowserWindowFireCoordinator {
    private var burnTask: Task<Void, Error>?
    var isBurning: Bool { burnTask != nil }

    func waitForBurn() async {
        try? await burnTask?.value
    }

    func burn(request: FireRequest, state: DataStoreWarmup.ApplicationState, origin: any BrowserWindowFireExecuting,
              allWindows: @escaping () throws -> [any BrowserWindowFireExecuting],
              willBurnAll: @escaping () -> Void = {}, didBurnAll: @escaping () -> Void = {},
              afterBurn: @escaping () async -> Void = {}) async throws {
        let previous = burnTask
        let task = Task { @MainActor in
            try? await previous?.value
            if case .all = request.scope {
                var seen: Set<ObjectIdentifier> = []
                let targets = try ([origin] + allWindows()).filter { seen.insert(ObjectIdentifier($0)).inserted }
                willBurnAll()
                defer { didBurnAll() }
                targets.forEach { $0.prepare(for: request) }
                for target in targets {
                    await target.burnInWindow(request: request, applicationState: state)
                }
            } else {
                await origin.burnInWindow(request: request, applicationState: state)
            }
            await afterBurn()
        }
        burnTask = task
        defer { if burnTask == task { burnTask = nil } }
        try await task.value
    }
}
