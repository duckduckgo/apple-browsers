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

/// Observes the "Import passwords" item in the autofill dropdown.
final class AutofillImportPromoObserver: ExternalPromoDelegate, AutofillImportPromoReporting {

    private var visibleOverlayOutcomes: [ObjectIdentifier: PromoResult] = [:]
    private var pendingResult: PromoResult = .ignored(cooldown: 0)

    // PromoService reads `resultWhenHidden` on its own queue.
    private let resolvedResultLock = NSLock()
    private var resolvedResult: PromoResult = .ignored(cooldown: 0)

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.removeDuplicates().eraseToAnyPublisher() }

    var resultWhenHidden: PromoResult {
        resolvedResultLock.lock()
        defer { resolvedResultLock.unlock() }
        return resolvedResult
    }

    init() { }

    @MainActor
    func overlayDidShowImportPrompt(_ overlay: AnyObject) {
        let overlayID = ObjectIdentifier(overlay)
        if visibleOverlayOutcomes[overlayID] == nil {
            visibleOverlayOutcomes[overlayID] = .ignored(cooldown: 0)
        }
        updateVisibility()
    }

    @MainActor
    func overlayDidStartImport(_ overlay: AnyObject) {
        upgradeOutcome(of: ObjectIdentifier(overlay), to: .actioned)
    }

    @MainActor
    func overlayDidPermanentlyDismissImportPrompt(_ overlay: AnyObject) {
        upgradeOutcome(of: ObjectIdentifier(overlay), to: .ignored())
    }

    @MainActor
    func overlayDidHideImportPrompt(_ overlay: AnyObject) {
        guard let outcome = visibleOverlayOutcomes.removeValue(forKey: ObjectIdentifier(overlay)) else { return }
        pendingResult = Self.stronger(pendingResult, outcome)
        updateVisibility()
    }

    @MainActor
    private func upgradeOutcome(of overlayID: ObjectIdentifier, to outcome: PromoResult) {
        guard let current = visibleOverlayOutcomes[overlayID] else { return }
        visibleOverlayOutcomes[overlayID] = Self.stronger(current, outcome)
    }

    private static func stronger(_ lhs: PromoResult, _ rhs: PromoResult) -> PromoResult {
        func rank(_ result: PromoResult) -> Int {
            switch result {
            case .actioned: return 2
            case .ignored(cooldown: nil): return 1
            default: return 0
            }
        }
        return rank(rhs) > rank(lhs) ? rhs : lhs
    }

    @MainActor
    private func updateVisibility() {
        let visible = !visibleOverlayOutcomes.isEmpty
        guard visibilitySubject.value != visible else { return }
        if !visible {
            // Resolve before emitting: PromoService reads `resultWhenHidden` once it observes `false`.
            resolvedResultLock.lock()
            resolvedResult = pendingResult
            resolvedResultLock.unlock()
            pendingResult = .ignored(cooldown: 0)
        }
        visibilitySubject.send(visible)
    }
}
