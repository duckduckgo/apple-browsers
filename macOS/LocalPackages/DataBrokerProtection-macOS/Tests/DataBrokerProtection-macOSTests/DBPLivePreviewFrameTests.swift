//
//  DBPLivePreviewFrameTests.swift
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

#if DEBUG
import XCTest
import DataBrokerProtectionCore
@testable import DataBrokerProtection_macOS

final class DBPLivePreviewFrameTests: XCTestCase {
    func testPreviewFrameSurvivesSecureCoding() throws {
        let operationID = UUID()
        let source = PIRLivePreviewFrame(imageData: Data([0, 1, 2, 255]), operationID: operationID,
                                         brokerName: "Test broker", activity: "Checking page", needsAssistance: true)
        let frame = DBPLivePreviewFrame(frame: source)
        let data = try NSKeyedArchiver.archivedData(withRootObject: frame, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: DBPLivePreviewFrame.self, from: data))

        XCTAssertEqual(decoded.imageData, source.imageData)
        XCTAssertEqual(decoded.operationID, operationID.uuidString)
        XCTAssertEqual(decoded.brokerName, source.brokerName)
        XCTAssertEqual(decoded.activity, source.activity)
        XCTAssertTrue(decoded.needsAssistance)
    }
}
#endif
