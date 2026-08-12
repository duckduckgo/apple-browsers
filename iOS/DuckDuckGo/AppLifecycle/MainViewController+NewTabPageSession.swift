//
//  MainViewController+NewTabPageSession.swift
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

import Core
import Foundation
import Suggestions
import UIKit
import VPN

private extension ConnectionStatus {

    /// Treats the handshake as already on, so a toggle sampled mid-connect is not read as unchanged.
    var isConnectedForSessionInstrumentation: Bool {
        switch self {
        case .connected, .connecting:
            return true
        case .notConfigured, .disconnected, .disconnecting, .reasserting, .snoozing:
            return false
        }
    }
}

/// Call sites for the New Tab Page session wide event, which measures how often a visit to the
/// New Tab Page ends in the user reaching what they came for.
extension MainViewController {

    /// Notes the VPN state as the user leaves the New Tab Page for the VPN screen, so a change
    /// made while they are there can be attributed to them on their return.
    func noteNewTabPageSessionVPNStateBeforeLeaving() {
        guard isNewTabPageVisible else { return }
        vpnConnectedWhenLeavingNewTabPage = AppDependencyProvider.shared.connectionObserver.recentValue.isConnectedForSessionInstrumentation
    }

    /// Records a VPN toggle the user made after leaving for the VPN screen.
    ///
    /// The state is sampled rather than observed, because the connection publisher also fires for
    /// reconnects the user had nothing to do with. Sampling only around a deliberate visit to the
    /// screen keeps those out, at the cost of attributing a self-healing reconnect during that
    /// visit to the user.
    func recordNewTabPageSessionVPNChangeIfNeeded() {
        guard let wasConnected = vpnConnectedWhenLeavingNewTabPage else { return }
        vpnConnectedWhenLeavingNewTabPage = nil

        let isConnected = AppDependencyProvider.shared.connectionObserver.recentValue.isConnectedForSessionInstrumentation
        guard isConnected != wasConnected, isNewTabPageVisible else { return }

        if isConnected {
            newTabPageSessionInstrumentation.vpnOn()
        } else {
            newTabPageSessionInstrumentation.vpnOff()
        }
    }

    /// Opens a visit when the app returns to a New Tab Page that is already on screen.
    ///
    /// Backgrounding ends the visit, and foregrounding does not re-attach the page, so the arrival
    /// has nothing else to announce it. Without this, everything the user does after coming back
    /// goes unrecorded until some other surface replaces the page.
    func registerForNewTabPageSessionForegroundNotification() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onForegroundWithNewTabPageOnScreen),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    @objc
    private func onForegroundWithNewTabPageOnScreen() {
        guard isNewTabPageVisible else { return }

        // Not a burn arrival: a burn reports itself through the attach it causes.
        startNewTabPageSessionInstrumentation(isNewTab: false,
                                              willBeginEditing: keyboardShowing,
                                              isAfterFire: false)
    }

    /// Records a New Tab Page action, but only while the New Tab Page is the surface on screen.
    ///
    /// A visit stays open until something ends it, and not every way out of the New Tab Page has a
    /// terminal. Without this guard such a visit would keep collecting interactions belonging to
    /// whatever replaced it.
    func recordNewTabPageSessionAction(_ record: (NewTabPageSessionInstrumentation) -> Void) {
        guard isNewTabPageVisible else { return }
        recordNewTabPageSessionVPNChangeIfNeeded()
        record(newTabPageSessionInstrumentation)
    }

    /// Records text entry from either the omnibar or the unified input.
    ///
    /// Empty text is ignored: the same change signals also carry a cleared field and the
    /// text hand-over between the search and Duck.ai inputs, neither of which is the user
    /// putting a query in.
    func recordNewTabPageSessionTextEntry(_ text: String) {
        guard !text.isEmpty else { return }
        recordNewTabPageSessionAction { $0.typeInInput() }
    }

    /// Ends the visit on a navigation the user asked for, splitting search results from a site.
    ///
    /// Called with the resolved URL rather than the typed text, because whether a query becomes a
    /// search or a direct address is only decided while building it. Unlike the action hooks this
    /// has no visibility guard: it must still land when the New Tab Page has already gone.
    func endNewTabPageSessionWithLoad(of url: URL) {
        newTabPageSessionInstrumentation.visitEnded(terminalAction: url.isDuckDuckGoSearch ? .loadSerp : .loadWebsite)
    }

    /// Records the user moving the Search / Duck.ai toggle, in whichever direction.
    func recordNewTabPageSessionToggleSwitch(to mode: TextEntryMode) {
        recordNewTabPageSessionAction { instrumentation in
            switch mode {
            case .search: instrumentation.switchToggleToSearch()
            case .aiChat: instrumentation.switchToggleToAiChat()
            }
        }
    }

    /// Records opening a screen from the browsing menu.
    ///
    /// The visit stays open: the menu takes the user somewhere else in the app, and they usually
    /// come back. Ending it here would lose everything they do next, including the selection the
    /// entry leads to.
    func recordNewTabPageSessionMenuEntry(_ record: (NewTabPageSessionInstrumentation) -> Void) {
        recordNewTabPageSessionAction(record)
        recordNewTabPageSessionDeparture()
    }

    /// Marks that the user is now reading a screen the app opened over the New Tab Page, so the
    /// time they spend there is not mistaken for abandoning the visit.
    func recordNewTabPageSessionDeparture() {
        guard isNewTabPageVisible else { return }
        newTabPageSessionInstrumentation.noteUserLeftForAnotherScreen()
    }

    /// Ends the visit on the customizable toolbar button doing something other than burning.
    ///
    /// Where it leads is deliberately not distinguished: the button is one slot the user has
    /// assigned, so what matters for the success rate is that they reached for it. Buttons needing
    /// a loaded page never act on the New Tab Page, so they cannot end a visit either.
    func endNewTabPageSessionWithCustomButton() {
        newTabPageSessionInstrumentation.visitEnded(terminalAction: .customButton)
    }

    /// Ends the visit on a burn, whichever surface it was started from.
    ///
    /// Called as the burn begins rather than once it finishes, because clearing lands the user back
    /// on a fresh New Tab Page: a terminal reported after that re-attach would arrive when the visit
    /// it belongs to has already been superseded and discarded.
    func endNewTabPageSessionWithDataClearing() {
        newTabPageSessionInstrumentation.visitEnded(terminalAction: .deleteData)
    }

    /// Records picking an autocomplete row, then ends the visit on where that row leads.
    ///
    /// The action is recorded first so it survives into the completed visit. Suggestions that do
    /// not navigate leave the visit open: a bookmarklet runs against the current page, and Duck.ai
    /// reports its own terminal once the chat opens.
    func endNewTabPageSessionWithSuggestion(_ suggestion: Suggestion) {
        recordNewTabPageSessionAction { $0.chooseSuggestion() }

        let terminalAction: NewTabPageSessionWideEventData.TerminalAction?
        switch suggestion {
        case .phrase:
            terminalAction = .loadSearchSuggestion
        case .website(let url):
            terminalAction = url.isBookmarklet() ? nil : .loadWebsite
        case .bookmark(_, let url, _, _):
            terminalAction = url.isBookmarklet() ? nil : .loadWebsite
        case .historyEntry(_, let url, _):
            // History covers both past searches and past sites, so the URL decides which.
            terminalAction = url.isDuckDuckGoSearch ? .loadSerp : .loadWebsite
        case .openTab:
            terminalAction = .selectOtherTab
        case .askAIChat, .unknown, .internalPage:
            terminalAction = nil
        }

        guard let terminalAction else { return }
        newTabPageSessionInstrumentation.visitEnded(terminalAction: terminalAction)
    }
}
