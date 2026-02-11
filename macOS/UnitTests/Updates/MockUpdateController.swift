//
//  MockUpdateController.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

@testable import DuckDuckGo_Privacy_Browser

/// Mock UpdateController for testing - fully implements the protocol.
public class MockUpdateController: UpdateController {

    @Published public var latestUpdate: Update?
    @Published public var hasPendingUpdate: Bool = false
    @Published public var updateProgress: UpdateCycleProgress = .updateCycleNotStarted

    public var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }
    public var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }
    public var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    public var needsNotificationDot: Bool = false
    public var notificationDotPublisher: AnyPublisher<Bool, Never> {
        Just(needsNotificationDot).eraseToAnyPublisher()
    }

    public var lastUpdateCheckDate: Date?
    public var lastUpdateNotificationShownDate: Date = Date()
    public var areAutomaticUpdatesEnabled: Bool = false
    public var notificationPresenter: UpdateNotificationPresenting = MockNotificationPresenter()
    public var isAtRestartCheckpoint: Bool = false
    public var shouldForceUpdateCheck: Bool = false
    public var willRelaunchAppPublisher: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()
    public var useLegacyAutoRestartLogic: Bool = false
    public var mustShowUpdateIndicators: Bool = false
    public var clearsNotificationDotOnMenuOpen: Bool = false

    // Track method calls for testing
    public var runUpdateCalled = false
    public var checkForUpdateSkippingRolloutCalled = false
    public var checkForUpdateRespectingRolloutCalled = false
    public var checkNewApplicationVersionIfNeededCalled = false
    public var runUpdateFromMenuItemCalled = false
    public var openUpdatesPageCalled = false
    public var resetLastUpdateCheckDateCalled = false
    public var logCalled = false
    public var setUpdateCheckingEnabledCalled = false
    public var handleAppTerminationCalled = false

    required public init(internalUserDecider: InternalUserDecider,
                         featureFlagger: FeatureFlagger,
                         pixelFiring: PixelFiring?,
                         notificationPresenter: UpdateNotificationPresenting,
                         keyValueStore: ThrowingKeyValueStoring,
                         buildType: ApplicationBuildType?,
                         wideEvent: WideEventManaging?,
                         isOnboardingFinished: @escaping () -> Bool) {
        fatalError("Use init() for testing")
    }

    public init() {}

    public func runUpdate() {
        runUpdateCalled = true
    }

    public func checkForUpdate() {
        checkForUpdateSkippingRolloutCalled = true
    }

    public func checkForUpdateSkippingRollout() {
        checkForUpdateSkippingRolloutCalled = true
    }

    public func checkForUpdateRespectingRollout() {
        checkForUpdateRespectingRolloutCalled = true
    }

    public func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress) {
        checkNewApplicationVersionIfNeededCalled = true
    }

    public func runUpdateFromMenuItem() {
        runUpdateFromMenuItemCalled = true
    }

    public func openUpdatesPage() {
        openUpdatesPageCalled = true
    }

    public func resetLastUpdateCheckDate() {
        resetLastUpdateCheckDateCalled = true
        lastUpdateCheckDate = nil
    }

    public func log() {
        logCalled = true
    }

    public func setUpdateCheckingEnabled(_ enabled: Bool) {
        setUpdateCheckingEnabledCalled = true
        areAutomaticUpdatesEnabled = enabled
    }

    public func handleAppTermination() {
        handleAppTerminationCalled = true
    }

}
