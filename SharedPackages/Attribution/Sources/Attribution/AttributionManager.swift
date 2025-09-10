//
//  AttributionManager.swift
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
//

import Foundation
import PixelKit
import Combine

public final class AttributionManager {

    let pixelKit: PixelKit
    let userDefaults: UserDefaults
    let originProvider: (any AttributionOriginProvider)?
    private var cancellables = Set<AnyCancellable>()

    init(pixelKit: PixelKit, userDefaults: UserDefaults, originProvider: (any AttributionOriginProvider)?) {
        self.pixelKit = pixelKit
        self.userDefaults = userDefaults
        self.originProvider = originProvider

        registerNotifications()
    }

    func registerNotifications() {

//        NotificationCenter.default
//            .publisher(for: UIApplication.didEnterBackgroundNotification)
//            .sink { [weak self] _ in
//                self?.appDidEnterBackground()
//            }
//            .store(in: &cancellables)

    }
}
