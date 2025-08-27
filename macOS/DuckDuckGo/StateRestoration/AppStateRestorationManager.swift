//
//  AppStateRestorationManager.swift
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

import Foundation
import Combine
import Common
import PixelKit
import os.log
import Persistence
import BrowserServicesKit

@MainActor
final class AppStateRestorationManager: NSObject {
    private enum Constants {
        static let fileName = "persistentState"
        static let appDidTerminateAsExpectedKey = "appDidTerminateAsExpected"
    }

    private let service: StatePersistenceService
    private let tabSnapshotCleanupService: TabSnapshotCleanupService
    private var appWillRelaunchCancellable: AnyCancellable?
    private var stateChangedCancellable: AnyCancellable?
    private let pinnedTabsManagerProvider: PinnedTabsManagerProviding = Application.appDelegate.pinnedTabsManagerProvider
    private let startupPreferences: StartupPreferences
    private let keyValueStore: ThrowingKeyValueStoring
    private let sessionRestorePromptCoordinator: SessionRestorePromptCoordinating

    @UserDefaultsWrapper(key: .appIsRelaunchingAutomatically, defaultValue: false)
    private var appIsRelaunchingAutomatically: Bool

    private var appDidTerminateAsExpected: Bool {
        get {
            do {
                if let value = try keyValueStore.object(forKey: Constants.appDidTerminateAsExpectedKey) as? Bool {
                    return value
                }
            } catch {
                Logger.general.error("Failed to read appDidTerminateAsExpected from keyValueStore: \(error)")
            }
            return true
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: Constants.appDidTerminateAsExpectedKey)
            } catch {
                Logger.general.error("Failed to write appDidTerminateAsExpected to keyValueStore: \(error)")
            }
        }
    }

    private var shouldRestoreRegularTabs: Bool {
        startupPreferences.restorePreviousSession
    }

    convenience init(fileStore: FileStore, startupPreferences: StartupPreferences, keyValueStore: ThrowingKeyValueStoring, sessionRestorePromptCoordinator: SessionRestorePromptCoordinating) {
        let service = StatePersistenceService(fileStore: fileStore, fileName: Constants.fileName)
        self.init(fileStore: fileStore, service: service, startupPreferences: startupPreferences, keyValueStore: keyValueStore, sessionRestorePromptCoordinator: sessionRestorePromptCoordinator)
    }

    init(
        fileStore: FileStore,
        service: StatePersistenceService,
        startupPreferences: StartupPreferences,
        keyValueStore: ThrowingKeyValueStoring,
        sessionRestorePromptCoordinator: SessionRestorePromptCoordinating
    ) {
        self.service = service
        self.tabSnapshotCleanupService = TabSnapshotCleanupService(fileStore: fileStore)
        self.startupPreferences = startupPreferences
        self.keyValueStore = keyValueStore
        self.sessionRestorePromptCoordinator = sessionRestorePromptCoordinator
    }

    func subscribeToAutomaticAppRelaunching(using relaunchPublisher: AnyPublisher<Void, Never>) {
        appWillRelaunchCancellable = relaunchPublisher
            .map { true }
            .assign(to: \.appIsRelaunchingAutomatically, onWeaklyHeld: self)
    }

    var canRestoreLastSessionState: Bool {
        service.canRestoreLastSessionState
    }

    @discardableResult
    func restoreLastSessionState(interactive: Bool, includeRegularTabs: Bool) -> WindowManagerStateRestoration? {
        var state: WindowManagerStateRestoration?
        do {
            let isCalledAtStartup = !interactive
            try service.restoreState(using: { coder in
                state = try WindowsManager.restoreState(from: coder, includeRegularTabs: includeRegularTabs, includePinnedTabs: isCalledAtStartup)
            })
            // rename loaded app state file
            service.didLoadState()
        } catch CocoaError.fileReadNoSuchFile {
            // ignore
        } catch {
            Logger.general.error("App state could not be decoded: \(error.localizedDescription)")
            PixelKit.fire(DebugEvent(GeneralPixel.appStateRestorationFailed, error: error),
                          withAdditionalParameters: ["interactive": String(interactive)])
        }

        return state
    }

    func clearLastSessionState() {
        service.clearState(sync: true)
    }

    // Cleans all stored snapshots except snapshots listed in the state
    func cleanTabSnapshots(state: WindowManagerStateRestoration? = nil) {
        let tabs = state?.windows.flatMap { $0.model.tabCollection.tabs } ?? []
        let perWindowPinnedTabs = state?.windows.flatMap { $0.pinnedTabs?.tabs ?? [] } ?? []
        let applicationPinnedTabs = state?.applicationPinnedTabs?.tabs ?? []
        let stateSnapshotIds = (tabs + perWindowPinnedTabs + applicationPinnedTabs).compactMap { $0.tabSnapshotIdentifier }
        Task {
            await tabSnapshotCleanupService.cleanStoredSnapshots(except: Set(stateSnapshotIds))
        }
    }

    func applicationDidFinishLaunching() {
        let isRelaunchingAutomatically = self.appIsRelaunchingAutomatically
        self.appIsRelaunchingAutomatically = false
        // don‘t automatically restore windows if relaunched 2nd time with no recently updated app session state
        readLastSessionState(restoreWindows: !service.isAppStateFileStale || isRelaunchingAutomatically, restoreRegularTabs: shouldRestoreRegularTabs)

        let didCloseUnexpectedly = !appDidTerminateAsExpected
        appDidTerminateAsExpected = false // Set to false so it will be false if the app closes without terminating properly
        // Display a prompt to restore the last session when the user has disabled "restore previous session" and the app closed unexpectedly.
        // Don't show the prompt if relaunched 2nd time with no recently updated app session state (crash loop).
        if didCloseUnexpectedly && !shouldRestoreRegularTabs && canRestoreLastSessionState && !service.isAppStateFileStale {
            sessionRestorePromptCoordinator.showRestoreSessionPrompt { [weak self] restoreSession in
                guard let self, restoreSession else { return }
                restoreLastSessionState(interactive: true, includeRegularTabs: true)
            }
        }

        stateChangedCancellable = Publishers.Merge(
                Application.appDelegate.windowControllersManager.stateChanged,
                pinnedTabsManagerProvider.settingChangedPublisher
            )
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            // There is a favicon assignment after a restored tab loads that triggered unnecessary
            // saving of the state
            .sink { [weak self] _ in
                self?.persistAppState()
            }
    }

    func applicationWillTerminate() {
        stateChangedCancellable?.cancel()
        appDidTerminateAsExpected = true
        if Application.appDelegate.windowControllersManager.isInInitialState {
            service.clearState(sync: true)
        } else {
            persistAppState(sync: true)
        }
    }

    private func readLastSessionState(restoreWindows: Bool, restoreRegularTabs: Bool) {
        service.loadLastSessionState()
        if restoreWindows {
            let state = restoreLastSessionState(interactive: false, includeRegularTabs: restoreRegularTabs)
            cleanTabSnapshots(state: state)
        } else {
            migratePinnedTabsSettingIfNecessary()
            restorePinnedTabs()
            cleanTabSnapshots()
        }
        Application.appDelegate.windowControllersManager.updateIsInInitialState()
    }

    @MainActor
    private func restorePinnedTabs() {
        do {
            try service.restoreState(using: { coder in
                try WindowsManager.restoreState(from: coder, includeRegularTabs: false, includeWindows: false)
            })
        } catch CocoaError.fileReadNoSuchFile {
            // ignore
        } catch {
            Logger.general.error("Pinned tabs state could not be decoded: \(error)")
            PixelKit.fire(DebugEvent(GeneralPixel.appStateRestorationFailed, error: error))
        }
    }

    @MainActor
    private func persistAppState(sync: Bool = false) {
        service.persistState(using: Application.appDelegate.windowControllersManager.encodeState(with:), sync: sync)
    }

    private func migratePinnedTabsSettingIfNecessary() {
        TabsPreferences.shared.migratePinnedTabsSettingIfNecessary(nil)
    }
}
