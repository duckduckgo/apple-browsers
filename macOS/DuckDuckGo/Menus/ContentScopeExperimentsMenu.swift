//
//  ContentScopeExperimentsMenu.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class ContentScopeExperimentsMenu: NSMenu, NSMenuDelegate {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let contentScopeExperimentsManager: ContentScopeExperimentsManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager,
         contentScopeExperimentsManager: ContentScopeExperimentsManaging = NSApp.delegateTyped.contentScopeExperimentsManager) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.contentScopeExperimentsManager = contentScopeExperimentsManager
        super.init(title: "Content Scope Experiments")
        self.delegate = self
        self.autoenablesItems = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        removeAllItems()

        let enrolledExperiments = contentScopeExperimentsManager.allActiveContentScopeExperiments

        guard let configData = try? PrivacyConfigurationData(data: privacyConfigurationManager.currentConfig),
              let cssFeature = configData.features["contentScopeExperiments"],
              !cssFeature.features.isEmpty else {
            let noExperimentsItem = NSMenuItem(title: "No experiments in config", action: nil, keyEquivalent: "")
            noExperimentsItem.isEnabled = false
            addItem(noExperimentsItem)
            return
        }

        for (name, subfeature) in cssFeature.features.sorted(by: { $0.key < $1.key }) {
            let enrollment = enrolledExperiments[name]
            let menuItem = createExperimentMenuItem(name: name, subfeature: subfeature, enrollment: enrollment)
            addItem(menuItem)
        }
    }

    private func createExperimentMenuItem(name: String,
                                          subfeature: PrivacyConfigurationData.PrivacyFeature.Feature,
                                          enrollment: ExperimentData?) -> NSMenuItem {
        let menuItem = NSMenuItem()

        // Build attributed title with name and subtitle
        let title = NSMutableAttributedString()

        // Enrollment indicator
        let indicator = enrollment != nil ? "✓ " : "○ "
        let indicatorColor = enrollment != nil ? NSColor.systemGreen : NSColor.secondaryLabelColor
        title.append(NSAttributedString(
            string: indicator,
            attributes: [.foregroundColor: indicatorColor, .font: NSFont.systemFont(ofSize: 13)]
        ))

        // Experiment name
        title.append(NSAttributedString(
            string: name,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]
        ))

        // Subtitle line
        var subtitleParts: [String] = []
        subtitleParts.append(subfeature.state)

        if let cohorts = subfeature.cohorts {
            subtitleParts.append("cohorts: \(cohorts.map { $0.name }.joined(separator: "/"))")
        }

        if let rollout = subfeature.rollout?.steps.last?.percent {
            subtitleParts.append("\(rollout)%")
        }

        if let enrollment = enrollment {
            subtitleParts.append("enrolled: \(enrollment.cohortID)")
        }

        let subtitle = "\n    " + subtitleParts.joined(separator: " · ")
        title.append(NSAttributedString(
            string: subtitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))

        menuItem.attributedTitle = title
        menuItem.isEnabled = false  // Info only, not actionable

        return menuItem
    }
}
