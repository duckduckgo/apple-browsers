//
//  HistoryDebugMenu.swift
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
import History

final class HistoryDebugMenu: NSMenu {

    let historyCoordinator: HistoryCoordinating
    let featureFlagger: FeatureFlagger
    let resetMenuItem: NSMenuItem
    let showMenuItem: NSMenuItem

    private let environmentMenu = NSMenu()

    init(historyCoordinator: HistoryCoordinating, featureFlagger: FeatureFlagger) {
        self.historyCoordinator = historyCoordinator
        self.featureFlagger = featureFlagger
        resetMenuItem = NSMenuItem(title: "Reset History View Onboarding", action: #selector(resetHistoryViewOnboarding))
        showMenuItem = NSMenuItem(title: "Show History View Onboarding", action: #selector(showHistoryViewOnboarding))

        super.init(title: "")
        resetMenuItem.target = self
        showMenuItem.target = self

        buildItems {
            NSMenuItem(
                title: "Add 10 history visits each day (10 domains)",
                action: #selector(populateFakeHistory),
                target: self,
                representedObject: (10, FakeURLsPool.random10Domains)
            )
            NSMenuItem(
                title: "Add 100 history visits each day (10 domains)",
                action: #selector(populateFakeHistory),
                target: self,
                representedObject: (100, FakeURLsPool.random10Domains)
            )
            NSMenuItem(
                title: "Add 100 history visits each day (200 domains – SLOW!)",
                action: #selector(populateFakeHistory),
                target: self,
                representedObject: (100, FakeURLsPool.random200Domains)
            )

            NSMenuItem.separator()
            resetMenuItem
            showMenuItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        super.update()

        let isHistoryViewEnabled = featureFlagger.isFeatureOn(.historyView)
        resetMenuItem.isHidden = !isHistoryViewEnabled
        showMenuItem.isHidden = !isHistoryViewEnabled
    }

    @objc func populateFakeHistory(_ sender: NSMenuItem) {
        guard let (maxVisitsPerDay, pool) = sender.representedObject as? (Int, FakeURLsPool) else {
            return
        }
        Task.detached {
            self.populateHistory(maxVisitsPerDay, pool.urls)
        }
    }

    private func populateHistory(_ maxVisitsPerDay: Int, _ urls: [URL]) {
        var date = Date()
        let endDate = Date.monthAgo

        var visitsPerDay = 0

        while date > endDate {
            guard let url = urls.randomElement() else {
                continue
            }
            let visitDate = Date(timeIntervalSince1970: TimeInterval.random(in: date.startOfDay.timeIntervalSince1970..<date.timeIntervalSince1970))
            historyCoordinator.addVisit(of: url, at: visitDate)
            historyCoordinator.updateTitleIfNeeded(title: url.path.dropping(prefix: "/"), url: url)
            visitsPerDay += 1
            if visitsPerDay >= maxVisitsPerDay {
                date = date.daysAgo(1)
                visitsPerDay = 0
            }
        }
    }

    @objc func resetHistoryViewOnboarding() {
        let persistor = UserDefaultsHistoryViewOnboardingViewSettingsPersistor()
        persistor.didShowOnboardingView = false
    }

    @MainActor
    @objc func showHistoryViewOnboarding() {
        resetHistoryViewOnboarding()
        WindowControllersManager.shared.lastKeyMainWindowController?
            .mainViewController
            .navigationBarViewController
            .presentHistoryViewOnboardingIfNeeded(force: true)
    }

    enum FakeURLsPool {
        case random10Domains
        case random200Domains

        var urls: [URL] {
            switch self {
            case .random10Domains:
                Self.fakeURLs10Domains
            case .random200Domains:
                Self.fakeURLs200Domains
            }
        }

        private static let fakeURLs10Domains: [URL] = generateFakeURLs(numberOfDomains: 10)
        private static let fakeURLs200Domains: [URL] = generateFakeURLs(numberOfDomains: 200)

        private static func generateFakeURLs(numberOfDomains: Int) -> [URL] {
            (0..<numberOfDomains).flatMap { _ in
                let hostname = UUID().uuidString.lowercased().prefix(8)
                return (1...3).map { i in
                    "https://\(hostname).com/index\(i).html".url!
                }
            }
        }
    }

}
