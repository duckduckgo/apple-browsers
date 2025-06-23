//
//  FreemiumDebugMenu.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
import Freemium
import OSLog

final class FreemiumDebugMenu: NSMenuItem {

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init() {
        super.init(title: "Freemium", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")

        menu.addItem(NSMenuItem(title: "Set Freemium DBP Activated State TRUE", action: #selector(setFreemiumDBPActivateStateTrue), target: self))
        menu.addItem(NSMenuItem(title: "Set Freemium DBP Activated State FALSE", action: #selector(setFreemiumDBPActivateStateFalse), target: self))
        menu.addItem(NSMenuItem(title: "Set Freemium DBP First Profile Saved Timestamp NIL", action: #selector(setFirstProfileSavedTimestampNil), target: self))
        menu.addItem(NSMenuItem(title: "Set Freemium DBP Did Post First Profile Saved FALSE", action: #selector(setDidPostFirstProfileSavedNotificationFalse), target: self))
        menu.addItem(NSMenuItem(title: "Set Freemium DBP Did Post Results FALSE", action: #selector(setDidPostResultsNotificationFalse), target: self))
        menu.addItem(NSMenuItem(title: "Set Results and Trigger Post-Scan Banner", action: #selector(setResultsAndTriggerPostScanBanner), target: self))
        menu.addItem(NSMenuItem(title: "Set No Results and Trigger Post-Scan Banner", action: #selector(setNoResultsAndTriggerPostScanBanner), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Set New Tab Promotion Did Dismiss FALSE", action: #selector(setNewTabPromotionDidDismissFalse), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Log all state", action: #selector(logAllState), target: self))
        menu.addItem(NSMenuItem(title: "Display all state", action: #selector(displayAllState), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reset all Freemium Feature State", action: #selector(resetAllState), target: self))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Override Feature Flag -> ON", action: #selector(setFeatureFlagOverrideOn), target: self))
        menu.addItem(NSMenuItem(title: "Override Feature Flag -> OFF", action: #selector(setFeatureFlagOverrideOff), target: self))
        menu.addItem(NSMenuItem(title: "Reset Feature Flag Override", action: #selector(resetFeatureFlagOverride), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Override Storefront -> USA", action: #selector(setStorefrontOverrideOn), target: self))
        menu.addItem(NSMenuItem(title: "Override Storefront -> Non-USA", action: #selector(setStorefrontOverrideOff), target: self))
        menu.addItem(NSMenuItem(title: "Reset Storefront Override", action: #selector(resetStorefrontOverride), target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reset ALL Overrides", action: #selector(resetAllOverrides), target: self))

        return menu
    }

    @objc
    func setFreemiumDBPActivateStateTrue() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didActivate = true
    }

    @objc
    func setFreemiumDBPActivateStateFalse() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didActivate = false
    }

    @objc
    func setFirstProfileSavedTimestampNil() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstProfileSavedTimestamp = nil
    }

    @objc
    func setDidPostFirstProfileSavedNotificationFalse() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostFirstProfileSavedNotification = false
    }

    @objc
    func setDidPostResultsNotificationFalse() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostResultsNotification = false
    }

    @objc
    func setResultsAndTriggerPostScanBanner() {
        let results = FreemiumDBPMatchResults(matchesCount: 19, brokerCount: 3)
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults = results
        NotificationCenter.default.post(name: .freemiumDBPResultPollingComplete, object: nil)
    }

    @objc
    func setNoResultsAndTriggerPostScanBanner() {
        let noResults = FreemiumDBPMatchResults(matchesCount: 0, brokerCount: 0)
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults = noResults
        NotificationCenter.default.post(name: .freemiumDBPResultPollingComplete, object: nil)
    }

    @objc
    func setFirstScanResultsNil() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults = nil
    }

    @objc
    func setNewTabPromotionDidDismissFalse() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didDismissHomePagePromotion = false
    }

    @objc
    func logAllState() {

        Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didActivate \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didActivate)")
        Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstProfileSavedTimestamp \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstProfileSavedTimestamp?.description ?? "Nil")")
        Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostFirstProfileSavedNotification \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostFirstProfileSavedNotification)")
        Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostResultsNotification \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostResultsNotification)")
        if let results = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults {
            Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults \(results.matchesCount) - \(results.brokerCount)")
        } else {
            Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults Nil")
        }
        Logger.freemiumDBP.debug("FREEMIUM DBP: DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didDismissHomePagePromotion \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didDismissHomePagePromotion)")

        if let override = UserDefaults.dbp.object(forKey: FreemiumDBPFeatureKeys.featureFlagOverride) as? Bool {
            Logger.freemiumDBP.debug("FREEMIUM DBP: FreemiumDBPFeatureKeys.featureFlagOverride: \(override)")
        } else {
            Logger.freemiumDBP.debug("FREEMIUM DBP: FreemiumDBPFeatureKeys.featureFlagOverride: Not Set")
        }
        if let override = UserDefaults.dbp.object(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride) as? Bool {
            Logger.freemiumDBP.debug("FREEMIUM DBP: FreemiumDBPFeatureKeys.usaStorefrontOverride: \(override)")
        } else {
            Logger.freemiumDBP.debug("FREEMIUM DBP: FreemiumDBPFeatureKeys.usaStorefrontOverride: Not Set")
        }
    }

    @objc
    func displayAllState() {
        let didActivate = "Activated: \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didActivate)"
        let firstProfileSavedTimestamp = "First Profile Saved Timestamp: \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstProfileSavedTimestamp?.description ?? "Nil")"
        let didPostFirstProfileSavedNotification = "Posted First Profile Saved Notification: \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostFirstProfileSavedNotification)"
        let didPostResultsNotification = "Posted Results Notification: \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didPostResultsNotification)"
        let firstScanResults = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).firstScanResults.map { "First Scan Results: \($0.matchesCount) matches, \($0.brokerCount) brokers" } ?? "First Scan Results: Nil"
        let didDismissHomePagePromotion = "Dismissed Home Page Promotion: \(DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).didDismissHomePagePromotion)"
        let featureFlagOverride = "Feature Flag Override: \(UserDefaults.dbp.object(forKey: FreemiumDBPFeatureKeys.featureFlagOverride) ?? "Not Set")"
        let storefrontOverride = "Storefront Override: \(UserDefaults.dbp.object(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride) ?? "Not Set")"

        let alert = NSAlert()
        alert.messageText = "State Information"
        alert.informativeText = """
        • \(didActivate)
        • \(firstProfileSavedTimestamp)
        • \(didPostFirstProfileSavedNotification)
        • \(didPostResultsNotification)
        • \(firstScanResults)
        • \(didDismissHomePagePromotion)
        • \(featureFlagOverride)
        • \(storefrontOverride)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    func resetAllState() {
        DefaultFreemiumDBPUserStateManager(userDefaults: .dbp).resetAllState()
    }

    // MARK: - Override Actions

    @objc func setFeatureFlagOverrideOn() {
        UserDefaults.dbp.set(true, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)
    }

    @objc func setFeatureFlagOverrideOff() {
        UserDefaults.dbp.set(false, forKey: FreemiumDBPFeatureKeys.featureFlagOverride)
    }

    @objc func resetFeatureFlagOverride() {
        UserDefaults.dbp.removeObject(forKey: FreemiumDBPFeatureKeys.featureFlagOverride)
    }

    @objc func setStorefrontOverrideOn() {
        UserDefaults.dbp.set(true, forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)
    }

    @objc func setStorefrontOverrideOff() {
        UserDefaults.dbp.set(false, forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)
    }

    @objc func resetStorefrontOverride() {
        UserDefaults.dbp.removeObject(forKey: FreemiumDBPFeatureKeys.usaStorefrontOverride)
    }

    @objc func resetAllOverrides() {
        resetFeatureFlagOverride()
        resetStorefrontOverride()
    }
}
