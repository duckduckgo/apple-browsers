//
//  SyncIdentitiesAdapterTests.swift
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

import XCTest
import BrowserServicesKit
import Combine
import DDGSync
@testable import DuckDuckGo_Privacy_Browser

final class SyncIdentitiesAdapterTests: XCTestCase {

    var errorHandler: CapturingAdapterErrorHandler!
    var adapter: SyncIdentitiesAdapter!
    var metadataStore: MockMetadataStore! = .init()
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        errorHandler = CapturingAdapterErrorHandler()
        adapter = SyncIdentitiesAdapter(syncErrorHandler: errorHandler)
        cancellables = []
    }

    override func tearDownWithError() throws {
        errorHandler = nil
        adapter = nil
        cancellables = nil
        metadataStore = nil
        try super.tearDownWithError()
    }

    func testWhenSyncErrorPublished_thenHandleIdentitiesErrorCalled() async {
        let expectation = XCTestExpectation(description: "Sync did fail")
        let expectedError = NSError(domain: "identities", code: 500)
        adapter.setUpProviderIfNeeded(secureVaultFactory: AutofillSecureVaultFactory, metadataStore: metadataStore)
        adapter.provider!.syncErrorPublisher
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        adapter.provider?.handleSyncError(expectedError)

        await fulfillment(of: [expectation], timeout: 10.0)
        XCTAssertTrue(errorHandler.handleIdentitiesErrorCalled)
        XCTAssertEqual(errorHandler.capturedError as? NSError, expectedError)
    }

    func testWhenSyncDidUpdate_thenSyncIdentitiesSucceededCalled() async {
        let expectation = XCTestExpectation(description: "Sync Did Update")
        adapter.setUpProviderIfNeeded(secureVaultFactory: AutofillSecureVaultFactory, metadataStore: metadataStore)

        Task {
            adapter.provider?.syncDidUpdateData()
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertTrue(errorHandler.syncIdentitiesSuccededCalled)
    }
}
