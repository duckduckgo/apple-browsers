//
//  DeclaredAgePrompt.swift
//  DuckDuckGo
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

import UIKit
import Combine
import BrowserServicesKit
import PrivacyConfig
import FeatureFlags_iOS

/// Presents Apple's Declared Age Range sheet as soon as a request is known to be needed.
@MainActor
final class DeclaredAgePrompt {

    private let requester: DeclaredAgeRequester
    private let featureFlagger: FeatureFlagger
    private var isRequestNeeded = false
    private var isPresenting = false
    private var pendingActions: [() -> Void] = []
    private weak var requestAnchor: UIViewController?
    private var cancellables = Set<AnyCancellable>()

    /// Returns nil while the request has to wait.
    var anchorProvider: (() -> UIViewController?)?

    init(requester: DeclaredAgeRequester, featureFlagger: FeatureFlagger) {
        self.requester = requester
        self.featureFlagger = featureFlagger

        startListeningToFeatureFlagger()
    }

    /// Returns whether the request is on screen, or was just started.
    @discardableResult
    func presentIfNeeded() -> Bool {
        guard !isPresenting else {
            return true
        }

        guard isRequestNeeded, featureFlagger.isFeatureOn(.declaredAgeRange) else {
            return false
        }

        return present()
    }

    /// Presents regardless of whether a request is needed. Returns whether the request was started.
    @discardableResult
    func present() -> Bool {
        guard !isPresenting else {
            return true
        }

        guard let anchor = anchorProvider?() else {
            return false
        }

        // Success or failure, the next attempt waits for the next launch.
        isRequestNeeded = false
        isPresenting = true
        requestAnchor = anchor

        Task {
            _ = await requester.requestDeclaredAge(in: anchor)
            isPresenting = false
            performPendingActions()
        }

        return true
    }

    /// Runs `action` once the request on screen finishes. Returns false, keeping nothing, when none is.
    func runOnceRequestFinishes(_ action: @escaping () -> Void) -> Bool {
        guard isPresenting else {
            return false
        }

        pendingActions.append(action)
        return true
    }

    /// Apple can drop its sheet in the background without finishing the request, so it's given up once the sheet is gone.
    func handleAppForegrounded() {
        guard isPresenting, requestAnchor?.presentedViewController == nil else {
            return
        }

        isPresenting = false
        pendingActions = []
    }
}

private extension DeclaredAgePrompt {

    func startListeningToFeatureFlagger() {
        let featureFlagsDidChange = featureFlagger.updatesPublisher
        let internalUserDidChange = featureFlagger.internalUserDecider.isInternalUserPublisher.map { _ in }

        // The flag doubles as a kill switch, so Apple's API isn't touched until the first time it's on.
        Publishers.Merge(featureFlagsDidChange, internalUserDidChange)
            .prepend(())
            .receive(on: DispatchQueue.main)
            .first { [featureFlagger] in
                featureFlagger.isFeatureOn(.declaredAgeRange)
            }
            .sink { [weak self] in
                Task {
                    await self?.refreshIsRequestNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func performPendingActions() {
        let actions = pendingActions
        pendingActions = []

        actions.forEach { $0() }
    }

    func refreshIsRequestNeeded() async {
        // A failed check stores nothing, so the next launch retries.
        guard let isNeeded = try? await requester.isRequestNeeded() else {
            return
        }

        // A reinstall wipes the stored date, so it needs no separate signal on iOS.
        isRequestNeeded = isNeeded

        guard isNeeded else {
            requester.markNotRequired()
            return
        }

        presentIfNeeded()
    }
}
