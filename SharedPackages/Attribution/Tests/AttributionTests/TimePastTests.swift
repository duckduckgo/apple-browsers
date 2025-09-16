//
//  TimePastTests.swift
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
@testable import Attribution

final class TimePastTests: XCTestCase {

    let testDate = Date(timeIntervalSince1970: 434720061)
}

// MARK: - TimePast Tests

extension TimePastTests {
    
    func testTimePastCalculation() {
        let installDate = testDate
        
        // Less than 1 week - should return .none
        let day2 = Calendar.current.date(byAdding: .day, value: 2, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day2, andInstallationDate: installDate), .none)
        
        let day3 = Calendar.current.date(byAdding: .day, value: 3, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day3, andInstallationDate: installDate), .none)
        
        let day4 = Calendar.current.date(byAdding: .day, value: 4, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day4, andInstallationDate: installDate), .none)
        
        // Week 1 boundary tests
        let day6 = Calendar.current.date(byAdding: .day, value: 6, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day6, andInstallationDate: installDate), .none)
        
        let week1Date = Calendar.current.date(byAdding: .day, value: 7, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: week1Date, andInstallationDate: installDate), .weeks(1))
        
        let day8 = Calendar.current.date(byAdding: .day, value: 8, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day8, andInstallationDate: installDate), .weeks(1))
        
        // Week 2 boundary tests
        let day13 = Calendar.current.date(byAdding: .day, value: 13, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day13, andInstallationDate: installDate), .weeks(1))
        
        let week2Date = Calendar.current.date(byAdding: .day, value: 14, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: week2Date, andInstallationDate: installDate), .weeks(2))
        
        let day15 = Calendar.current.date(byAdding: .day, value: 15, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day15, andInstallationDate: installDate), .weeks(2))
        
        // Week 3 boundary tests
        let day20 = Calendar.current.date(byAdding: .day, value: 20, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day20, andInstallationDate: installDate), .weeks(2))
        
        let week3Date = Calendar.current.date(byAdding: .day, value: 21, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: week3Date, andInstallationDate: installDate), .weeks(3))
        
        let day22 = Calendar.current.date(byAdding: .day, value: 22, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day22, andInstallationDate: installDate), .weeks(3))
        
        // Week 4 = Month 1 boundary tests (28 days)
        let day27 = Calendar.current.date(byAdding: .day, value: 27, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day27, andInstallationDate: installDate), .weeks(3))
        
        let month1Date = Calendar.current.date(byAdding: .day, value: 28, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: month1Date, andInstallationDate: installDate), .months(1))
        
        let day29 = Calendar.current.date(byAdding: .day, value: 29, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day29, andInstallationDate: installDate), .months(1))

        // Month 2 boundary tests (56 days)
        let day55 = Calendar.current.date(byAdding: .day, value: 55, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day55, andInstallationDate: installDate), .months(1))

        let week8Date = Calendar.current.date(byAdding: .day, value: 56, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: week8Date, andInstallationDate: installDate), .months(2))
        
        let day57 = Calendar.current.date(byAdding: .day, value: 57, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day57, andInstallationDate: installDate), .months(2))
        
        // Week 16 = Month 4 boundary tests (112 days)
        let day111 = Calendar.current.date(byAdding: .day, value: 111, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day111, andInstallationDate: installDate), .months(3))
        
        let month4Date = Calendar.current.date(byAdding: .day, value: 112, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: month4Date, andInstallationDate: installDate), .months(4))
        
        let day113 = Calendar.current.date(byAdding: .day, value: 113, to: installDate)!
        XCTAssertEqual(TimePast.timePastFrom(date: day113, andInstallationDate: installDate), .months(4))
    }
}
