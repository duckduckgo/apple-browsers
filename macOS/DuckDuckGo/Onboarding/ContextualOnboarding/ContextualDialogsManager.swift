//
//  ContextualDialogsManager.swift
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

import Foundation
import Combine
import Persistence
import PrivacyDashboard

/// Represents the current state of onboarding.
enum ContextualOnboardingState: String {
    case notStarted
    case ongoing
    case onboardingCompleted
}

/// Enum representing various dialogs that may be shown during onboarding.
enum ContextualDialogType: Equatable {
    case tryASearch
    case searchDone(shouldFollowUp: Bool)
    case tryASite
    case trackers(message: NSAttributedString, shouldFollowUp: Bool)
    case tryFireButton
    case highFive
    case subscriptionUpsell
}

/// Protocol for providing the appropriate dialog type based on a Tab.
protocol ContextualOnboardingDialogTypeProviding {
    /// Returns a dialog type for the provided tab and  privacy information.
    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo?) -> ContextualDialogType?

    /// Returns the last dialog shown if it was shown for the given tab.
    func lastDialogForTab(_ tab: Tab) -> ContextualDialogType?

    /// The most recently selected dialog.
    var lastDialog: ContextualDialogType? { get }
}

/// Protocol to update the onboarding state (e.g., when the user uses the fire button or the feature is turned off).
protocol ContextualOnboardingStateUpdater: AnyObject {
    var state: ContextualOnboardingState { get set }
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { get }
    func gotItPressed()
    func fireButtonUsed()
    func turnOffFeature()
}

/// Protocol for storing onboarding state data.
protocol ContextualOnboardingStateStoring: AnyObject {
    /// Array of string representations of dialogs that have been shown.
    var contextualDialogsSeen: [String] { get set }

    /// Current contextual onboarding state stored as a string (notStarted, ongoing, completed).
    var stateString: String { get set }

    /// Flag indicating if the fire button has been used.
    var fireButtonUsedOnce: Bool { get set }
}

/// Concrete implementation of the state storage using property wrappers (backed by UserDefaults).
public class ContextualOnboardingStateStorage: ContextualOnboardingStateStoring {
    @UserDefaultsWrapper(key: .contextualOnboardingSeenDialogs, defaultValue: [])
    var contextualDialogsSeen: [String]

    @UserDefaultsWrapper(key: .contextualOnboardingState, defaultValue: ContextualOnboardingState.onboardingCompleted.rawValue)
    var stateString: String

    @UserDefaultsWrapper(key: .contextualOnboardingFireButtonUsed, defaultValue: false)
    var fireButtonUsedOnce: Bool
}

/// Main manager responsible for deciding which onboarding dialog to display based on the current state and tab.
public class ContextualDialogsManager: ObservableObject, ContextualOnboardingDialogTypeProviding, ContextualOnboardingStateUpdater {

    private let progress: ContextualOnboardingProgress
    private let makePath: (ContextualOnboardingPathKind) -> ContextualOnboardingPath

    /// The path chosen at the junction. No saved path means search.
    /// Built on first use, so a finished onboarding never builds one.
    private lazy var activePath: ContextualOnboardingPath = makePath(progress.pathKind ?? .search)

    // The last dialog that was presented.
    var lastDialog: ContextualDialogType?

    // The last tab for which a dialog was provided.
    private weak var lastTab: Tab?

    // Publisher for contextual onboarding completion
    @Published private(set) var isContextualOnboardingCompleted: Bool
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }

    var state: ContextualOnboardingState {
        get {
            progress.state
        }
        set {
            progress.state = newValue

            // Publish completion status
            let isCompleted = newValue == .onboardingCompleted
            if isContextualOnboardingCompleted != isCompleted {
                isContextualOnboardingCompleted = isCompleted
            }

            // If onboarding is restarted, clear all stored dialogs and flags.
            if newValue == .notStarted {
                activePath.reset()
                progress.reset()
                activePath = makePath(.search)
            }
        }
    }

    init(trackerMessageProvider: TrackerMessageProviding,
         subscriptionUpsellEligibility: OnboardingSubscriptionUpsellEligibilityChecking,
         stateStorage: ContextualOnboardingStateStoring = ContextualOnboardingStateStorage(),
         settings: any ThrowingKeyedStoring<ContextualOnboardingSettings> = Application.appDelegate.keyValueStore.throwingKeyedStoring(),
         makePath: ((ContextualOnboardingPathKind, ContextualOnboardingProgressReading) -> ContextualOnboardingPath)? = nil) {
        let progress = ContextualOnboardingProgress(storage: stateStorage, settings: settings)
        self.progress = progress
        self.makePath = { kind in
            if let makePath { return makePath(kind, progress) }
            switch kind {
            case .search:
                return SearchOnboardingPath(progress: progress,
                                            subscriptionUpsellEligibility: subscriptionUpsellEligibility,
                                            trackerMessageProvider: trackerMessageProvider)
            }
        }
        // Compares the raw value, as before: an unreadable saved value counts as not completed here.
        self.isContextualOnboardingCompleted = stateStorage.stateString == ContextualOnboardingState.onboardingCompleted.rawValue
    }

    // Returns the last dialog shown if it was shown for the given tab.
    func lastDialogForTab(_ tab: Tab) -> ContextualDialogType? {
        // If the provided tab is the same as the last tab we processed, return the stored last dialog.
        if tab == lastTab {
            return lastDialog
        }
        return nil
    }

    // Called when the user taps the "Got It" button present on some dialogs.
    public func gotItPressed() {
        guard let lastDialog else { return }
        switch activePath.gotItPressed(lastDialog: lastDialog) {
        case .next(let dialog):
            progress.markSeen(dialog)
            self.lastDialog = dialog
        case .completed:
            state = .onboardingCompleted
            self.lastDialog = nil
        case .none:
            break
        }
    }

    // Called when the user uses the fire button
    func fireButtonUsed() {
        progress.fireButtonUsedOnce = true
    }

    /// Whether the active path keeps the browser UI locked. Always false on the search path.
    var isUILocked: Bool {
        activePath.isUILocked
    }

    /// Called from the junction with the path the user picked.
    func startPath(_ kind: ContextualOnboardingPathKind) {
        progress.pathKind = kind
        activePath = makePath(kind)
        switch kind {
        case .search:
            // The user has just searched from the junction, so Try a search is skipped.
            progress.markSeen(.tryASearch)
        }
    }

    // Called to turn off the contextual onboarding.
    func turnOffFeature() {
        state = .onboardingCompleted
    }

    // Determines and returns which dialog should be shown for a given tab and privacy info.
    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo? = nil) -> ContextualDialogType? {
        // If onboarding is complete, return nil.
        guard state != .onboardingCompleted else { return nil }
        // If onboarding hasn't started, mark it as ongoing.
        if state == .notStarted { state = .ongoing }

        switch activePath.dialog(for: tab, privacyInfo: privacyInfo) {
        case .next(let dialog):
            progress.markSeen(dialog)
            lastDialog = dialog
            lastTab = tab
        case .none:
            lastDialog = nil
            lastTab = tab
        case .completed:
            state = .onboardingCompleted
            lastDialog = nil
        }
        return lastDialog
    }
}

// MARK: - ContextualDialogType Extension

// Extension to provide a common string representation for each dialog type, ignoring associated values.
extension ContextualDialogType {
    var stringRepresentation: String {
        switch self {
        case .tryASearch:
            return "tryASearch"
        case .searchDone:
            return "searchDone"
        case .tryASite:
            return "tryASite"
        case .trackers:
            return "trackers"
        case .tryFireButton:
            return "tryFireButton"
        case .highFive:
            return "highFive"
        case .subscriptionUpsell:
            return "subscriptionUpsell"
        }
    }

    static var defaultTrackers: ContextualDialogType {
        return .trackers(message: NSAttributedString(), shouldFollowUp: true)
    }
    static var defaultSearchDone: ContextualDialogType {
        return .searchDone(shouldFollowUp: true)
    }
}
