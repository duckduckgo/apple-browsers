//
//  DeclaredAgePromptTests.swift
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

import XCTest
import UIKit
import BrowserServicesKit
import FeatureFlags_iOS
@_spi(Testing) import Persistence
@testable import DuckDuckGo

@MainActor
final class DeclaredAgePromptTests: XCTestCase {

    private var storage: (any ThrowingKeyedStoring<DeclaredAgeSettings>)!
    private var service: DeclaredAgeServiceMock!
    private let viewController = UIViewController()

    override func setUp() async throws {
        try await super.setUp()
        storage = InMemoryKeyValueStore().throwingKeyedStoring()
        service = DeclaredAgeServiceMock()
    }

    func testWhenRequestIsDueThenItRequestsTheDeclaredAge() async {
        await makePrompt().presentIfNeeded(in: viewController)

        XCTAssertEqual(service.requestCount, 1)
    }

    func testWhenFlagIsOffThenAppleIsNotAsked() async {
        await makePrompt(isFlagOn: false).presentIfNeeded(in: viewController)

        XCTAssertEqual(service.isRequestRequiredCount, 0)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testWhenRequestIsNotRequiredThenItDoesNotRequest() async {
        service.isRequired = false

        await makePrompt().presentIfNeeded(in: viewController)

        XCTAssertEqual(service.isRequestRequiredCount, 1)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testWhenRequestFailsThenItIsNotAttemptedAgainDuringTheSameLaunch() async {
        service.requestError = CancellationError()
        let prompt = makePrompt()

        await prompt.presentIfNeeded(in: viewController)
        await prompt.presentIfNeeded(in: viewController)

        XCTAssertEqual(service.requestCount, 1)
    }

    func testWhenRequestFailsThenTheNextLaunchRetries() async {
        service.requestError = CancellationError()

        await makePrompt().presentIfNeeded(in: viewController)
        await makePrompt().presentIfNeeded(in: viewController)

        XCTAssertEqual(service.requestCount, 2)
    }

    func testWhenUserAlreadyAnsweredThenTheNextLaunchDoesNotAskApple() async {
        await makePrompt().presentIfNeeded(in: viewController)
        await makePrompt().presentIfNeeded(in: viewController)

        XCTAssertEqual(service.isRequestRequiredCount, 1)
        XCTAssertEqual(service.requestCount, 1)
    }

    // MARK: - Helpers

    private func makePrompt(isFlagOn: Bool = true) -> DeclaredAgePrompt {
        DeclaredAgePrompt(requester: DeclaredAgeRequester(service: service, storage: storage),
                          featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isFlagOn ? [.declaredAgeRange] : []))
    }
}

@MainActor
private final class DeclaredAgeServiceMock: DeclaredAgeServicing {
    var isRequired = true
    var requestError: Error?
    private(set) var isRequestRequiredCount = 0
    private(set) var requestCount = 0

    func isRequestRequired() async throws -> Bool {
        isRequestRequiredCount += 1
        return isRequired
    }

    func requestDeclaredAge(in anchor: DeclaredAgeAnchor) async throws -> Bool {
        requestCount += 1
        if let requestError {
            throw requestError
        }
        return true
    }
}
