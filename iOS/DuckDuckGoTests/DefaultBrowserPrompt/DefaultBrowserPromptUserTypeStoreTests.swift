//
//  DefaultBrowserPromptUserTypeStoreTests.swift
//  DuckDuckGo
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
import Testing
import class Common.EventMapping
import PersistenceTestingUtils
import SetDefaultBrowserCore
@testable import DuckDuckGo

@Suite("Default Browser Prompt - User Type Store")
final class DefaultBrowserPromptUserTypeStoreTests {
    private var storeMock: MockKeyValueFileStore
    private var sut: DefaultBrowserPromptUserTypeStore

    init() throws {
        storeMock = try MockKeyValueFileStore()
        sut = DefaultBrowserPromptUserTypeStore(keyValueFilesStore: storeMock, eventMapper: EventMapping<DefaultBrowserPromptUserTypeStore.DebugEvent> { _, _, _, _ in })
    }

    @Test(
        "Check User Type Can Be Retrieved",
        arguments: [
            DefaultBrowserPromptUserType.existing,
            .returning,
            .new,
            nil
        ]
    )
    func whenUserTypeIsCalledThenRetrieveUserType(userType: DefaultBrowserPromptUserType?) {
        // GIVEN
        storeMock.underlyingDict = if let userType {
            [DefaultBrowserPromptUserTypeStore.StorageKey.userType: userType.rawValue]
        } else {
            [:]
        }

        // WHEN
        let result = sut.userType()

        // THEN
        #expect(result == userType)
    }

    @Test(
        "Check User Type Can Be Saved",
        arguments: [
            DefaultBrowserPromptUserType.existing,
            .returning,
            .new,
        ]
    )
    func whenUserTypeIsCalledThenRetrieveUserType(userType: DefaultBrowserPromptUserType) throws {
        // GIVEN
        #expect(try storeMock.object(forKey: DefaultBrowserPromptUserTypeStore.StorageKey.userType) == nil)

        // WHEN
        sut.save(userType: userType)

        // THEN
        #expect(try storeMock.object(forKey: DefaultBrowserPromptUserTypeStore.StorageKey.userType) as? String == userType.rawValue)
    }

    @Test("Check When User Cannot Be Retrieved Then Send Correct Event")
    func whenUserCannotBeRetrievedThenSendEvent() {
        // GIVEN
        let error = NSError(domain: #file, code: 0, userInfo: nil)
        var capturedEvent: DefaultBrowserPromptUserTypeStore.DebugEvent?
        var capturedError: Error?
        storeMock.throwOnRead = error
        sut = DefaultBrowserPromptUserTypeStore(keyValueFilesStore: storeMock, eventMapper: EventMapping<DefaultBrowserPromptUserTypeStore.DebugEvent> { event, error, _, _ in
            capturedEvent = event
            capturedError = error
        })

        // WHEN
        _ = sut.userType()

        // THEN
        #expect(capturedEvent == .failedToRetrieveUserType)
        #expect(capturedError as NSError? == error)
    }

    @Test(
        "Check When User Cannot Be Saved Then Send Correct Event",
        arguments: [
            DefaultBrowserPromptUserType.existing,
            .returning,
            .new,
        ]
    )
    func whenUserCannotBeSavedThenSendEvent(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        let error = NSError(domain: #file, code: 0, userInfo: nil)
        var capturedEvent: DefaultBrowserPromptUserTypeStore.DebugEvent?
        var capturedError: Error?
        storeMock.throwOnSet = error
        sut = DefaultBrowserPromptUserTypeStore(keyValueFilesStore: storeMock, eventMapper: EventMapping<DefaultBrowserPromptUserTypeStore.DebugEvent> { event, error, _, _ in
            capturedEvent = event
            capturedError = error
        })

        // WHEN
        sut.save(userType: userType)

        // THEN
        #expect(capturedEvent == .failedToSaveUserType)
        #expect(capturedError as NSError? == error)
    }
}
