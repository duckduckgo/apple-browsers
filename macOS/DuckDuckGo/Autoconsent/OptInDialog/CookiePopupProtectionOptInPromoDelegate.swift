//
//  CookiePopupProtectionOptInPromoDelegate.swift
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
import Combine
import PixelKit
import WebExtensions

/// Presents the Cookie Pop-up Protection opt-in dialog through the promo queue.
/// ponytail: always eligible for now — real show conditions come later.
final class CookiePopupProtectionOptInPromoDelegate: InternalPromoDelegate {

    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(true)
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    var isEligible: Bool { isEligibleSubject.value }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let browserTabViewController = Application.appDelegate.windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController else {
            return .noChange
        }

        // Skip telemetry for force-shows (promo debug menu). First launch presentation vs subsequent ones
        // (the latter is dormant while the dialog shows once per install).
        if !force {
            PixelKit.fire(history.lastShown == nil ? CookiePopupProtectionOptInPixel.shownFirst : .shownRepeat, frequency: .standard)
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
            browserTabViewController.showCookiePopupProtectionOptInDialog(onConfirm: { [weak self] preference in
                PixelKit.fire(CookiePopupProtectionOptInPixel.optionConfirmed(preference: preference), frequency: .standard)
                self?.resume(with: .actioned)
            })
        }
    }

    @MainActor
    func hide() {
        Application.appDelegate.windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController
            .dismissCookiePopupProtectionOptInDialog()
        resume(with: .noChange)
    }

    private func resume(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}
