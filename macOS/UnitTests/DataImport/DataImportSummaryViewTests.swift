//
//  DataImportSummaryViewTests.swift
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

import AppKit
import BrowserServicesKit
import DesignResourcesKit
import FeatureFlags_macOS
import PrivacyConfig
import SnapshotTestingSupport
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Data Import Summary View Tests")
final class DataImportSummaryViewTests {
    private struct ImportFlowRelauncherMock: DataImportFlowRelaunching {
        func relaunchDataImport(model: DataImportViewModel) {}
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testSummaryWithBookmarksPasswordsAndHistorySnapshot() {
        let palette = DesignSystemPalette.current
        DesignSystemPalette.current = .default
        defer { DesignSystemPalette.current = palette }
        let appearancePreferences = NSApp.delegateTyped.appearancePreferences
        let showBookmarksBar = appearancePreferences.showBookmarksBar
        appearancePreferences.showBookmarksBar = false
        defer { appearancePreferences.showBookmarksBar = showBookmarksBar }
        let view = summaryView(for: [
            .bookmarks: .success(.init(successful: 32, duplicate: 0, failed: 0)),
            .passwords: .success(.init(successful: 23, duplicate: 0, failed: 0)),
            .history: .success(.init(successful: 265, duplicate: 0, failed: 0))
        ])

        assertImageSnapshot(matching: view, size: .intrinsicContentSize)
    }

    private func summaryView(for summary: DataImportSummary) -> DataImportView {
        let syncFeatureVisibility = SyncFeatureVisibility.show(syncLauncher: MockSyncDeviceFlowLauncher())
        let model = DataImportViewModel(
            importSource: .chrome,
            screen: .summary(summary),
            availableImportSources: [.chrome],
            isPasswordManagerAutolockEnabled: true,
            syncFeatureVisibility: syncFeatureVisibility,
            loadProfiles: { .init(browser: $0, profiles: []) },
            featureFlagger: historyImportFeatureFlagger(),
            pixelFiring: nil
        )
        return DataImportView(
            model: model,
            importFlowLauncher: ImportFlowRelauncherMock(),
            syncFeatureVisibility: syncFeatureVisibility,
            pinningManager: MockPinningManager()
        )
    }

    private func historyImportFeatureFlagger() -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.dataImportHistory.rawValue] = true
        return featureFlagger
    }
}
