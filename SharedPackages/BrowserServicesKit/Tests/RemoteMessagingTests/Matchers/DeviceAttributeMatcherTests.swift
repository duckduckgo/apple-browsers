//
//  DeviceAttributeMatcherTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Foundation
import RemoteMessagingTestsUtils
import Common
@testable import RemoteMessaging

class DeviceAttributeMatcherTests: XCTestCase {

    func testWhenDeviceMatchesLocaleThenReturnMatch() throws {
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute:
                                                         LocaleMatchingAttribute(value: [LocaleMatchingAttribute.localeIdentifierAsJsonFormat(Locale.current.identifier)], fallback: false)),
                       .match)
    }

    func testWhenDeviceMatchesAnyLocaleThenReturnMatch() throws {
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute:
                                                         LocaleMatchingAttribute(value: [LocaleMatchingAttribute.localeIdentifierAsJsonFormat(Locale.current.identifier), "en-US", "fr-FR", "fr-CA"],
                                                                                 fallback: false)),
                       .match)
    }

    func testWhenDeviceDoesNotMatchLocaleThenReturnFail() throws {
        XCTAssertEqual(DeviceAttributeMatcher(osVersion: AppVersion.shared.osVersion, locale: "will-not-match", formFactor: DevicePlatform.formFactor).evaluate(matchingAttribute: LocaleMatchingAttribute(value: ["en-US"], fallback: false)),
                       .fail)
    }

    func testWhenLocaleMatchingAttributeIsEmptyThenReturnFail() throws {
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute: LocaleMatchingAttribute(value: [], fallback: false)),
                       .fail)
    }

    func testWhenDeviceSameAsOsApiLevelThenReturnMatch() throws {
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute: OSMatchingAttribute(value: AppVersion.shared.osVersion, fallback: nil)),
                       .match)
    }

    func testWhenDeviceDifferentAsOsApiLevelThenReturnFail() throws {
        let os = ProcessInfo().operatingSystemVersion
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute:
                                                         OSMatchingAttribute(value: "\(os.majorVersion).\(os.minorVersion).Different",
                                                                             fallback: nil)),
                       .fail)
    }

    func testWhenDeviceMatchesOsApiLevelRangeThenReturnMatch() throws {
        let os = ProcessInfo().operatingSystemVersion
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute:
                                                         OSMatchingAttribute(max: String(os.majorVersion + 1), fallback: nil)),
                       .match)
    }

    func testWhenDeviceMatchesOsApiLevelMinThenReturnMatch() throws {
        let os = ProcessInfo().operatingSystemVersion
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute:
                                                         OSMatchingAttribute(min: String(os.majorVersion - 1), fallback: nil)),
                       .match)
    }

    func testWhenDeviceDoesNotMatchesOsApiLevelRangeThenReturnFail() throws {
        let os = ProcessInfo().operatingSystemVersion
        let osStringBump = "\(os.majorVersion).\(os.minorVersion + 1).\(os.patchVersion)"
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute: OSMatchingAttribute(min: "0.0", max: String(os.majorVersion - 1), fallback: nil)),
                       .fail)
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute: OSMatchingAttribute(min: osStringBump, max: String(os.majorVersion + 1), fallback: nil)),
                       .fail)
    }

    func testWhenOsApiMatchingAttributeEmptyThenReturnMatch() throws {
        XCTAssertEqual(DeviceAttributeMatcher().evaluate(matchingAttribute: OSMatchingAttribute(fallback: nil)),
                       .match)
    }

    func testWhenDeviceMatchesFormFactorThenReturnMatch() throws {
        let formFactor = DevicePlatform.formFactor
        XCTAssertEqual(
            DeviceAttributeMatcher(formFactor: formFactor)
                .evaluate(matchingAttribute: FormFactorMatchingAttribute(value: [formFactor], fallback: false)),
                .match)
    }

    func testWhenDeviceDoesNotMatchFormFactorThenReturnFail() throws {
        let formFactor = DevicePlatform.formFactor
        XCTAssertEqual(
            DeviceAttributeMatcher(formFactor: formFactor)
                .evaluate(matchingAttribute: FormFactorMatchingAttribute(value: ["SomeOtherDevice"], fallback: false)),
            .fail)
    }

    func testWhenFormFactorMatchingAttributeIsEmptyThenReturnFail() throws {
        XCTAssertEqual(
            DeviceAttributeMatcher()
                .evaluate(matchingAttribute: FormFactorMatchingAttribute(value: [], fallback: false)),
            .fail)
    }
}
