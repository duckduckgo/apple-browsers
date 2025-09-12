//
//  UpdateController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Common
import Combine
import Sparkle
import BrowserServicesKit
import Persistence
import SwiftUIExtensions
import PixelKit
import SwiftUI
import os.log

protocol UpdateController: AnyObject {

    // Core update state - shared by both implementations
    var latestUpdate: Update? { get }
    var latestUpdatePublisher: Published<Update?>.Publisher { get }

    var hasPendingUpdate: Bool { get }
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { get }

    var needsNotificationDot: Bool { get set }
    var notificationDotPublisher: AnyPublisher<Bool, Never> { get }

    var lastUpdateCheckDate: Date? { get }

    // User-initiated update check - works for both
    func checkForUpdate()
}
