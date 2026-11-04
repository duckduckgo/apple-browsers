//
//  AppStoreUpdateControllerPromptStageTests.swift
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

import AppUpdaterShared
import AppUpdaterTestHelpers
import Combine
import Common
import FeatureFlags_macOS
import Foundation
import FoundationExtensions
@_spi(Testing) import Persistence
import PrivacyConfig
import Testing

@testable import AppStoreAppUpdater

@MainActor
@Suite("AppStoreUpdateController prompt stages", .serialized)
final class AppStoreUpdateControllerPromptStageTests {

    private static let newerVersion = "9999.0.0"
    private static let olderVersion = "0.0.1"

    private let featureFlagger = MockFeatureFlagger()
    private let releaseDate = Date(timeIntervalSince1970: 1_793_207_100)
    private lazy var now = releaseDate
    private lazy var tracker = UpdatePromptStageTracker(
        store: InMemoryThrowingKeyValueStore().throwingKeyedStoring(),
        settings: { MoreProminentUpdatesSettings(.external) },
        installedVersion: "1.0.0",
        now: { [unowned self] in now },
        schedule: { _, _ in AnyCancellable {} },
        reevaluationTriggers: Empty().eraseToAnyPublisher()
    )

    init() {
        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = true
    }

    deinit {
        StubURLProtocol.json = nil
    }

    private func makeController() -> AppStoreUpdateController {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return AppStoreUpdateController(featureFlagger: featureFlagger,
                                        updatePromptStageTracker: tracker,
                                        releaseChecker: LatestReleaseChecker(baseURL: "https://test.example.com/",
                                                                             urlSession: URLSession(configuration: configuration)),
                                        notificationPresenter: MockNotificationPresenter(),
                                        appVersion: AppVersion(bundle: InstalledVersionBundle()),
                                        now: { [unowned self] in now })
    }

    private func publish(latest: String, available: String, availableIsCritical: Bool = false) {
        StubURLProtocol.json = """
        {
            "latest_appstore_version": {"latest_version": "\(latest)", "build_number": 1, "release_date": "2026-10-01T17:00:00Z", "is_critical": false},
            "available_appstore_version": {"latest_version": "\(available)", "build_number": 1, "release_date": "2026-10-28T17:05:00Z", "is_critical": \(availableIsCritical)}
        }
        """
    }

    @available(iOS 16, macOS 13, *)
    @Test("Offers a rolling-out release once the buffer has passed and starts the prompt clock", .timeLimit(.minutes(1)))
    func offersAvailableReleaseAfterBuffer() async {
        publish(latest: Self.olderVersion, available: Self.newerVersion)
        now = releaseDate + .hours(24)
        let controller = makeController()

        await controller.performUpdateCheck(dismissRateLimiting: true)

        #expect(controller.hasPendingUpdate)
        #expect(controller.latestUpdate?.version == Self.newerVersion)
        #expect(tracker.stage == .available)
        #expect(tracker.clockStartDate == now)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Doesn't offer a rolling-out release during the buffer", .timeLimit(.minutes(1)))
    func holdsBackAvailableReleaseDuringBuffer() async {
        publish(latest: Self.olderVersion, available: Self.newerVersion)
        now = releaseDate + .hours(23)
        let controller = makeController()

        await controller.performUpdateCheck(dismissRateLimiting: true)

        #expect(!controller.hasPendingUpdate)
        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Critical releases still wait for the buffer, then go straight to the second prompt", .timeLimit(.minutes(1)))
    func criticalReleaseSkipsToSecondPromptAfterBuffer() async {
        publish(latest: Self.olderVersion, available: Self.newerVersion, availableIsCritical: true)
        let controller = makeController()

        now = releaseDate + .hours(23)
        await controller.performUpdateCheck(dismissRateLimiting: true)
        #expect(tracker.stage == .none)

        now = releaseDate + .hours(24)
        await controller.performUpdateCheck(dismissRateLimiting: true)
        #expect(tracker.stage == .secondPrompt)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off, ignores the rolling-out release and starts no prompt clock", .timeLimit(.minutes(1)))
    func flagOffIgnoresAvailableRelease() async {
        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        publish(latest: Self.olderVersion, available: Self.newerVersion)
        now = releaseDate + .hours(100)
        let controller = makeController()

        await controller.performUpdateCheck(dismissRateLimiting: true)

        #expect(!controller.hasPendingUpdate)
        #expect(tracker.clockStartDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag off clears the prompt clock, so turning it back on starts again from day 0", .timeLimit(.minutes(1)))
    func flagOffClearsPromptClock() async {
        publish(latest: Self.olderVersion, available: Self.newerVersion)
        now = releaseDate + .hours(24)
        let controller = makeController()
        await controller.performUpdateCheck(dismissRateLimiting: true)
        #expect(tracker.clockStartDate == now)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = false
        now += .hours(72)
        await controller.performUpdateCheck(dismissRateLimiting: true)
        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)

        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = true
        now += .hours(1)
        await controller.performUpdateCheck(dismissRateLimiting: true)
        #expect(tracker.stage == .available)
        #expect(tracker.clockStartDate == now)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Opening the menu clears the notification dot only while the flag is off", .timeLimit(.minutes(1)), arguments: [true, false])
    func menuClearsDotOnlyWithFlagOff(isFlagOn: Bool) {
        featureFlagger.featuresStub[FeatureFlag.moreProminentUpdates.rawValue] = isFlagOn

        #expect(makeController().clearsNotificationDotOnMenuOpen == !isFlagOn)
    }
}

private struct InstalledVersionBundle: InfoBundle {
    func object(forInfoDictionaryKey key: String) -> Any? {
        [Bundle.Key.versionNumber: "1.0.0", Bundle.Key.buildNumber: "1"][key]
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var json: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.json ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
