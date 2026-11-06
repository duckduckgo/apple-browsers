//
//  DaxOutfitTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class DaxOutfitTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .distantPast
    }

    // MARK: - Seasons

    func testHalloweenWeekBringsTheWitchHat() {
        XCTAssertNil(DaxOutfit.seasonal(on: date(10, 23), calendar: calendar))
        XCTAssertEqual(DaxOutfit.seasonal(on: date(10, 24), calendar: calendar), .witchHat)
        XCTAssertEqual(DaxOutfit.seasonal(on: date(10, 31), calendar: calendar), .witchHat)
        XCTAssertNil(DaxOutfit.seasonal(on: date(11, 1), calendar: calendar))
    }

    func testDecemberBringsTheSantaHatUntilNewYearsEve() {
        XCTAssertEqual(DaxOutfit.seasonal(on: date(12, 1), calendar: calendar), .santaHat)
        XCTAssertEqual(DaxOutfit.seasonal(on: date(12, 30), calendar: calendar), .santaHat)
        XCTAssertEqual(DaxOutfit.seasonal(on: date(12, 31), calendar: calendar), .partyHat)
    }

    func testNewYearsDayKeepsThePartyHatThenItComesOff() {
        XCTAssertEqual(DaxOutfit.seasonal(on: date(1, 1), calendar: calendar), .partyHat)
        XCTAssertNil(DaxOutfit.seasonal(on: date(1, 2), calendar: calendar))
    }

    // MARK: - Wardrobe

    func testTheWardrobeDressesForTheSeasonByDefault() {
        XCTAssertEqual(DaxWardrobe(rawValue: nil), .seasonal)
        XCTAssertEqual(DaxWardrobe(rawValue: "something-unknown"), .seasonal)
        XCTAssertEqual(DaxWardrobe.seasonal.outfit(on: date(10, 31), calendar: calendar), .witchHat)
    }

    func testAChosenOutfitIsWornAllYearAndNothingMeansNothing() {
        XCTAssertEqual(DaxWardrobe.outfit(.partyHat).outfit(on: date(6, 1), calendar: calendar), .partyHat)
        XCTAssertNil(DaxWardrobe.none.outfit(on: date(12, 25), calendar: calendar))
    }

    func testTheWardrobeRoundTripsThroughItsStoredValue() {
        for wardrobe in [DaxWardrobe.seasonal, .none] + DaxOutfit.allCases.map(DaxWardrobe.outfit) {
            XCTAssertEqual(DaxWardrobe(rawValue: wardrobe.rawValue), wardrobe)
        }
    }

    // MARK: - Rig

    func testEachOutfitIsDrawnOnTopOfDaxAndMovesWithHim() throws {
        for outfit in DaxOutfit.allCases {
            let rig = try XCTUnwrap(DaxRig(outfit: outfit))
            XCTAssertEqual(rig.outfit, outfit)
            XCTAssertEqual(outfit.layer["parent"] as? Int, 1, "parented to CTRL_Dax")
        }
        XCTAssertNil(try XCTUnwrap(DaxRig()).outfit)
    }
}
