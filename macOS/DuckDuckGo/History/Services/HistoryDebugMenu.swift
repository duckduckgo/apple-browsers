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
import History
import PrivacyConfig
import UniformTypeIdentifiers
import ZIPFoundation

final class HistoryDebugMenu: NSMenu {

    let historyCoordinator: HistoryCoordinating
    let featureFlagger: FeatureFlagger

    private let environmentMenu = NSMenu()

    init(historyCoordinator: HistoryCoordinating, featureFlagger: FeatureFlagger) {
        self.historyCoordinator = historyCoordinator
        self.featureFlagger = featureFlagger

        super.init(title: "")

        buildItems {
            NSMenuItem(
                title: "Add 10 history visits each day (10 domains)",
                action: #selector(populateFakeHistory),
                target: self,
                representedObject: (10, FakeURLsPool.random10Domains)
            ).withAccessibilityIdentifier("HistoryDebugMenu.populate10")
            NSMenuItem(
                title: "Add 100 history visits each day (10 domains)",
                action: #selector(populateFakeHistory),
                target: self,
                representedObject: (100, FakeURLsPool.random10Domains)
            ).withAccessibilityIdentifier("HistoryDebugMenu.populate100")
            NSMenuItem(
                title: "Add 100 history visits each day (200 domains – SLOW!)",
                action: #selector(populateFakeHistory),
                target: self,
                representedObject: (100, FakeURLsPool.random200Domains)
            ).withAccessibilityIdentifier("HistoryDebugMenu.populate100slow")

            NSMenuItem.separator()

            NSMenuItem(
                title: "Import Safari History…",
                action: #selector(importSafariHistory),
                target: self
            ).withAccessibilityIdentifier("HistoryDebugMenu.importSafariHistory")
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func populateFakeHistory(_ sender: NSMenuItem) {
        guard let (maxVisitsPerDay, pool) = sender.representedObject as? (Int, FakeURLsPool) else {
            return
        }
        DispatchQueue.main.async {
            self.populateHistory(maxVisitsPerDay, pool.urls)
        }
    }

    @MainActor
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

    @MainActor
    @objc func importSafariHistory(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.message = "Select a Safari export (.zip) or its History.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor in
            do {
                let parseResult = try await Task.detached {
                    try SafariHistoryImporter.parse(Self.historyJSONData(at: url))
                }.value
                let summary = try await SafariHistoryImporter.importVisits(parseResult, into: historyCoordinator)
                showAlert(title: "Safari History Imported",
                          message: """
                          Imported: \(summary.imported)
                          Already in history: \(summary.alreadyInHistory)
                          Older than a month: \(summary.tooOld)
                          Skipped (redirects, failed loads, non-web URLs): \(summary.skipped)
                          """)
            } catch {
                showAlert(title: "Safari History Import Failed", message: "\(error)")
            }
        }
    }

    private static func historyJSONData(at url: URL) throws -> Data {
        guard url.pathExtension.lowercased() == "zip" else {
            return try Data(contentsOf: url)
        }

        let archive = try Archive(url: url, accessMode: .read)
        // Skip the AppleDouble copies Finder adds under __MACOSX/ when re-zipping.
        guard let entry = archive.first(where: { entry in
            let path = entry.path as NSString
            return entry.type == .file
                && !entry.path.hasPrefix("__MACOSX/")
                && path.lastPathComponent.lowercased() == "history.json"
        }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
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
