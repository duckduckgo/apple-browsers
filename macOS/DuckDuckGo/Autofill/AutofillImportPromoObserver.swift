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
    @MainActor func overlayDidPermanentlyDismissImportPrompt(_ overlay: AnyObject)
    @MainActor func overlayDidHideImportPrompt(_ overlay: AnyObject)
}

enum AutofillImportPromoState {
    case initial
    case permanentlyDismissed
    case importStarted
}

/// Observes the "Import passwords" item in the autofill dropdown.
final class AutofillImportPromoObserver: ExternalPromoDelegate, AutofillImportPromoReporting {

    // Only one overlay is on screen at a time; others may not have reported their hide yet.
    private var currentOverlay: ObjectIdentifier?
    private var promoState: AutofillImportPromoState = .initial

    // PromoService reads `resultWhenHidden` on its own queue; hold the state for a closed promo so it can be used for the result.
    private let closedPromoStateLock = NSLock()
    private var closedPromoState: AutofillImportPromoState = .initial

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.removeDuplicates().eraseToAnyPublisher() }

    var resultWhenHidden: PromoResult {
        closedPromoStateLock.lock()
        defer { closedPromoStateLock.unlock() }
        switch closedPromoState {
        case .initial: return .ignored(cooldown: 0)
        case .permanentlyDismissed: return .ignored()
        case .importStarted: return .actioned
        }
    }

    init() { }

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
        promoState = .importStarted
    }

    @MainActor
    func overlayDidPermanentlyDismissImportPrompt(_ overlay: AnyObject) {
        guard currentOverlay == ObjectIdentifier(overlay) else { return }
        promoState = .permanentlyDismissed
    }

    @MainActor
    func overlayDidHideImportPrompt(_ overlay: AnyObject) {
        guard currentOverlay == ObjectIdentifier(overlay) else { return }
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
