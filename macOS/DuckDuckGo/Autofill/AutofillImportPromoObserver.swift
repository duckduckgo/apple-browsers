//
//  AutofillImportPromoObserver.swift
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

import Combine
import Foundation

protocol AutofillImportPromoReporting: AnyObject {
    @MainActor func overlayDidShowImportPrompt(_ overlay: AnyObject)
    @MainActor func overlayDidStartImport(_ overlay: AnyObject)
    @MainActor func overlayDidEndImportFlow(_ overlay: AnyObject)
    @MainActor func overlayDidPermanentlyDismissImportPrompt(_ overlay: AnyObject)
    @MainActor func overlayWillDisappear(_ overlay: AnyObject)
}

private enum AutofillImportPromoState {
    case initial
    case importInProgress(hadImportedLogins: Bool)
    case importedLogins
    case permanentlyDismissed
}

/// Observes the "Import passwords" item in the autofill dropdown.
final class AutofillImportPromoObserver: ExternalPromoDelegate, AutofillImportPromoReporting {

    // Only one overlay is on screen at a time; others may not have reported their hide yet.
    @MainActor private var currentOverlay: ObjectIdentifier?
    private var promoState: AutofillImportPromoState = .initial

    // PromoService reads `resultWhenHidden` on its own queue; hold the state for a closed promo to determine the result.
    private let closedPromoStateLock = NSLock()
    private var closedPromoState: AutofillImportPromoState = .initial

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)
    private let loginImportStateProvider: AutofillLoginImportStateProvider

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.removeDuplicates().eraseToAnyPublisher() }

    var resultWhenHidden: PromoResult {
        closedPromoStateLock.lock()
        defer { closedPromoStateLock.unlock() }
        switch closedPromoState {
        case .initial, .importInProgress: return .ignored(cooldown: 0)
        case .importedLogins: return .actioned
        case .permanentlyDismissed: return .ignored()
        }
    }

    init(loginImportStateProvider: AutofillLoginImportStateProvider) {
        self.loginImportStateProvider = loginImportStateProvider
    }

    @MainActor
    func overlayDidShowImportPrompt(_ overlay: AnyObject) {
        let overlayID = ObjectIdentifier(overlay)
        guard currentOverlay != overlayID else { return }
        if currentOverlay != nil {
            // The previous overlay never reported its hide.
            close()
        }
        currentOverlay = overlayID
        promoState = .initial
        visibilitySubject.send(true)
    }

    @MainActor
    func overlayDidStartImport(_ overlay: AnyObject) {
        guard currentOverlay == ObjectIdentifier(overlay) else { return }
        // A tab loaded before an earlier import can still offer the item; only an import that adds logins counts.
        promoState = .importInProgress(hadImportedLogins: loginImportStateProvider.hasImportedLogins)
    }

    @MainActor
    func overlayDidEndImportFlow(_ overlay: AnyObject) {
        guard currentOverlay == ObjectIdentifier(overlay),
              case .importInProgress(let hadImportedLogins) = promoState else { return }
        if !hadImportedLogins, loginImportStateProvider.hasImportedLogins {
            promoState = .importedLogins
        }
        close()
    }

    @MainActor
    func overlayDidPermanentlyDismissImportPrompt(_ overlay: AnyObject) {
        guard currentOverlay == ObjectIdentifier(overlay) else { return }
        promoState = .permanentlyDismissed
    }

    @MainActor
    func overlayWillDisappear(_ overlay: AnyObject) {
        guard currentOverlay == ObjectIdentifier(overlay) else { return }
        // Launching the import flow hides the overlay; the import flow's end closes the promo instead.
        if case .importInProgress = promoState { return }
        close()
    }

    @MainActor
    private func close() {
        // Resolve before emitting: PromoService reads `resultWhenHidden` once it observes `false`.
        closedPromoStateLock.lock()
        closedPromoState = promoState
        closedPromoStateLock.unlock()
        currentOverlay = nil
        visibilitySubject.send(false)
    }
}
