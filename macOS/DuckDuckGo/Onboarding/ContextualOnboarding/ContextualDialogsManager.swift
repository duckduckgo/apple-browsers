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

enum ContextualOnboardingState: String {
    case notStarted
    case ongoing
    case onboardingCompleted
}

enum ContextualDialogType: Equatable {
    case tryASearch
    case searchDone(shouldFollowUp: Bool)
    case tryASite
    case trackers(message: NSAttributedString, shouldFollowUp: Bool)
    case tryFireButton
    case highFive
}

protocol ContextualOnboardingDialogTypeProviding {
    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo?) -> ContextualDialogType?
    var lastDialog: ContextualDialogType? { get }
}

protocol ContextualOnboardingStateUpdater: AnyObject {
    var state: ContextualOnboardingState { get set }
    func gotItPressed()
    func fireButtonUsed()
    func turnOffFeature()
}

protocol ContextualOnboardingStateStoring {
    var contextualDialogsSeen: [String] { get set }
    var stateString: String { get set }
    var blockedTrackerSeen: Bool { get set }
    var fireButtonUsedOnce: Bool { get set }
}

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

public class ContextualDialogsManager: ContextualOnboardingDialogTypeProviding, ContextualOnboardingStateUpdater {

    private var lastDialogDisplayed: ContextualDialogType?
    private let trackerMessageProvider: TrackerMessageProviding
    private var stateStorage: ContextualOnboardingStateStoring
    var lastDialog: ContextualDialogType?

    var state: ContextualOnboardingState {
        get {
            return ContextualOnboardingState(rawValue: stateStorage.stateString) ?? .onboardingCompleted
        }
        set {
            stateStorage.stateString = newValue.rawValue
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

    public func gotItPressed() {
        switch lastDialog {
        case .searchDone(shouldFollowUp: true)?:
            markSeen(.tryASite)
            lastDialog = .tryASite
        case .trackers?:
            markSeen(.tryFireButton)
            lastDialog = .tryFireButton
        case .highFive?:
            state = .onboardingCompleted
        default:
            break
        }
    }

    func fireButtonUsed() {
        stateStorage.fireButtonUsedOnce = true
    }

    func turnOffFeature() {
        state = .onboardingCompleted
    }

    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo? = nil) -> ContextualDialogType? {
        guard state != .onboardingCompleted else { return nil }
        if state == .notStarted { state = .ongoing }
        if hasSeen(.highFive) {
            state = .onboardingCompleted
            return nil
        }

        var selectedDialog: ContextualDialogType?
        switch tab.content {
        case .newtab:
            selectedDialog = dialogForNewTab()
        case .url(let url, _, _):
            if url.isDuckDuckGoSearch {
                selectedDialog = dialogForDuckDuckGoSearch()
            } else {
                let trackerType = trackerMessageProvider.trackersType(privacyInfo: tab.privacyInfo)
                selectedDialog = dialogForRegularUrl(trackerType: trackerType, privacyInfo: privacyInfo)
            }
        default:
            selectedDialog = nil
        }

        if let dialog = selectedDialog, dialog == .highFive {
            state = .onboardingCompleted
        }
        if let dialog = selectedDialog { markSeen(dialog) }
        lastDialog = selectedDialog
        return selectedDialog
    }

    // MARK: - Helpers

    private func dialogForNewTab() -> ContextualDialogType? {
        if !hasSeen(.tryASearch) {
            return .tryASearch
        }
        if !hasSeen(.tryASite) && !hasSeen(.defaultTrackers) {
            return .tryASite
        }
        if (hasSeen(.tryFireButton) || stateStorage.fireButtonUsedOnce) &&
            !hasSeen(.highFive) &&
            hasSeen(.defaultTrackers) {
            return .highFive
        }
        return nil
    }

    private func dialogForDuckDuckGoSearch() -> ContextualDialogType? {
        guard hasSeen(.tryASearch) else { return nil }
        if !hasSeen(.defaultSearchDone) {
            return (hasSeen(.tryASite) || hasSeen(.defaultTrackers))
                ? .searchDone(shouldFollowUp: false)
                : .searchDone(shouldFollowUp: true)
        }
        if hasSeen(.defaultTrackers) && !hasSeen(.tryFireButton) && !stateStorage.fireButtonUsedOnce {
            return .tryFireButton
        }
        if (hasSeen(.tryFireButton) || stateStorage.fireButtonUsedOnce) &&
           hasSeen(.defaultTrackers) &&
           !hasSeen(.highFive) {
            return .highFive
        }
        return nil
    }

    private func dialogForRegularUrl(trackerType: OnboardingTrackersType?, privacyInfo: PrivacyInfo?) -> ContextualDialogType? {
        if !hasSeen(.tryASearch) { return .tryASearch }
        if !stateStorage.blockedTrackerSeen {
            if case .blockedTrackers = trackerType {
                stateStorage.blockedTrackerSeen = true
                let shouldFollowUp = !hasSeen(.tryFireButton) && !stateStorage.fireButtonUsedOnce
                return trackerDialog(for: privacyInfo, shouldFollowUp: shouldFollowUp)
            }
            if !hasSeen(.defaultTrackers) {
                let shouldFollowUp = !hasSeen(.tryFireButton) && !stateStorage.fireButtonUsedOnce
                return trackerDialog(for: privacyInfo, shouldFollowUp: shouldFollowUp)
            }
        }
        if !hasSeen(.tryFireButton) && hasSeen(.defaultTrackers) {
            return .tryFireButton
        }
        if hasSeen(.tryFireButton) && hasSeen(.defaultTrackers) && !hasSeen(.highFive) {
            return .highFive
        }
        return nil
    }

    private func trackerDialog(for privacyInfo: PrivacyInfo?, shouldFollowUp: Bool) -> ContextualDialogType? {
        guard let message = trackerMessageProvider.trackerMessage(privacyInfo: privacyInfo) else { return nil }
        return .trackers(message: message, shouldFollowUp: shouldFollowUp)
    }

    /// Helper to check if a dialog (by case name only) has been seen.
    private func hasSeen(_ dialog: ContextualDialogType) -> Bool {
        return stateStorage.contextualDialogsSeen.contains(dialog.stringRepresentation)
    }

    private func markSeen(_ dialog: ContextualDialogType) {
        stateStorage.contextualDialogsSeen.append(dialog.stringRepresentation)
    }
}

extension ContextualDialogType {
    var stringRepresentation: String {
        switch self {
        case .tryASearch:
            return "tryASearch"
        case .searchDone(_):
            return "searchDone"
        case .tryASite:
            return "tryASite"
        case .trackers(_, _):
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
