//
//  AppStoreReleasesTests.swift
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

import AppStoreAppUpdater
import AppUpdaterShared
import Foundation
import FoundationExtensions
import Testing

@Suite("AppStoreReleases")
struct AppStoreReleasesTests {

    private let latest = ReleaseMetadata(latestVersion: "1.156.0", buildNumber: 540, releaseDate: "2026-10-01T17:00:00Z", isCritical: false)
    private let available = ReleaseMetadata(latestVersion: "1.157.0", buildNumber: 541, releaseDate: "2026-10-28T17:05:00Z", isCritical: false)
    private let availableReleaseDate = Date(timeIntervalSince1970: 1_793_207_100)

    @available(iOS 16, macOS 13, *)
    @Test("Offers the available release only once the delay has passed since its release date", .timeLimit(.minutes(1)), arguments: [
        (TimeInterval.hours(24) - 1, "1.156.0"),
        (.hours(24), "1.157.0")
    ])
    func offersAvailableReleaseAfterDelay(sinceRelease: TimeInterval, expectedVersion: String) {
        let releases = AppStoreReleases(latest: latest, available: available)

        let offered = releases.releaseToOffer(availableAfter: .hours(24), now: availableReleaseDate.addingTimeInterval(sinceRelease))

        #expect(offered.latestVersion == expectedVersion)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Offers the latest release when the available release isn't newer than it", .timeLimit(.minutes(1)), arguments: [
        ("1.155.0", 541),
        ("1.156.0", 539),
        ("1.156.0", 540)
    ])
    func offersLatestOverStaleAvailableRelease(availableVersion: String, availableBuild: Int) {
        let stale = ReleaseMetadata(latestVersion: availableVersion, buildNumber: availableBuild, releaseDate: "2026-10-28T17:05:00Z", isCritical: false)
        let releases = AppStoreReleases(latest: latest, available: stale)

        let offered = releases.releaseToOffer(availableAfter: 0, now: availableReleaseDate)

        #expect(offered.latestVersion == "1.156.0")
        #expect(offered.buildNumber == 540)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Offers a rebuilt available release with the same version as the latest", .timeLimit(.minutes(1)))
    func offersNewerBuildOfSameVersion() {
        let rebuilt = ReleaseMetadata(latestVersion: "1.156.0", buildNumber: 541, releaseDate: "2026-10-28T17:05:00Z", isCritical: false)
        let releases = AppStoreReleases(latest: latest, available: rebuilt)

        #expect(releases.releaseToOffer(availableAfter: 0, now: availableReleaseDate).buildNumber == 541)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Compares version components numerically", .timeLimit(.minutes(1)))
    func comparesVersionComponentsNumerically() {
        let older = ReleaseMetadata(latestVersion: "1.9.0", buildNumber: 900, releaseDate: "2026-10-01T17:00:00Z", isCritical: false)
        let newer = ReleaseMetadata(latestVersion: "1.10.0", buildNumber: 100, releaseDate: "2026-10-28T17:05:00Z", isCritical: false)

        #expect(AppStoreReleases(latest: older, available: newer).releaseToOffer(availableAfter: 0, now: availableReleaseDate).latestVersion == "1.10.0")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Offers the latest release when no release is rolling out", .timeLimit(.minutes(1)))
    func offersLatestWithoutAvailableRelease() {
        let releases = AppStoreReleases(latest: latest, available: nil)

        #expect(releases.releaseToOffer(availableAfter: 0, now: availableReleaseDate).latestVersion == "1.156.0")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Offers the latest release when the available release date can't be read", .timeLimit(.minutes(1)))
    func offersLatestForUnreadableReleaseDate() {
        let undated = ReleaseMetadata(latestVersion: "1.157.0", buildNumber: 541, releaseDate: "28 October", isCritical: false)
        let releases = AppStoreReleases(latest: latest, available: undated)

        #expect(releases.releaseToOffer(availableAfter: 0, now: availableReleaseDate).latestVersion == "1.156.0")
    }
}
