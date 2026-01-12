//
//  AutoClear.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import UIKit
import Core
import PrivacyConfig

protocol AutoClearing {

    var isClearingEnabled: Bool { get }
    func clearDataIfEnabled(launching: Bool, applicationState: DataStoreWarmup.ApplicationState) async

    var isClearingDue: Bool { get }
    func clearDataDueToTimeExpired(applicationState: DataStoreWarmup.ApplicationState) async
    func startClearingTimer(_ time: TimeInterval)

}

final class AutoClear: AutoClearing {

    private let worker: FireExecuting
    private var timestamp: TimeInterval?
    private let appSettings: AppSettings
    private let featureFlagger: FeatureFlagger

    var isClearingEnabled: Bool {
        return AutoClearSettingsModel(settings: appSettings) != nil
    }

    init(worker: FireExecuting,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger) {
        self.worker = worker
        self.appSettings = appSettings
        self.featureFlagger = featureFlagger
    }

    @MainActor
    func clearDataIfEnabled(launching: Bool = false, applicationState: DataStoreWarmup.ApplicationState = .unknown) async {
        guard var options = AutoClearSettingsModel(settings: appSettings)?.action else { return }
        if shouldInjectAIChatsFireOption(into: options) {
            options.insert(.aiChats)
        }
        let fireContext: FireContext = launching ? .autoClearOnLaunch : .autoClearOnForeground
        await worker.burn(options: options, applicationState: applicationState, fireContext: fireContext)
    }

    /// Note: function is parametrised because of tests.
    func startClearingTimer(_ time: TimeInterval = Date().timeIntervalSince1970) {
        timestamp = time
    }

    private func shouldClearData(elapsedTime: TimeInterval) -> Bool {
        guard let settings = AutoClearSettingsModel(settings: appSettings) else { return false }

        if ProcessInfo.processInfo.arguments.contains("autoclear-ui-test") {
            return elapsedTime > 5
        }

        switch settings.timing {
        case .termination:
            return false
        case .delay5min:
            return elapsedTime > 5 * 60
        case .delay15min:
            return elapsedTime > 15 * 60
        case .delay30min:
            return elapsedTime > 30 * 60
        case .delay60min:
            return elapsedTime > 60 * 60
        }
    }

    var isClearingDue: Bool {
        guard isClearingEnabled, let timestamp = timestamp else { return false }
        return shouldClearData(elapsedTime: Date().timeIntervalSince1970 - timestamp)
    }

    @MainActor
    func clearDataDueToTimeExpired(applicationState: DataStoreWarmup.ApplicationState) async {
        timestamp = nil
        await clearDataIfEnabled(applicationState: applicationState)
    }
    // Determine whether to inject the `.aiChats` fire option.
    // 
    // Criteria:
    // 1. The user has enabled "auto-clear AI chat history" in settings.
    // 2. FireOptions currently include `.data` but do NOT already include `.aiChats`.
    // 
    // This ensures .aiChats is only injected in the correct (legacy UI) scenarios.
    private func shouldInjectAIChatsFireOption(into options: FireOptions) -> Bool {
        options.contains(.data)
            && !options.contains(.aiChats)
            && !featureFlagger.isFeatureOn(.enhancedDataClearingSettings)
            && appSettings.autoClearAIChatHistory
    }

}

extension DataStoreWarmup.ApplicationState {

    init(with state: UIApplication.State) {
        switch state {
        case .inactive:
            self = .inactive
        case .active:
            self = .active
        case .background:
            self = .background
        @unknown default:
            self = .unknown
        }
    }
}
