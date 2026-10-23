//
//  FireAnimationTestSupport.swift
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

import Common
import Foundation

/// UI tests opt into real playback and hold cleanup independently of animation timing.
/// Environment controls are ignored by normal browser launches.
enum FireAnimationTestSupport {
    static var playsAnimations: Bool {
        switch AppVersion.runType {
        case .normal: return true
        case .uiTests: return ProcessInfo.processInfo.environment["FIRE_UI_TEST_PLAY_ANIMATIONS"] == "1"
        default: return false
        }
    }

    static func waitForCleanupRelease() async {
        guard case .uiTests = AppVersion.runType,
              let path = ProcessInfo.processInfo.environment["FIRE_UI_TEST_CLEANUP_RELEASE"] else { return }
        try? Data().write(to: URL(fileURLWithPath: path + ".started"))
        // Bound an interrupted test's hold so its browser cannot remain blocked indefinitely.
        for _ in 0..<1_200 {
            if FileManager.default.fileExists(atPath: path) { return }
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }
    }

    static func didFinishCleanup() {
        guard case .uiTests = AppVersion.runType,
              let path = ProcessInfo.processInfo.environment["FIRE_UI_TEST_CLEANUP_RELEASE"] else { return }
        try? Data().write(to: URL(fileURLWithPath: path + ".finished"))
    }
}
