//
//  AttributedMetricNotifications.swift
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
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension AttributedMetricManager {

    func registerNotifications() {

        // App start
#if os(iOS)
        // NOTE: Remove this and use ForegroundHandling in iOS
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.process(trigger: .appDidStart)
            }
            .store(in: &cancellables)
#elseif os(macOS)
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.process(trigger: .appDidStart)
            }
            .store(in: &cancellables)
#endif
    }
}
