//
//  PromoTriggerTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromoTriggerTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// The trigger is only useful if the notification the save flow already posts actually reaches the queue.
    func testWhenFirstPasswordSavedNotificationPostedThenTriggerIsPublished() {
        let expectation = expectation(description: "trigger published")
        var received: PromoTrigger?

        PromoTrigger.triggerPublisher
            .sink { trigger in
                if trigger == .firstPasswordSaved {
                    received = trigger
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.post(name: .firstPasswordSaved, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, .firstPasswordSaved)
    }
}
