//
//  WindowsManagerFireWindowOpenTriggerTests.swift
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

import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct WindowsManagerFireWindowOpenTriggerTests {

    @Test("Check non Fire windows opens are not classified", arguments: [true, false])
    func nilWhenNotBurner(isOpenedAutomatically: Bool) {
        #expect(WindowsManager.fireWindowOpenTrigger(
            isBurner: false,
            burnerModeWasExplicitlyProvided: true,
            isOpenedAutomatically: isOpenedAutomatically
        ) == nil)
    }

    @Test("Check Fire Windows opened by an explicit user gesture are classified as manual")
    func manualWhenExplicitBurnerAndNotAutomatic() {
        #expect(WindowsManager.fireWindowOpenTrigger(
            isBurner: true,
            burnerModeWasExplicitlyProvided: true,
            isOpenedAutomatically: false
        ) == .manual)
    }

    @Test("Check Fire Windows opened during app startup are classified as automatic")
    func automaticWhenIsOpenedAutomatically() {
        #expect(WindowsManager.fireWindowOpenTrigger(
            isBurner: true,
            burnerModeWasExplicitlyProvided: true,
            isOpenedAutomatically: true
        ) == .automatic)
    }

    @Test("Check Fire Windows opened via the 'Open Fire Window by default' preference are classified as automatic")
    func automaticWhenBurnerInferred() {
        #expect(WindowsManager.fireWindowOpenTrigger(
            isBurner: true,
            burnerModeWasExplicitlyProvided: false,
            isOpenedAutomatically: false
        ) == .automatic)
    }

    @Test("Check Fire Windows are classified as automatic when both preference and startup signals apply")
    func automaticWhenBothInferredAndAutomatic() {
        #expect(WindowsManager.fireWindowOpenTrigger(
            isBurner: true,
            burnerModeWasExplicitlyProvided: false,
            isOpenedAutomatically: true
        ) == .automatic)
    }

}
