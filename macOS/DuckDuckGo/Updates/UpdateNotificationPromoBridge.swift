//
//  UpdateNotificationPromoBridge.swift
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

import AppUpdaterShared
import Combine
import Foundation

protocol UpdateNotificationPromoDismissing: AnyObject {
    @MainActor func dismissIfPresented()
}

/// Bridges the existing Sparkle/App Store update-check machinery onto the `update-available` and
/// `browser-updated` promo triggers.
final class UpdateNotificationPromoBridge: UpdateNotificationPresenting {

    @Published private(set) var pendingApplicationUpdateStatus: AppUpdateStatus = .noChange
    var pendingApplicationUpdateStatusPublisher: AnyPublisher<AppUpdateStatus, Never> {
        $pendingApplicationUpdateStatus.eraseToAnyPublisher()
    }

    weak var updateAvailableDelegate: UpdateNotificationPromoDismissing?
    weak var browserUpdatedDelegate: UpdateNotificationPromoDismissing?

    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observers = [
            notificationCenter.addObserver(forName: .suggestionWindowDidShow, object: nil, queue: .main) { [weak self] _ in
                self?.dismissIfPresented()
            }
        ]
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    func showUpdateNotification(for status: Update.UpdateType, areAutomaticUpdatesEnabled: Bool) {
        notificationCenter.post(name: .updateAvailable, object: nil)
    }

    func showUpdateNotification(for status: AppUpdateStatus) {
        guard status != .noChange else { return }
        pendingApplicationUpdateStatus = status
        notificationCenter.post(name: .browserUpdated, object: nil)
    }

    func dismissIfPresented() {
        DispatchQueue.main.async { [weak self] in
            self?.updateAvailableDelegate?.dismissIfPresented()
            self?.browserUpdatedDelegate?.dismissIfPresented()
        }
    }

    func openUpdatesPage() {
        DispatchQueue.main.async {
            Application.appDelegate.updateController?.openUpdatesPage()
        }
    }

    func acknowledgeApplicationUpdateStatus() {
        pendingApplicationUpdateStatus = .noChange
    }
}
