//
//  AIChatBonusInstallCleanupTests.swift
//  DuckDuckGo
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

import Foundation
import Testing
@testable import DuckDuckGo

@Suite("AIChatBonus - Install Cleanup Tests")
struct AIChatBonusInstallCleanupTests {

    @Test("Check the record is deleted on a new install")
    func recordIsDeletedOnANewInstall() {
        // GIVEN
        var deleteCallCount = 0

        // WHEN
        AIChatBonusInstallCleanup.deleteRecordIfNewInstall(installDate: nil) { deleteCallCount += 1 }

        // THEN
        #expect(deleteCallCount == 1)
    }

    @Test("Check the record is kept once the install date is known")
    func recordIsKeptOnceTheInstallDateIsKnown() {
        // GIVEN
        let installDate = Date(timeIntervalSince1970: 1_792_036_890)
        var deleteCallCount = 0

        // WHEN
        AIChatBonusInstallCleanup.deleteRecordIfNewInstall(installDate: installDate) { deleteCallCount += 1 }

        // THEN
        #expect(deleteCallCount == 0)
    }
}
