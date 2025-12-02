//
//  MoreOptionsMenuButton.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Cocoa
import Combine
import Common

final class MoreOptionsMenuButton: MouseOverButton, NotificationDotProviding {

    private var updateController: UpdateController?
    private var dockCustomization: DockCustomization?

    var notificationLayer: CALayer?
    private var cancellable: AnyCancellable?

    var notificationColor: NSColor = .updateIndicator {
        didSet {
            updateNotificationLayer()
        }
    }

    var isNotificationVisible: Bool = false {
        didSet {
            updateNotificationVisibility()
            needsDisplay = isNotificationVisible != oldValue
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        if AppVersion.runType != .uiTests {
            updateController = Application.appDelegate.updateController
            dockCustomization = Application.appDelegate.dockCustomization
        }
        subscribeToUpdateInfo()
    }

    override func updateLayer() {
        super.updateLayer()
        setupNotificationLayerIfNeeded()
    }

    private func subscribeToUpdateInfo() {
        var dockPublisher: AnyPublisher<Bool, Never>
        guard let dockCustomization = dockCustomization else { return }
        dockPublisher = dockCustomization.shouldShowNotificationPublisher
        guard let updateController else { return }
        cancellable = Publishers.CombineLatest3(updateController.hasPendingUpdatePublisher, updateController.notificationDotPublisher, dockPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPendingUpdate, needsNotificationDot, shouldNotificationForAddToDock in
                self?.isNotificationVisible = hasPendingUpdate && needsNotificationDot || shouldNotificationForAddToDock
            }
    }

    override func layout() {
        super.layout()
        layoutNotification(notificationLayer: notificationLayer)
    }

}
