//
//  DataBrokerProtectionInMemoryCacheTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DataBrokerProtectionInMemoryCacheTests: XCTestCase {

    func testCacheStoresNewName() throws {
        let communicator = DBPUICommunicator()
        let result = communicator.addNameToCurrentUserProfile(DBPUIUserProfileName(first: "John", middle: "Jacob", last: "JingleHeimerSchmidt", suffix: nil))

        _ = communicator.setBirthYearForCurrentUserProfile(DBPUIBirthYear(year: 0))

        XCTAssert(result, "Adding name to profile cache failed")
        XCTAssert(communicator.profile?.names.count == 1, "There should be 1 name in the profile")
        XCTAssert(communicator.profile?.names.first?.firstName == "John", "The name stored in the cache is incorrect")
    }

    func testCacheDoesNotStoreDuplicateNames() throws {
        let communicator = DBPUICommunicator()
        var result = communicator.addNameToCurrentUserProfile(DBPUIUserProfileName(first: "John", middle: "Jacob", last: "JingleHeimerSchmidt", suffix: nil))

        XCTAssert(result, "Adding name to profile cache failed")

        result = communicator.addNameToCurrentUserProfile(DBPUIUserProfileName(first: "John", middle: "Jacob", last: "JingleHeimerSchmidt", suffix: nil))
        XCTAssertFalse(result, "Result of adding duplicate name should be `false`")
    }

    func testCacheDoesNotStoreEmptyNames() throws {
        let communicator = DBPUICommunicator()
        let result = communicator.addNameToCurrentUserProfile(DBPUIUserProfileName(first: "", middle: "Jacob", last: "JingleHeimerSchmidt", suffix: nil))

        XCTAssertFalse(result, "Result of adding empty name should be `false`")
    }

    func testCacheStoresNewAddress() throws {
        let communicator = DBPUICommunicator()
        let result = communicator.addAddressToCurrentUserProfile(DBPUIUserProfileAddress(street: "123 any street", city: "Any Town", state: "TX", zipCode: "12345"))
        _ = communicator.setBirthYearForCurrentUserProfile(DBPUIBirthYear(year: 0))

        XCTAssert(result, "Adding address to profile cache failed")
        XCTAssert(communicator.profile?.addresses.count == 1, "There should be 1 address in the profile")
        XCTAssert(communicator.profile?.addresses.first?.state == "TX", "The address stored in the cache is incorrect")
    }

    func testCacheDoesNotStoreDuplicateAddresses() throws {
        let communicator = DBPUICommunicator()
        var result = communicator.addAddressToCurrentUserProfile(DBPUIUserProfileAddress(street: "123 any street", city: "Any Town", state: "TX", zipCode: "12345"))

        XCTAssert(result, "Adding address to profile cache failed")

        result = communicator.addAddressToCurrentUserProfile(DBPUIUserProfileAddress(street: "123 any street", city: "Any Town", state: "TX", zipCode: "12345"))
        XCTAssertFalse(result, "Result of adding duplicate address should be `false`")
    }

    func testCacheDoesNotStoreEmptyAddresses() throws {
        let communicator = DBPUICommunicator()
        let result = communicator.addAddressToCurrentUserProfile(DBPUIUserProfileAddress(street: "123 any street", city: "", state: "TX", zipCode: "12345"))

        XCTAssertFalse(result, "Result of adding empty address should be `false`")
    }

    func testCacheSetBirthYear() throws {
        let communicator = DBPUICommunicator()
        let result = communicator.setBirthYearForCurrentUserProfile(DBPUIBirthYear(year: 1990))

        XCTAssert(result, "Setting birth year was not succcessful")
        XCTAssert(communicator.profile?.birthYear == 1990, "Birth year not set correctly")
    }

    func testCacheRemoveNameFromIndex() throws {
        let communicator = DBPUICommunicator()
        var result = communicator.addNameToCurrentUserProfile(DBPUIUserProfileName(first: "John", middle: "Jacob", last: "JingleHeimerSchmidt", suffix: nil))
        _ = communicator.setBirthYearForCurrentUserProfile(DBPUIBirthYear(year: 0))

        XCTAssert(result, "Adding name to profile cache failed")
        XCTAssert(communicator.profile?.names.count == 1, "There should be 1 name in the profile")

        result = communicator.removeNameAtIndexFromUserProfile(DBPUIIndex(index: 0))

        XCTAssert(result, "Removing name from profile cache failed")
        XCTAssert(communicator.profile?.names.isEmpty ?? false, "The name was not removed from the cache")
    }

    func testCacheRemoveAddressFromIndex() throws {
        let communicator = DBPUICommunicator()
        var result = communicator.addAddressToCurrentUserProfile(DBPUIUserProfileAddress(street: "123 any street", city: "Any Town", state: "TX", zipCode: "12345"))
        _ = communicator.setBirthYearForCurrentUserProfile(DBPUIBirthYear(year: 0))

        XCTAssert(result, "Adding address to profile cache failed")
        XCTAssert(communicator.profile?.addresses.count == 1, "There should be 1 address in the profile")

        result = communicator.removeAddressAtIndexFromUserProfile(DBPUIIndex(index: 0))

        XCTAssert(result, "Removing address from profile cache failed")
        XCTAssert(communicator.profile?.names.isEmpty ?? false, "The address was not removed from the cache")
    }

}
