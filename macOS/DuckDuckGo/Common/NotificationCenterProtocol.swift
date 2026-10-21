//
//  NotificationCenterProtocol.swift
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

protocol NotificationCenterProtocol: AnyObject {
    func post(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)
    func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?)
    func notificationPublisher(for name: Notification.Name, object: AnyObject?) -> AnyPublisher<Notification, Never>
}

extension NotificationCenter: NotificationCenterProtocol {
    func notificationPublisher(for name: Notification.Name, object: AnyObject?) -> AnyPublisher<Notification, Never> {
        publisher(for: name, object: object).eraseToAnyPublisher()
    }
}

extension NotificationCenterProtocol {
    func post(name: Notification.Name, object: Any?) {
        post(name: name, object: object, userInfo: nil)
    }

    func notificationPublisher(for name: Notification.Name) -> AnyPublisher<Notification, Never> {
        notificationPublisher(for: name, object: nil)
    }
}
