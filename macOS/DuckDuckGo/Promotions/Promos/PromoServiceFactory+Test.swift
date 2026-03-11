//
//  PromoServiceFactory+Test.swift
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

import AppKit
import BrowserServicesKit
import Combine
import Foundation
import Utilities

extension PromoServiceFactory {
    static var testPromos: [Promo] = {
        guard includeTestPromos else { return [] }

        var testPromoA = Promo(id: "test-promo-a", triggers: [.testTriggered], initiated: .user, promoType: PromoType(.appModal), context: .newTabPage)
        var testPromoB = Promo(id: "test-promo-b", triggers: [.testTriggered], initiated: .user, promoType: PromoType(.appModal), context: .webPage)
        var testPromoC = Promo(id: "test-promo-c", triggers: [.testTriggered], initiated: .app, promoType: PromoType(.appModal), context: .global)
        var testPromoD = Promo(id: "test-promo-d", triggers: [.testTriggered], initiated: .app, promoType: PromoType(.appModal, customTimeoutInterval: .seconds(3), customTimeoutResult: .ignored()), context: .global)

        testPromoA.delegate = TestPromoDelegate(for: testPromoA)
        testPromoB.delegate = TestPromoDelegate(for: testPromoB)
        testPromoC.delegate = TestPromoDelegate(for: testPromoC)
        testPromoD.delegate = TestPromoDelegate(for: testPromoD)

        return [testPromoA, testPromoB, testPromoC, testPromoD]
    }()
}

/// Test promo delegate that shows an NSAlert with metadata, history, and result buttons.
/// Used to exercise promo persistence across app restarts.
final class TestPromoDelegate: PromoDelegate {
    private let promo: Promo
    private var alert: NSAlert?
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(true)

    var isEligible: Bool { isEligibleSubject.value }
    var isEligiblePublisher: AnyPublisher<Bool, Never> { isEligibleSubject.eraseToAnyPublisher() }

    init(for promo: Promo) {
        self.promo = promo
    }

    func resetEligibility() {
        isEligibleSubject.value = true
    }

    @MainActor
    func show(history: PromoHistoryRecord) async -> PromoResult {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let lastShownText = history.lastShown.map { formatter.string(from: $0) } ?? "never"
        let lastDismissedText = history.lastDismissed.map { formatter.string(from: $0) } ?? "never"
        let nextEligibleText: String
        if let next = history.nextEligibleDate {
            if next == .distantFuture {
                nextEligibleText = "Permanently dismissed"
            } else {
                nextEligibleText = formatter.string(from: next)
            }
        } else {
            nextEligibleText = "No cooldown"
        }
        let timeoutResult = promo.promoType.timeoutResult
        let timeoutText = promo.promoType.timeoutInterval.map { "\($0) seconds with result \(timeoutResult)" } ?? "none"

        let metadataBlock = """
            Context: \(promo.context)
            Interruption level: \(promo.promoType.severity)
            Initiated: \(promo.initiated)
            Timeout: \(timeoutText)

            Times dismissed: \(history.timesDismissed)
            Last shown: \(lastShownText)
            Last dismissed: \(lastDismissedText)
            Next eligible: \(nextEligibleText)
            """

        let alert = NSAlert()
        alert.messageText = "Promo: \(promo.id)"
        alert.informativeText = metadataBlock
        alert.alertStyle = .informational

        _ = alert.addButton(withTitle: "Action")
        _ = alert.addButton(withTitle: "Dismiss Permanently")
        _ = alert.addButton(withTitle: "Dismiss (1 day cooldown)")
        _ = alert.addButton(withTitle: "None")
        _ = alert.addButton(withTitle: "Set Ineligible")

        let alertId = AccessibilityIdentifiers.PromoQueue.testPromoAlert(promo.id)
        alert.window.setAccessibilityIdentifier(alertId)
        self.alert = alert

        guard let window = NSApp.delegateTyped.windowControllersManager.mainWindowController?.window ?? NSApp.delegateTyped.windowControllersManager.openNewWindow() else { return .noChange }
        let response = await alert.beginSheetModal(for: window)

        switch response.rawValue {
        case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue:
            return .actioned
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue:
            return .ignored(cooldown: nil)
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue:
            return .ignored(cooldown: .day)
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 2:
            isEligibleSubject.send(false)
            return .noChange
        default:
            return .noChange
        }
    }

    @MainActor
    func hide() {
        guard let alert else { return }
        alert.window.parent?.endSheet(alert.window)
        if alert.window.isVisible {
            alert.window.orderOut(nil)
        }
        self.alert = nil
    }
}
