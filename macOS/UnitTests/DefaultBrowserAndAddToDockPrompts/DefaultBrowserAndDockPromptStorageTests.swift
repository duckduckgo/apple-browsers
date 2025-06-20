//
//  DefaultBrowserAndDockPromptStorageTests.swift
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

import Common
import Foundation
import PersistenceTestingUtils
import Testing

@testable import DuckDuckGo_Privacy_Browser

struct DefaultBrowserAndDockPromptStorageTests {
    static let now = Date(timeIntervalSince1970: 1747785600) // 21 May 2025 12:00:00 AM

    struct PersistenceTests {

        @Test("Check Popover Shown Date Is Persisted")
        func checkPopoverShownDateIsPersistedInUnderlyingStorage() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.popoverShownDate.rawValue) == nil)

            // WHEN
            sut.popoverShownDate = now.timeIntervalSince1970

            // THEN
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.popoverShownDate.rawValue) as? TimeInterval == now.timeIntervalSince1970)
        }

        @Test("Check Popover Shown Date Is Retrieved")
        func checkPopoverShownDateIsRetrievedFromUnderlyingStorage() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })
            #expect(sut.popoverShownDate == nil)
            try keyValueStoringMock.set(now.timeIntervalSince1970, forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.popoverShownDate.rawValue)

            // WHEN
            let result = sut.popoverShownDate

            // THEN
            #expect(result == now.timeIntervalSince1970)
        }

        @Test("Check Banner Shown Date Is Persisted")
        func checkBannerShownDateIsPersistedInUnderlyingStorage() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerShownDate.rawValue) == nil)

            // WHEN
            sut.bannerShownDate = now.timeIntervalSince1970

            // THEN
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerShownDate.rawValue) as? TimeInterval == now.timeIntervalSince1970)
        }

        @Test("Check Banner Shown Date Is Retrieved")
        func checkBannerShownDateIsRetrievedFromUnderlyingStorage() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })
            #expect(sut.bannerShownDate == nil)
            try keyValueStoringMock.set(now.timeIntervalSince1970, forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerShownDate.rawValue)

            // WHEN
            let result = sut.bannerShownDate

            // THEN
            #expect(result == now.timeIntervalSince1970)
        }

        @Test("Check Banner Permanently Dismissed Value Is Persisted")
        func checkBannerPermanentlyDismissedValueIsPersistedInUnderlyingStorage() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerPermanentlyDismissed.rawValue) == nil)

            // WHEN
            sut.isBannerPermanentlyDismissed = true

            // THEN
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerPermanentlyDismissed.rawValue) as? Bool == true)
        }

        @Test("Check Banner Permanently Dismissed Value Is Retrieved")
        func checkBannerPermanentlyDismissedValueIsRetrievedFromUnderlyingStorage() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            try keyValueStoringMock.set(true, forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerPermanentlyDismissed.rawValue)
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })

            // WHEN
            let result = sut.isBannerPermanentlyDismissed

            // THEN
            #expect(result)
        }

        @Test("Check Banner Permanently Dismissed Default Value Is False")
        func checkBannerPermanentlyDismissedDefaultValueIsFalse() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            #expect(try keyValueStoringMock.object(forKey: DefaultBrowserAndDockPromptKeyValueStore.StorageKey.bannerPermanentlyDismissed.rawValue) == nil)
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { _, _, _, _ in })

            // WHEN
            let result = sut.isBannerPermanentlyDismissed

            // THEN
            #expect(!result)
        }
    }

    struct EventMappingTests {

        @Test("Check Popover Failed To Save Event Is Triggered When Underlying Storage Fails To Save Value")
        func checkPopoverFailedToSaveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnSet = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            sut.popoverShownDate = now.timeIntervalSince1970

            // THEN
            if case let .storage(.failedToSaveValue(.popoverShownDate(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .popoverShownDate")
            }
        }

        @Test("Check Banner Failed To Save Event Is Triggered When Underlying Storage Fails To Save Value")
        func checkBannerFailedToSaveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnSet = expectedError
            var expectedEvents: [DefaultBrowserAndDockPromptDebugEvent] = []
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvents.append(event)
            })

            // WHEN
            sut.bannerShownDate = now.timeIntervalSince1970

            // THEN
            let failedToSaveBannerShownDateEvent = try #require(expectedEvents.first)
            let failedToSaveBannerShownOccurrences = try #require(expectedEvents.last)

            #expect(expectedEvents.count == 2)
            if case let .storage(.failedToSaveValue(.bannerShownDate(error as NSError))) = failedToSaveBannerShownDateEvent {
                #expect(error == expectedError)
            } else if case let .storage(.failedToSaveValue(.bannerShownOccurrences(error as NSError))) = failedToSaveBannerShownOccurrences {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .bannerShownDate")
            }
        }

        @Test("Check Banner Failed To Save Event Is Triggered When Underlying Storage Fails To Save Value")
        func checkBannerPermanentlyDismissedFailedToSaveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnSet = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            sut.isBannerPermanentlyDismissed = true

            // THEN
            if case let .storage(.failedToSaveValue(.permanentlyDismissPrompt(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .permanentlyDismissPrompt")
            }
        }

        @Test("Check Popover Failed To Retrieve Event Is Triggered When Underlying Storage Fails To Retrieve Value")
        func checkPopoverFailedToRetrieveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnRead = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            _ = sut.popoverShownDate

            // THEN
            if case let .storage(.failedToRetrieveValue(.popoverShownDate(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .popoverShownDate")
            }
        }

        @Test("Check Banner Failed To Retrieve Event Is Triggered When Underlying Storage Fails To Retrieve Value")
        func checkBannerFailedToRetrieveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnRead = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            _ = sut.bannerShownDate

            // THEN
            if case let .storage(.failedToRetrieveValue(.bannerShownDate(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .bannerShownDate")
            }
        }

        @Test("Check Permanently Dismissed Prompt Failed To Retrieve Event Is Triggered When Underlying Storage Fails To Retrieve Value")
        func checkPermanentlyDismissedPromptFailedToRetrieveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnRead = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            _ = sut.isBannerPermanentlyDismissed

            // THEN
            if case let .storage(.failedToRetrieveValue(.permanentlyDismissPrompt(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .permanentlyDismissPrompt")
            }
        }

        @Test("Check Failed To Save Number Banners Shown Is Event Is Triggered When Underlying Storage Fails To Save Value")
        func checkNumberOfBannersShownFailedToSaveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnSet = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            sut.bannerShownOccurrences = 10

            // THEN
            if case let .storage(.failedToSaveValue(.bannerShownOccurrences(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .bannerShownOccurrences")
            }
        }

        @Test("Check Failed To Retrieve Number Banners Shown Is Triggered When Underlying Storage Fails To Retrieve Value")
        func checkNumberOfBannersShownFailedToRetrieveValueEventIsSentWhenUnderlyingStorageFailsToPersist() throws {
            // GIVEN
            let keyValueStoringMock = try MockKeyValueFileStore()
            let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
            keyValueStoringMock.throwOnRead = expectedError
            var expectedEvent: DefaultBrowserAndDockPromptDebugEvent?
            let sut = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStoringMock, eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> { event, _, _, _ in
                expectedEvent = event
            })

            // WHEN
            _ = sut.bannerShownOccurrences

            // THEN
            if case let .storage(.failedToRetrieveValue(.bannerShownOccurrences(error as NSError))) = expectedEvent {
                #expect(error == expectedError)
            } else {
                Issue.record("Expected Event .bannerShownOccurrences")
            }
        }
    }

}
