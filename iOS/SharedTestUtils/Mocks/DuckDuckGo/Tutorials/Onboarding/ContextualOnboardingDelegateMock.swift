//
//  ContextualOnboardingDelegateMock.swift
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

import Foundation
@testable import DuckDuckGo

final class ContextualOnboardingDelegateMock: ContextualOnboardingDelegate {
    private(set) var didCallDidShowContextualOnboardingTrackersDialog = false
    private(set) var didCallDidAcknowledgeContextualOnboardingTrackersDialog = false
    private(set) var didCallDidTapDismissContextualOnboardingAction = false
    private(set) var didCallSearchForQuery = false
    private(set) var didCallNavigateToURL = false
    private(set) var didCallDidAcknowledgeContextualOnboardingSearch = false
    private(set) var urlToNavigateTo: URL?

    func didShowContextualOnboardingTrackersDialog() {
        didCallDidShowContextualOnboardingTrackersDialog = true
    }

    func didAcknowledgeContextualOnboardingTrackersDialog() {
        didCallDidAcknowledgeContextualOnboardingTrackersDialog = true
    }

    func didTapDismissContextualOnboardingAction() {
        didCallDidTapDismissContextualOnboardingAction = true
    }

    func searchFromOnboarding(for query: String) {
        didCallSearchForQuery = true
    }

    func navigateFromOnboarding(to url: URL) {
        didCallNavigateToURL = true
        urlToNavigateTo = url
    }

    func didAcknowledgeContextualOnboardingSearch() {
        didCallDidAcknowledgeContextualOnboardingSearch = true
    }

}
