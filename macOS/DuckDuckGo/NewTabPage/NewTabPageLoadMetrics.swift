//
//  NewTabPageLoadMetrics.swift
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

import AppKit
import PixelKit
import os.log

final class NewTabPageLoadMetrics {

    enum NTPState {
        case loading
        case notLoading
    }

    private var ntpStartTime: Date?
    private var ntpShownTime: Date?
    private var state: NTPState = .notLoading
    private let firePixel: (PixelKitEvent) -> Void

    init(firePixel: @escaping (PixelKitEvent) -> Void = { PixelKit.fire($0, frequency: .standard) }) {
        self.firePixel = firePixel
    }

    /// Called when the app is about to show the New Tab Page
    func onNTPWillPresent() {
        state = .loading
        ntpStartTime = Date()
    }

    /// Called when the New Tab Page has become visible to the user
    func onNTPDidPresent() {
        guard state == .loading else {
            Logger.newTabPageMetrics.error("NTP presentation not initiated")
            return
        }
        ntpShownTime = Date()
        state = .notLoading
        if let loadTime = calculateLoadTime() {
            reportLoadTime(loadTime)
        }
    }

    /// Called when the NTP is already loaded and presented
    func onNTPAlreadyPresented() {
        reportLoadTime(0)
    }

    /// Returns the time it took to present the New Tab Page, or nil if invalid
    func calculateLoadTime() -> TimeInterval? {
        guard let start = ntpStartTime, let shown = ntpShownTime else {
            return nil
        }
        return shown.timeIntervalSince(start)
    }

    private func reportLoadTime(_ loadTime: TimeInterval) {
        guard loadTime <= 10 else {
            return
        }
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        firePixel(NewTabPagePixel.newTabPageLoadingTime(duration: loadTime, osMajorVersion: osVersion))
    }

}
