//
//  AppStoreUpdateController.swift
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
import Foundation
import Combine

final class AppStoreUpdateController: NSObject, UpdateController {
    @Published private(set) var latestUpdate: Update?
    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published private(set) var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    var needsNotificationDot: Bool = false
    var notificationDotPublisher: AnyPublisher<Bool, Never> = .init(Just(false))

    var lastUpdateCheckDate: Date?

    func checkForUpdate() {

    }
}
