//
//  FeatureFlagOverridesMenu.swift
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
import BrowserServicesKit
import FeatureFlags
final class FeatureFlagOverridesMenu: NSMenu {
    let featureFlagger: FeatureFlagger
    let setInternalUserStateItem: NSMenuItem = {
        let item = NSMenuItem(title: "Set Internal User State First")
        item.isEnabled = false
        return item
    }()
    init(featureFlagOverrides: FeatureFlagger) {
        self.featureFlagger = featureFlagOverrides
        super.init(title: "")

        buildItems {
            internalUserStateMenuItem()
            NSMenuItem.separator()

            sectionHeader(title: "Legend")
            legend(title: "- Category has overridden flags", icon: Self.categoryHasOverriddenFlagsIcon)
            legend(title: "- Flag enabled by default", icon: Self.enabledByDefaultIcon)
            legend(title: "- Flag disabled by default", icon: Self.disabledByDefaultIcon)
            legend(title: "- Flag enabled by user", icon: Self.enabledByUserIcon)
            legend(title: "- Flag disabled by user", icon: Self.disabledByUserIcon)
            NSMenuItem.separator()

            sectionHeader(title: "Feature Flags")
            featureFlagMenuItems()
            NSMenuItem.separator()

            sectionHeader(title: "Experiments")
            experimentFeatureMenuItems()
            NSMenuItem.separator()
            resetAllOverridesMenuItem()
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu Item Builders

    private func internalUserStateMenuItem() -> NSMenuItem {
        return setInternalUserStateItem
    }

    private func featureFlagMenuItems() -> [NSMenuItem] {
        FeatureFlagCategory.allCases.sorted()
            .map { category in
                let menuItem = NSMenuItem(title: category.rawValue)
                menuItem.representedObject = category
                let submenu = NSMenu(title: category.rawValue)
                menuItem.submenu = submenu

                let flagItems = FeatureFlag.allCases
                    .filter {
                        $0.supportsLocalOverriding
                        && $0.cohortType == nil
                        && $0.category == category
                    }
                    .sorted { $0.rawValue.lowercased() < $1.rawValue.lowercased() }
                    .map { flag in
                        NSMenuItem(
                            title: menuItemTitle(for: flag),
                            action: #selector(toggleFeatureFlag(_:)),
                            target: self,
                            representedObject: flag)
                    }

                submenu.items = flagItems
                return menuItem
            }
    }

    private func experimentFeatureMenuItems() -> [NSMenuItem] {
        return FeatureFlag.allCases
            .filter { $0.supportsLocalOverriding && $0.cohortType != nil }
            .map { experiment in
                let experimentMenuItem = NSMenuItem(
                    title: self.experimentMenuItemTitle(for: experiment),
                    action: nil,
                    target: self,
                    representedObject: experiment
                )
                experimentMenuItem.submenu = cohortSubmenu(for: experiment)
                return experimentMenuItem
            }
    }

    private func resetAllOverridesMenuItem() -> NSMenuItem {
        return NSMenuItem(
            title: "Remove All Overrides",
            action: #selector(resetAllOverrides(_:)),
            target: self
        )
    }

    // MARK: - Menu Updates

    override func update() {
        super.update()
        update(items)
        setInternalUserStateItem.isHidden = featureFlagger.internalUserDecider.isInternalUser
    }

    private func update(_ items: [NSMenuItem]) {
        for item in items {
            if let category = item.representedObject as? FeatureFlagCategory {
                updateCategoryItem(item, category: category)
                continue
            }

            guard let flag = item.representedObject as? FeatureFlag else {
                continue
            }

            item.isHidden = !featureFlagger.internalUserDecider.isInternalUser

            if flag.cohortType == nil {
                updateFeatureFlagItem(item, flag: flag)
            } else {
                updateExperimentFeatureItem(item, flag: flag)
            }
        }
    }

    private func updateCategoryItem(_ item: NSMenuItem, category: FeatureFlagCategory) {
        item.image = icon(for: category)

        if let submenu = item.submenu {
            update(submenu.items)
        }
    }

    private func updateFeatureFlagItem(_ item: NSMenuItem, flag: FeatureFlag) {
        let override = featureFlagger.localOverrides?.override(for: flag)
        let submenu = NSMenu()
        submenu.addItem(removeOverrideSubmenuItem(for: flag))
        item.submenu = override != nil ? submenu : nil
        item.title = menuItemTitle(for: flag)
        item.image = icon(for: flag)
    }

    private func updateExperimentFeatureItem(_ item: NSMenuItem, flag: FeatureFlag) {
        let override = featureFlagger.localOverrides?.experimentOverride(for: flag)
        item.state = override != nil ? .on : .off
        item.submenu = cohortSubmenu(for: flag)
        item.title = experimentMenuItemTitle(for: flag)
    }

    // MARK: - Actions

    @objc func toggleFeatureFlag(_ sender: NSMenuItem) {
        guard let featureFlag = sender.representedObject as? FeatureFlag else { return }
        featureFlagger.localOverrides?.toggleOverride(for: featureFlag)
    }

    @objc func toggleExperimentFeatureFlag(_ sender: NSMenuItem) {
        guard let representedObject = sender.representedObject as? (FeatureFlag, String) else { return }
        let (experimentFeature, cohort) = representedObject
        featureFlagger.localOverrides?.setExperimentCohortOverride(for: experimentFeature, cohort: cohort)
    }

    @objc func resetOverride(_ sender: NSMenuItem) {
        guard let featureFlag = sender.representedObject as? FeatureFlag else { return }
        featureFlagger.localOverrides?.clearOverride(for: featureFlag)
    }

    @objc func resetAllOverrides(_ sender: NSMenuItem) {
        featureFlagger.localOverrides?.clearAllOverrides(for: FeatureFlag.self)
    }

    // MARK: - Helpers

    private func menuItemTitle(for flag: FeatureFlag) -> String {
        return "\(flag.rawValue)"
    }

    private func experimentMenuItemTitle(for flag: FeatureFlag) -> String {
        return "\(flag.rawValue) (default: \(defaultExperimentValue(for: flag)), override: \(experimentOverrideValue(for: flag)))"
    }

    // MARK: - Menu Icons

    private static let iconAlpha = 0.2

    private static var categoryHasOverriddenFlagsIcon = NSImage(systemSymbolName: "flag.fill",
                                                            accessibilityDescription: "Category has overridden flags")!

    private static var enabledByDefaultIcon = NSImage(systemSymbolName: "checkmark.circle",
                                                      accessibilityDescription: "Enabled by default")!

    private static var enabledByUserIcon = NSImage(systemSymbolName: "checkmark.circle.fill",
                                                   accessibilityDescription: "Enabled by user")!

    private static var disabledByDefaultIcon = NSImage(systemSymbolName: "x.circle",
                                                       accessibilityDescription: "Disabled by default")!

    private static var disabledByUserIcon = NSImage(systemSymbolName: "x.circle.fill",
                                                    accessibilityDescription: "Disabled by user")!

    private func icon(for category: FeatureFlagCategory) -> NSImage? {
        for flag in FeatureFlag.allCases {
            guard flag.supportsLocalOverriding
                && flag.cohortType == nil
                && flag.category == category else {

                continue
            }

            if overrideValue(for: flag) != nil {
                return Self.categoryHasOverriddenFlagsIcon
            }
        }

        return nil
    }

    private func icon(for flag: FeatureFlag) -> NSImage {
        if let override = overrideValue(for: flag) {
            if override {
                return Self.enabledByUserIcon
            } else {
                return Self.disabledByUserIcon
            }
        } else {
            if defaultValue(for: flag) {
                return Self.enabledByDefaultIcon
            } else {
                return Self.disabledByDefaultIcon
            }
        }
    }

    private func cohortSubmenu(for flag: FeatureFlag) -> NSMenu {
        let submenu = NSMenu()

        // Get the current override cohort
        let currentOverride = featureFlagger.localOverrides?.experimentOverride(for: flag)

        // Get all possible cohorts for this flag
        let cohorts = cohorts(for: flag)

        // Add cohort options
        for cohort in cohorts {
            let cohortItem = NSMenuItem(
                title: "Cohort: \(cohort.rawValue)",
                action: #selector(toggleExperimentFeatureFlag(_:)),
                target: self
            )
            cohortItem.representedObject = (flag, cohort.rawValue)

            // Mark the selected override with a checkmark
            cohortItem.state = (cohort.rawValue == currentOverride) ? .on : .off

            submenu.addItem(cohortItem)
        }

        submenu.addItem(NSMenuItem.separator())

        // "Remove Override" only if an override exists
        let removeOverrideItem = removeOverrideSubmenuItem(for: flag)
        removeOverrideItem.isHidden = currentOverride == nil

        submenu.addItem(removeOverrideItem)

        return submenu
    }

    private func removeOverrideSubmenuItem(for flag: FeatureFlag) -> NSMenuItem {
        let defaultValueString = defaultValue(for: flag) ? "ON" : "OFF"

        let removeOverrideItem = NSMenuItem(
            title: "Reset to default: \(defaultValueString)",
            action: #selector(resetOverride(_:)),
            target: self
        )
        removeOverrideItem.representedObject = flag
        removeOverrideItem.isHidden = featureFlagger.localOverrides?.override(for: flag) == nil
        return removeOverrideItem
    }

    private func cohorts<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> [any FeatureFlagCohortDescribing] {
        return featureFlag.cohortType?.cohorts ?? []
    }

    private func defaultValue(for flag: FeatureFlag) -> Bool {
        assert(flag.cohortType == nil)
        return featureFlagger.isFeatureOn(for: flag, allowOverride: false)
    }

    private func defaultExperimentValue(for flag: FeatureFlag) -> String {
        assert(flag.cohortType != nil)
        return featureFlagger.localOverrides?.currentExperimentCohort(for: flag)?.rawValue ?? "unassigned"
    }

    private func overrideValue(for flag: FeatureFlag) -> Bool? {
        assert(flag.cohortType == nil)
        return featureFlagger.localOverrides?.override(for: flag)
    }

    private func experimentOverrideValue(for flag: FeatureFlag) -> String {
        assert(flag.cohortType != nil)
        guard let override = featureFlagger.localOverrides?.experimentOverride(for: flag) else {
            return "none"
        }
        return override
    }

    private func sectionHeader(title: String) -> NSMenuItem {
        let headerItem = NSMenuItem(title: title)
        headerItem.isEnabled = false
        return headerItem
    }

    private func legend(title: String, icon: NSImage) -> NSMenuItem {
        let legendItem = NSMenuItem(title: title)
        legendItem.image = icon
        legendItem.isEnabled = false
        legendItem.indentationLevel = 1
        return legendItem
    }
}
