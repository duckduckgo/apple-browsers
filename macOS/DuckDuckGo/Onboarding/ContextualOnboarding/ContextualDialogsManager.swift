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
import Subscription

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
    case tryDuckAI
    case subscriptionUpsell
    case thatsDuckAI
}

/// Protocol for providing the appropriate dialog type based on a Tab.
protocol ContextualOnboardingDialogTypeProviding {
    /// Returns a dialog type for the provided tab and  privacy information.
    func dialogTypeForTab(_ tab: Tab) -> ContextualDialogType?

    /// Returns the last dialog shown if it was shown for the given tab.
    func lastDialogForTab(_ tab: Tab) -> ContextualDialogType?

    /// The most recently selected dialog.
    var lastDialog: ContextualDialogType? { get }
}

/// Protocol to update the onboarding state (e.g., when the user uses the fire button or the feature is turned off).
protocol ContextualOnboardingStateUpdater: AnyObject {
    var state: ContextualOnboardingState { get set }
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { get }
    /// Whether the Duck.ai path is waiting for the user to delete their chat with Fire.
    var isWaitingForDuckAIChatDeletion: Bool { get }
    func gotItPressed()
    func fireButtonUsed()
    func turnOffFeature()
}

/// Starts the contextual onboarding path the user picked on the junction.
protocol ContextualOnboardingPathStarting: AnyObject {
    func startPath(_ kind: ContextualOnboardingPathKind, query: String)
}

/// Locks the browser UI while contextual onboarding needs the user to stay on one tab.
protocol ContextualOnboardingUILocking: AnyObject {
    @MainActor func setUILock(_ lock: UserInteractionLock)
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
public class ContextualDialogsManager: ObservableObject, ContextualOnboardingDialogTypeProviding, ContextualOnboardingStateUpdater, ContextualOnboardingPathStarting {

    private let progress: ContextualOnboardingProgress
    private let makePath: (ContextualOnboardingPathKind) -> ContextualOnboardingPath
    private weak var uiLocker: ContextualOnboardingUILocking?
    /// The lock last sent to `uiLocker`, so it's only told about changes.
    private var appliedUILock = UserInteractionLock.unlocked

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
            if isCompleted {
                progress.duckAIPrompt = nil
            }

            // If onboarding is restarted, clear all stored dialogs and flags.
            if newValue == .notStarted {
                activePath.reset()
                progress.reset()
                activePath = makePath(.search)
            }
            updateUILock()
        }
    }

    init(trackerMessageProvider: TrackerMessageProviding,
         subscriptionManager: any SubscriptionManager,
         stateStorage: ContextualOnboardingStateStoring = ContextualOnboardingStateStorage(),
         settings: any ThrowingKeyedStoring<ContextualOnboardingSettings> = Application.appDelegate.keyValueStore.throwingKeyedStoring(),
         uiLocker: ContextualOnboardingUILocking? = nil,
         aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
         makePath: ((ContextualOnboardingPathKind, ContextualOnboardingProgressReading) -> ContextualOnboardingPath)? = nil) {
        let progress = ContextualOnboardingProgress(storage: stateStorage, settings: settings)
        self.progress = progress
        self.uiLocker = uiLocker
        self.makePath = { kind in
            if let makePath { return makePath(kind, progress) }
            switch kind {
            case .search:
                return SearchOnboardingPath(progress: progress,
                                            subscriptionManager: subscriptionManager,
                                            trackerMessageProvider: trackerMessageProvider,
                                            aiChatMenuConfig: aiChatMenuConfig)
            case .duckAI:
                return DuckAIOnboardingPath(progress: progress, subscriptionManager: subscriptionManager)
            }
        }
        // Compares the raw value, as before: an unreadable saved value counts as not completed here.
        self.isContextualOnboardingCompleted = stateStorage.stateString == ContextualOnboardingState.onboardingCompleted.rawValue
        // After a relaunch, restores the lock of a path that was still running.
        updateUILock()
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

    var isWaitingForDuckAIChatDeletion: Bool {
        state != .onboardingCompleted && progress.pathKind == .duckAI && !progress.fireButtonUsedOnce
    }

    // Called when the user uses the fire button
    func fireButtonUsed() {
        progress.fireButtonUsedOnce = true
        progress.duckAIPrompt = nil
        // Fire can be used before a reopened chat shows "That's Duck.ai!"; the ending must still follow.
        if progress.pathKind == .duckAI {
            progress.markSeen(.thatsDuckAI)
        }
        updateUILock()
    }

    /// The lock the active path keeps on the browser UI. None on the search path and once onboarding ends.
    var uiLock: UserInteractionLock {
        state == .onboardingCompleted ? .unlocked : activePath.uiLock
    }

    private func updateUILock() {
        let lock = uiLock
        // Only send changes, so an unlocked path doesn't lift the welcome onboarding's lock.
        guard lock != appliedUILock else { return }
        appliedUILock = lock
        DispatchQueue.main.async { [weak uiLocker] in uiLocker?.setUILock(lock) }
    }

    /// Called from the junction with the path the user picked and the text they sent.
    func startPath(_ kind: ContextualOnboardingPathKind, query: String) {
        progress.pathKind = kind
        activePath = makePath(kind)
        switch kind {
        case .search:
            // The user has just searched from the junction, so Try a search is skipped.
            progress.markSeen(.tryASearch)
        case .duckAI:
            // Only Fire used on this path unlocks it, not Delete All History during the welcome flow.
            progress.fireButtonUsedOnce = false
            progress.duckAIPrompt = query
        }
        updateUILock()
    }

    /// Shows "That's Duck.ai!" again for the chat reopened in a new window.
    func restartDuckAIChat() {
        progress.markUnseen(.thatsDuckAI)
    }

    /// Moves to the search path, from Try a search, when the Duck.ai chat can't be reopened.
    func fallBackToSearchPath() {
        progress.pathKind = .search
        progress.duckAIPrompt = nil
        activePath = makePath(.search)
        updateUILock()
    }

    var duckAIPrompt: String? {
        progress.duckAIPrompt
    }

    // Called to turn off the contextual onboarding.
    func turnOffFeature() {
        state = .onboardingCompleted
    }

    // Determines and returns which dialog should be shown for a given tab and privacy info.
    func dialogTypeForTab(_ tab: Tab) -> ContextualDialogType? {
        // If onboarding is complete, return nil.
        guard state != .onboardingCompleted else { return nil }
        // If onboarding hasn't started, mark it as ongoing.
        if state == .notStarted { state = .ongoing }

        switch activePath.dialog(for: tab) {
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
        case .tryDuckAI:
            return "tryDuckAI"
        case .subscriptionUpsell:
            return "subscriptionUpsell"
        case .thatsDuckAI:
            return "thatsDuckAI"
        }
    }

    static var defaultTrackers: ContextualDialogType {
        return .trackers(message: NSAttributedString(), shouldFollowUp: true)
    }
    static var defaultSearchDone: ContextualDialogType {
        return .searchDone(shouldFollowUp: true)
    }
}
