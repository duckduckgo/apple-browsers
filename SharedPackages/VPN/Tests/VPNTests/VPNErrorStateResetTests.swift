//
//  VPNErrorStateResetTests.swift
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
import XCTest
@testable import VPN

final class VPNErrorStateResetTests: XCTestCase {

    private final class FakeErrorMessageStore: LastErrorMessageStoring {
        var lastErrorMessage: String?
    }

    private final class FakeKnownFailureStore: LastKnownFailureStoring {
        var lastKnownFailure: KnownFailure?
    }

    /// A working connection must clear both stores, not just one — a value left on either
    /// resurfaces on the next disconnect.
    func testClearRemovesBothTheLastErrorMessageAndTheKnownFailure() {
        let errorMessageStore = FakeErrorMessageStore()
        let knownFailureStore = FakeKnownFailureStore()
        errorMessageStore.lastErrorMessage = "Tunnel failed to start"
        knownFailureStore.lastKnownFailure = KnownFailure(NSError(domain: "SMAppServiceErrorDomain", code: 1))

        // Precondition: both error signals are present.
        XCTAssertNotNil(errorMessageStore.lastErrorMessage)
        XCTAssertNotNil(knownFailureStore.lastKnownFailure)

        let reset = VPNErrorStateReset(errorMessageStore: errorMessageStore,
                                       knownFailureStore: knownFailureStore)
        reset.clear()

        XCTAssertNil(errorMessageStore.lastErrorMessage)
        XCTAssertNil(knownFailureStore.lastKnownFailure)
    }
}
