//
//  UserInteractionLockTests.swift
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

struct UserInteractionLockTests {

    @available(iOS 16, macOS 13, *)
    @Test("Unlocked allows everything", .timeLimit(.minutes(1)))
    func unlockedAllowsEverything() {
        #expect(!UserInteractionLock.unlocked.isLocked)
        #expect(UserInteractionLock.unlocked.allows(.fire))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A full lock allows nothing", .timeLimit(.minutes(1)))
    func fullLockAllowsNothing() {
        let lock = UserInteractionLock.locked()

        #expect(lock.isLocked)
        #expect(!lock.allows(.fire))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A lock allows only its exceptions", .timeLimit(.minutes(1)))
    func lockAllowsItsExceptions() {
        let lock = UserInteractionLock.locked(except: [.fire])

        #expect(lock.isLocked)
        #expect(lock.allows(.fire))
    }
}
