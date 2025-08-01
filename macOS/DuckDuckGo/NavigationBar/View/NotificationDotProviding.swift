//
//  NotificationDotProviding.swift
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

import Cocoa
import Common

/// Protocol for buttons that can show a notification dot in their upper-right corner
protocol NotificationDotProviding: NSView {
    var notificationLayer: CALayer? { get set }
    var notificationColor: NSColor { get set }
    var isNotificationVisible: Bool { get set }
}

extension NotificationDotProviding {

    static var notificationSize: CGFloat { 6 }
    static var notificationOffset: CGFloat { 3 }

    func setupNotificationLayerIfNeeded() {
        guard notificationLayer == nil, let layer = self.layer else { return }

        let notificationLayer = CALayer()
        notificationLayer.backgroundColor = notificationColor.cgColor
        layoutNotification(notificationLayer: notificationLayer)
        notificationLayer.isHidden = !isNotificationVisible
        layer.addSublayer(notificationLayer)
        self.notificationLayer = notificationLayer
    }

    func updateNotificationLayer() {
        notificationLayer?.backgroundColor = notificationColor.cgColor
    }

    func updateNotificationVisibility() {
        notificationLayer?.isHidden = !isNotificationVisible
    }

    func layoutNotification(notificationLayer: CALayer?) {
        // Position the dot notification indicator to upper right corner of the button
        notificationLayer?.frame = CGRect(
            x: self.bounds.width - Self.notificationSize - Self.notificationOffset,
            y: Self.notificationOffset,
            width: Self.notificationSize,
            height: Self.notificationSize
        )
        notificationLayer?.cornerRadius = Self.notificationSize / 2
    }
}
