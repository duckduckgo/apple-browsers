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
    func gotItPressed()
    func fireButtonUsed()
    func turnOffFeature()
}

/// Protocol for storing onboarding state data.
protocol ContextualOnboardingStateStoring {
    /// Array of string representations of dialogs that have been shown.
    var contextualDialogsSeen: [String] { get set }

    /// Current contextual onboarding state stored as a string (notStarted, ongoing, completed).
    var stateString: String { get set }

    /// Flag indicating if a blocked tracker dialog has been shown.
    var blockedTrackerSeen: Bool { get set }

    /// Flag indicating if the fire button has been used.
    var fireButtonUsedOnce: Bool { get set }
}

/// Concrete implementation of the state storage using property wrappers (backed by UserDefaults).
public class ContextualOnboardingStateStorage: ContextualOnboardingStateStoring {
    @UserDefaultsWrapper(key: .contextualOnboardingSeenDialogs, defaultValue: [])
    var contextualDialogsSeen: [String]

    @UserDefaultsWrapper(key: .contextualOnboardingState, defaultValue: ContextualOnboardingState.onboardingCompleted.rawValue)
    var stateString: String

    @UserDefaultsWrapper(key: .contextualOnboardingBlockedTrackers, defaultValue: false)
    var blockedTrackerSeen: Bool

    @UserDefaultsWrapper(key: .contextualOnboardingFireButtonUsed, defaultValue: false)
    var fireButtonUsedOnce: Bool
}

/// Main manager responsible for deciding which onboarding dialog to display based on the current state and tab.
public class ContextualDialogsManager: ContextualOnboardingDialogTypeProviding, ContextualOnboardingStateUpdater {

    private let trackerMessageProvider: TrackerMessageProviding
    private var stateStorage: ContextualOnboardingStateStoring

    // The last dialog that was presented.
    var lastDialog: ContextualDialogType?

    // The last tab for which a dialog was provided.
    private weak var lastTab: Tab?

    // Computed property for managing state.
    var state: ContextualOnboardingState {
        get {
            return ContextualOnboardingState(rawValue: stateStorage.stateString) ?? .onboardingCompleted
        }
        set {
            // Update persistent state.
            stateStorage.stateString = newValue.rawValue
            // If onboarding is restarted, clear all stored dialogs and flags.
            if state == ContextualOnboardingState.notStarted {
                stateStorage.contextualDialogsSeen = []
                stateStorage.fireButtonUsedOnce = false
                stateStorage.blockedTrackerSeen = false
            }
        }
    }

    init(trackerMessageProvider: TrackerMessageProviding = TrackerMessageProvider(),
         stateStorage: ContextualOnboardingStateStoring = ContextualOnboardingStateStorage()) {
        self.trackerMessageProvider = trackerMessageProvider
        self.stateStorage = stateStorage
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
        // Update state based on the type of dialog that was last shown.
        switch lastDialog {
        case .searchDone(shouldFollowUp: true)?:
            // When user press got it "searchDone" dialog it will automatically show "tryASite" therefore we mark it as seen and as lastDialog
            markSeen(.tryASite)
            lastDialog = .tryASite
        case .trackers?:
            // When user press got it "trackers" dialog it will automatically show "tryFireButton" therefore we mark it as seen and as lastDialog
            markSeen(.tryFireButton)
            lastDialog = .tryFireButton
        case .highFive?:
            // If highFive dialog, complete onboarding.
            state = .onboardingCompleted
            lastDialog = nil
        default:
            break
        }
    }

    // Called when the user uses the fire button
    func fireButtonUsed() {
        stateStorage.fireButtonUsedOnce = true
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
        // If a highFive has already been seen, conclude onboarding (it's just for extra safety).
        if hasSeen(.highFive) {
            state = .onboardingCompleted
            return nil
        }

        var selectedDialog: ContextualDialogType?
        // Determine which dialog to show based on the type of tab.
        switch tab.content {
        case .newtab:
            selectedDialog = dialogForNewTab()
        case .url(let url, _, _):
            // Check if the URL is a DuckDuckGo search.
            if url.isDuckDuckGoSearch {
                selectedDialog = dialogForDuckDuckGoSearch()
            } else {
                // For website visit, decide dialog also based on the tracker type.
                let trackerType = trackerMessageProvider.trackersType(privacyInfo: tab.privacyInfo)
                selectedDialog = dialogForRegularUrl(trackerType: trackerType, privacyInfo: privacyInfo)
            }
        default:
            selectedDialog = nil
        }

        // If highFive is the selected dialog, end onboarding.
        if let dialog = selectedDialog, dialog == .highFive {
            state = .onboardingCompleted
        }
        // Mark the dialog as seen.
        if let dialog = selectedDialog { markSeen(dialog) }

        // Store the last dialog and last tab for future reference.
        lastDialog = selectedDialog
        lastTab = tab

        return selectedDialog
    }

    // MARK: - Helpers

    // Determines the dialog for a new tab.
    private func dialogForNewTab() -> ContextualDialogType? {
        // If "tryASearch" has not been shown, show it.
        if !hasSeen(.tryASearch) {
            return .tryASearch
        }
        // If "tryASearch" was seen and "tryASite" hasn't been shown and the "tracker" dialog hasn't been seen, show "tryASite".
        if !hasSeen(.tryASite) && !hasSeen(.defaultTrackers) {
            return .tryASite
        }
        // If either "tryFireButton" has been shown or the fire button was used, and "highFive" hasn't been shown,
        // and the trackers dialog has been shown, return "highFive" if not previously shown.
        if (hasSeen(.tryFireButton) || stateStorage.fireButtonUsedOnce) &&
            !hasSeen(.highFive) &&
            hasSeen(.defaultTrackers) {
            return .highFive
        }
        return nil
    }

    // Determines the dialog for a DuckDuckGo search URL.
    private func dialogForDuckDuckGoSearch() -> ContextualDialogType? {
        // Ensure "tryASearch" has been seen.
        guard hasSeen(.tryASearch) else { return nil }
        // If the "SearchDone" hasn't been seen, choose between follow-up or non-follow-up (showing TrySiteVisit or not o gotItPressed)
        // based on whether either "tryASite" or the "trackers" has been seen.
        if !hasSeen(.defaultSearchDone) {
            return (hasSeen(.tryASite) || hasSeen(.defaultTrackers))
            ? .searchDone(shouldFollowUp: false)
            : .searchDone(shouldFollowUp: true)
        }
        // If the fire button was used or "tryFireButton" seen, and default trackers has been seen,
        // show "highFive" if not previously shown.
        if (hasSeen(.tryFireButton) || stateStorage.fireButtonUsedOnce) &&
            hasSeen(.defaultTrackers) &&
            !hasSeen(.highFive) {
            return .highFive
        }
        return nil
    }

    // Determines the dialog for a website visit based on tracker type and privacy info.
    private func dialogForRegularUrl(trackerType: OnboardingTrackersType?, privacyInfo: PrivacyInfo?) -> ContextualDialogType? {
        // If "tryASearch" hasn't been seen, show it.
        if !hasSeen(.tryASearch) { return .tryASearch }
        // If a blocked tracker dialog (specific tracker dialog where trackers were blocked) was not shown
        if !stateStorage.blockedTrackerSeen {
            // If the tracker type is blocked, mark it and show a tracker dialog.
            // Decide if when the user presses got it we should show the fireButton dialog
            // (based on whether the fire button was used or related dialog shown)
            if case .blockedTrackers = trackerType {
                stateStorage.blockedTrackerSeen = true
                let shouldFollowUp = !hasSeen(.tryFireButton) && !stateStorage.fireButtonUsedOnce
                return trackerDialog(for: privacyInfo, shouldFollowUp: shouldFollowUp)
            }
            // if the tracker dialog (for not blocked trackers e.i. major tracker no no trackers) hasn't been seen, show it.
            if !hasSeen(.defaultTrackers) {
                let shouldFollowUp = !hasSeen(.tryFireButton) && !stateStorage.fireButtonUsedOnce
                return trackerDialog(for: privacyInfo, shouldFollowUp: shouldFollowUp)
            }
        }
        // If "trackers" has been seen, show "tryFireButton" if not seen before.
        if !hasSeen(.tryFireButton) && hasSeen(.defaultTrackers) {
            return .tryFireButton
        }
        // If "tryFireButton" and "trackers" dialogs have been seen show "highFive" if not seen before.
        if hasSeen(.tryFireButton) && hasSeen(.defaultTrackers) && !hasSeen(.highFive) {
            return .highFive
        }
        return nil
    }

    // Builds a tracker dialog using the tracker message provider.
    private func trackerDialog(for privacyInfo: PrivacyInfo?, shouldFollowUp: Bool) -> ContextualDialogType? {
        guard let message = trackerMessageProvider.trackerMessage(privacyInfo: privacyInfo) else { return nil }
        return .trackers(message: message, shouldFollowUp: shouldFollowUp)
    }

    // Checks if a dialog (by case name) has been seen previously.
    private func hasSeen(_ dialog: ContextualDialogType) -> Bool {
        return stateStorage.contextualDialogsSeen.contains(dialog.stringRepresentation)
    }

    // Marks a dialog as seen by adding its string representation to storage.
    private func markSeen(_ dialog: ContextualDialogType) {
        stateStorage.contextualDialogsSeen.append(dialog.stringRepresentation)
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
        }
    }

    static var defaultTrackers: ContextualDialogType {
        return .trackers(message: NSAttributedString(), shouldFollowUp: true)
    }
    static var defaultSearchDone: ContextualDialogType {
        return .searchDone(shouldFollowUp: true)
    }
}
