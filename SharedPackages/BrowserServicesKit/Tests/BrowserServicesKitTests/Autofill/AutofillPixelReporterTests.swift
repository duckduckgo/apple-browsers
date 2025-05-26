//
//  AutofillPixelReporterTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import SecureStorage
import SecureStorageTestsUtils
@testable import BrowserServicesKit

final class AutofillPixelReporterTests: XCTestCase {

    private class MockEventMapping: EventMapping<AutofillPixelEvent> {
        static var events: [AutofillPixelEvent] = []
        static var loginsParam: String?
        static var creditCardsParam: String?
        static var identitiesParam: String?

        public init() {
            super.init { event, _, param, _ in
                Self.events.append(event)
                switch event {
                case .autofillLoginsStacked:
                    Self.loginsParam = param?[AutofillPixelEvent.Parameter.countBucket]
                case .autofillCreditCardsStacked:
                    Self.creditCardsParam = param?[AutofillPixelEvent.Parameter.countBucket]
                case .autofillIdentitiesStacked:
                    Self.identitiesParam = param?[AutofillPixelEvent.Parameter.countBucket]
                default:
                    break
                }
            }
        }

        override init(mapping: @escaping EventMapping<AutofillPixelEvent>.Mapping) {
            fatalError("Use init()")
        }
    }

    private var mockCryptoProvider = MockCryptoProvider()
    private var mockDatabaseProvider = (try! MockAutofillDatabaseProvider())
    private var mockKeystoreProvider = MockKeystoreProvider()
    private var vault: (any AutofillSecureVault)!
    private var eventMapping: MockEventMapping!
    private var standardDefaults: UserDefaults!
    private var appGroupDefaults: UserDefaults!
    private let testStandardName = "autofill-reporter"
    private let testGroupName = "autofill-reporter-group"

    override func setUpWithError() throws {
        try super.setUpWithError()

        standardDefaults = UserDefaults(suiteName: testStandardName)!
        appGroupDefaults = UserDefaults(suiteName: testGroupName)!
        standardDefaults.removePersistentDomain(forName: testStandardName)
        appGroupDefaults.removePersistentDomain(forName: testGroupName)

        let providers = SecureStorageProviders(crypto: mockCryptoProvider,
                                               database: mockDatabaseProvider,
                                               keystore: mockKeystoreProvider)

        vault = DefaultAutofillSecureVault(providers: providers)

        eventMapping = MockEventMapping()
        MockEventMapping.events.removeAll()
    }

    override func tearDownWithError() throws {
        vault = nil
        eventMapping = nil
        standardDefaults.removePersistentDomain(forName: testStandardName)
        appGroupDefaults.removePersistentDomain(forName: testGroupName)

        try super.tearDownWithError()
    }

    func testWhenFirstFillAndSearchDauIsNotTodayThenNoEventsAreFired() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()

        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenFirstFillAndSearchDauIsTodayAndAccountsCountIsZeroThenFourEventsAreFiredWithNoneParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        setAutofillSearchDauDate(daysAgo: 0)

        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 4)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndAutofillDisabledAndFillDateIsNotTodayAndAccountsCountIsZeroThenOneEventIsFired() throws {
        let autofillPixelReporter = createAutofillPixelReporter(autofillEnabled: false)
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)

        NotificationCenter.default.post(name: .searchDAU, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 1)
        let event = try XCTUnwrap(MockEventMapping.events.first)
        XCTAssertEqual(event, .autofillToggledOff)
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndAutofillEnabledAndFillDateIsNotTodayAndAccountsCountIsZeroThenOneEventIsFired() throws {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)

        NotificationCenter.default.post(name: .searchDAU, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 1)
        let event = try XCTUnwrap(MockEventMapping.events.first)
        XCTAssertEqual(event, .autofillToggledOn)
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndAutofillDisabledAndFillDateIsNotTodayAndAndAccountsCountIsTenThenThenOneEventIsFired() throws {
        let autofillPixelReporter = createAutofillPixelReporter(autofillEnabled: false)
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 10)

        NotificationCenter.default.post(name: .searchDAU, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 1)
        let event = try XCTUnwrap(MockEventMapping.events.first)
        XCTAssertEqual(event, .autofillToggledOff)
    }

    func testWhenFirstSearchDauAndAutofillEnabledAndFillDateIsNotTodayAndAndAccountsCountIsTenThenThenTwoEventsAreFired() throws {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 10)

        NotificationCenter.default.post(name: .searchDAU, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 2)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillEnabledUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
    }

    func testWhenFirstSearchDauAndThenFirstFillAndAccountsCountIsZeroThenFiveEventsAreFiredWithNoneParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndAccountsCountIsThreeThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 3)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.few.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndAccountsCountIsTenThenSixEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 10)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 6)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillEnabledUser))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.some.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndAccountsCountIsElevenThenSixEventsAreFiredWithManyParam() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 11)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 6)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillEnabledUser))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.many.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndAccountsCountIsFortyThenSixEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 40)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 6)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillEnabledUser))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.many.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndAccountsCountIsFiftyThenSixEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 50)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 6)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillEnabledUser))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.lots.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndCreditCardsCountIsOneThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)
        createCreditCardsInVault(count: 1)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.some.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndCreditCardsCountIsThreeThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)
        createCreditCardsInVault(count: 3)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.some.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

     func testWhenFirstSearchDauAndThenFirstFillAndCreditCardsCountIsFourThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)
        createCreditCardsInVault(count: 4)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
         XCTAssertTrue(MockEventMapping.events.contains(.autofillToggledOn))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.many.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.none.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndIdentitiesCountIsOneThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)
        createCreditCardsInVault(count: 0)
        createIdentitiesInVault(count: 1)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.some.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndIdentitiesCountIsFourThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)
        createCreditCardsInVault(count: 0)
        createIdentitiesInVault(count: 4)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.some.rawValue)
    }

     func testWhenFirstSearchDauAndThenFirstFillAndIdentitiesCountIsFiveThenFiveEventsAreFiredWithCorrectParams() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)
        createIdentitiesInVault(count: 5)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 5)
        XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
        XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
        XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
        XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.many.rawValue)
    }

    func testWhenFirstSearchDauAndThenFirstFillAndIdentitiesCountIsTwelveThenFiveEventsAreFiredWithCorrectParams() {
       let autofillPixelReporter = createAutofillPixelReporter()
       autofillPixelReporter.resetStoreDefaults()
       createAccountsInVault(count: 0)
       createIdentitiesInVault(count: 12)

       NotificationCenter.default.post(name: .searchDAU, object: nil)
       NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

       XCTAssertEqual(MockEventMapping.events.count, 5)
       XCTAssertTrue(MockEventMapping.events.contains(.autofillActiveUser))
       XCTAssertTrue(MockEventMapping.events.contains(.autofillLoginsStacked))
       XCTAssertTrue(MockEventMapping.events.contains(.autofillCreditCardsStacked))
       XCTAssertTrue(MockEventMapping.events.contains(.autofillIdentitiesStacked))
       XCTAssertEqual(MockEventMapping.loginsParam, AutofillPixelReporter.BucketName.none.rawValue)
       XCTAssertEqual(MockEventMapping.creditCardsParam, AutofillPixelReporter.BucketName.none.rawValue)
       XCTAssertEqual(MockEventMapping.identitiesParam, AutofillPixelReporter.BucketName.lots.rawValue)
   }

    func testWhenSubsequentFillAndSearchDauIsNotTodayThenNoEventsAreFired() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        setAutofillSearchDauDate(daysAgo: 1)

        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenSubsequentFillAndSearchDauIsTodayThenNoEventsAreFired() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        setAutofillSearchDauDate(daysAgo: 0)
        setAutofillFillDate(daysAgo: 0)

        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenSubsequentSearchDauAndFillDateIsNotTodayThenNoEventsAreFired() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        setAutofillSearchDauDate(daysAgo: 0)

        NotificationCenter.default.post(name: .searchDAU, object: nil)
        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenSubsequentSearchDauAndFillDateIsTodayThenNoEventsAreFired() {
        let autofillPixelReporter = createAutofillPixelReporter()
        autofillPixelReporter.resetStoreDefaults()
        setAutofillSearchDauDate(daysAgo: 0)
        setAutofillFillDate(daysAgo: 0)

        NotificationCenter.default.post(name: .searchDAU, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenSaveAndUserIsAlreadyOnboardedThenOnboardedUserPixelShouldNotBeFired() {
        let autofillPixelReporter = createAutofillPixelReporter(installDate: Date().addingTimeInterval(.days(-1)))
        autofillPixelReporter.resetStoreDefaults()
        standardDefaults.set(true, forKey: AutofillPixelReporter.Keys.autofillOnboardedUserKey)

        NotificationCenter.default.post(name: .autofillSaveEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenSaveAndNotOnboardedAndInstallDateIsNilThenOnboardedUserPixelShouldNotBeFired() {
        let autofillPixelReporter = createAutofillPixelReporter(installDate: nil)
        autofillPixelReporter.resetStoreDefaults()

        NotificationCenter.default.post(name: .autofillSaveEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenUserIsNotOnboardedAndInstallDateIsLessThanSevenDaysAgoAndAccountsCountIsZeroThenOnboardedUserPixelShouldNotBeFired() {
        let autofillPixelReporter = createAutofillPixelReporter(installDate: Date().addingTimeInterval(.days(-4)))
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 0)

        NotificationCenter.default.post(name: .autofillSaveEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
    }

    func testWhenUserIsNotOnboardedAndInstallDateIsLessThanSevenDaysAgoAndAccountsCountIsGreaterThanZeroThenOnboardedUserPixelShouldBeFiredAndAutofillOnboardedUserShouldBeTrue() throws {
        let autofillPixelReporter = createAutofillPixelReporter(installDate: Date().addingTimeInterval(.days(-4)))
        autofillPixelReporter.resetStoreDefaults()
        createAccountsInVault(count: 1)

        NotificationCenter.default.post(name: .autofillSaveEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 1)
        let event = try XCTUnwrap(MockEventMapping.events.first)
        XCTAssertEqual(event, .autofillOnboardedUser)
        let onboardedState = try XCTUnwrap(getAutofillOnboardedUserState())
        XCTAssertTrue(onboardedState)
    }

    func testWhenUserIsNotOnboardedAndInstallDateIsGreaterThanSevenDaysAgoThenOnboardedUserPixelShouldNotBeFiredAndAutofillOnboardedUserShouldBeTrue() throws {
        let autofillPixelReporter = createAutofillPixelReporter(installDate: Date().addingTimeInterval(.days(-8)))
        autofillPixelReporter.resetStoreDefaults()

        NotificationCenter.default.post(name: .autofillSaveEvent, object: nil)

        XCTAssertEqual(MockEventMapping.events.count, 0)
        let onboardedState = try XCTUnwrap(getAutofillOnboardedUserState())
        XCTAssertTrue(onboardedState)
    }

    func testWhenMigrationRequiredAndDataExistsThenDataIsMigratedToAppGroupUserDefaults() {
        let testDate = Date()
        standardDefaults.set(testDate, forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey)
        standardDefaults.set(testDate, forKey: AutofillPixelReporter.Keys.autofillFillDateKey)
        standardDefaults.set(true, forKey: AutofillPixelReporter.Keys.autofillOnboardedUserKey)

        _ = createAutofillPixelReporter(appGroupUserDefaults: appGroupDefaults)

        XCTAssertEqual(appGroupDefaults.object(forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey) as? Date, testDate)
        XCTAssertEqual(appGroupDefaults.bool(forKey: AutofillPixelReporter.Keys.autofillOnboardedUserKey), true)
        XCTAssertNil(standardDefaults.object(forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey))
        XCTAssertTrue(appGroupDefaults.bool(forKey: AutofillPixelReporter.Keys.autofillDauMigratedKey))
    }

    func testWhenMigrationRequiredAndNoDataExistsThenMigratedKeyIsTrue() {
        _ = createAutofillPixelReporter(appGroupUserDefaults: appGroupDefaults)

        XCTAssertTrue(appGroupDefaults.bool(forKey: AutofillPixelReporter.Keys.autofillDauMigratedKey))
        XCTAssertNil(appGroupDefaults.object(forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey))
        XCTAssertNil(appGroupDefaults.object(forKey: AutofillPixelReporter.Keys.autofillFillDateKey))
        XCTAssertNil(appGroupDefaults.object(forKey: AutofillPixelReporter.Keys.autofillOnboardedUserKey))
    }

    func testWhenMigrationCompleteThenMigrationDoesNotSecondTime() {
        let testDate = Date()
        standardDefaults.set(testDate, forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey)
        appGroupDefaults.set(true, forKey: AutofillPixelReporter.Keys.autofillDauMigratedKey)

        _ = createAutofillPixelReporter(appGroupUserDefaults: appGroupDefaults)

        XCTAssertNotNil(standardDefaults.object(forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey))
        XCTAssertNil(appGroupDefaults.object(forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey))
    }

    func testWhenNilAppGroupUserDefaultsProvidedThenNoMigrationOccurs() {
        let testDate = Date()
        standardDefaults.set(testDate, forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey)

        _ = createAutofillPixelReporter(appGroupUserDefaults: nil)

        XCTAssertNotNil(standardDefaults.object(forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey))
        XCTAssertNil(appGroupDefaults.object(forKey: AutofillPixelReporter.Keys.autofillDauMigratedKey))
    }

    private func createAutofillPixelReporter(appGroupUserDefaults: UserDefaults? = nil, installDate: Date? = Date(), autofillEnabled: Bool = true) -> AutofillPixelReporter {
        return AutofillPixelReporter(standardUserDefaults: standardDefaults,
                                     appGroupUserDefaults: appGroupUserDefaults,
                                     autofillEnabled: autofillEnabled,
                                     eventMapping: eventMapping,
                                     secureVault: vault,
                                     installDate: installDate)
    }

    private func createAccountsInVault(count: Int) {
        try? vault.deleteAllWebsiteCredentials()

        for i in 0..<count {
            mockDatabaseProvider._accounts.append(SecureVaultModels.WebsiteAccount(username: "dax-\(i)@duck.com", domain: "domain.com"))
        }
    }

    private func createCreditCardsInVault(count: Int) {
        let creditCards = try? vault.creditCards()
        for card in creditCards ?? [] {
            if let id = card.id {
                try? vault.deleteCreditCardFor(cardId: id)
            }
        }

        for i in 0..<count {
            mockDatabaseProvider._creditCards[Int64(i)] = SecureVaultModels.CreditCard(cardNumber: "1234 5678 9012 345\(i)",
                                                                                       cardholderName: "Dax \(i)",
                                                                                       cardSecurityCode: nil,
                                                                                       expirationMonth: 12,
                                                                                       expirationYear: 24)
        }
    }

    private func createIdentitiesInVault(count: Int) {
        let identities = try? vault.identities()
        for identity in identities ?? [] {
            if let id = identity.id {
                try? vault.deleteIdentityFor(identityId: id)
            }
        }

        for i in 0..<count {
            mockDatabaseProvider._identities[Int64(i)] = SecureVaultModels.Identity(title: "Identity \(i)",
                                                                                    created: Date(),
                                                                                    lastUpdated: Date(),
                                                                                    firstName: "Dax \(i)",
                                                                                    lastName: "Duck")
        }
    }

    private func setAutofillSearchDauDate(daysAgo: Int) {
        let date = Date().addingTimeInterval(.days(-daysAgo))
        standardDefaults.set(date, forKey: AutofillPixelReporter.Keys.autofillSearchDauDateKey)
    }

    private func setAutofillFillDate(daysAgo: Int) {
        let date = Date().addingTimeInterval(.days(-daysAgo))
        standardDefaults.set(date, forKey: AutofillPixelReporter.Keys.autofillFillDateKey)
    }

    private func getAutofillOnboardedUserState() -> Bool? {
        return standardDefaults.object(forKey: AutofillPixelReporter.Keys.autofillOnboardedUserKey) as? Bool
    }

}
