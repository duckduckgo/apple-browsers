//
//  CrashLogMessageExtractorTests.swift
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

@testable import Crashes
import MetricKit
import XCTest

final class CrashLogMessageExtractorTests: XCTestCase {

    private var fileManager: FileManagerMock!
    private var extractor: CrashLogMessageExtractor!
    private let formatter = ISO8601DateFormatter()

    override func setUp() {
        fileManager = FileManagerMock()
        extractor = CrashLogMessageExtractor(fileManager: fileManager)
    }

    func testWhenNoDiagnosticsDirectory_noCrashDiagnosticReturned() {
        fileManager.contents = []
        let r = extractor.crashDiagnostic(for: Date(), pid: 1)
        XCTAssertNil(r)
    }

    func testWhenFileManagerThrows_noCrashDiagnosticReturned() {
        fileManager.error = CocoaError(CocoaError.Code.fileNoSuchFile)
        let r = extractor.crashDiagnostic(for: Date(), pid: 1)
        XCTAssertNil(r)
    }

    func testWhenMultipleDiagnosticsWithSameMinuteTimestamp_latestIsChosen() {
        fileManager.contents = [
            "2024-07-05T09:36:15Z-101.log",
            "2024-07-05T09:36:56Z-102.log", // <-
            "2024-07-05T09:36:11Z-103.log",
            "2024-07-05T08:36:15Z-104.log",
            "2024-07-05T010:36:15Z-105.log",
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2024-07-05T09:36:00Z"), pid: nil)

        XCTAssertEqual(r?.url, fileManager.diagnosticsDirectory.appendingPathComponent(fileManager.contents[1]))
        XCTAssertEqual(r?.timestamp, formatter.date(from: "2024-07-05T09:36:56Z"))
        XCTAssertEqual(r?.pid, 102)
    }

    func testWhenMultipleDiagnosticsWithSameMinuteTimestampAndPid_latestWithMatchingPidIsChosen() {
        fileManager.contents = [
            "2024-07-05T09:36:15Z-101.log",
            "2024-07-05T09:36:56Z-102.log",
            "2024-07-05T09:36:21Z-101.log", // <-
            "2024-07-05T08:36:15Z-101.log",
            "2024-07-05T010:36:15Z-101.log",
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2024-07-05T09:36:00Z"), pid: 101)

        XCTAssertEqual(r?.url, fileManager.diagnosticsDirectory.appendingPathComponent(fileManager.contents[2]))
        XCTAssertEqual(r?.timestamp, formatter.date(from: "2024-07-05T09:36:21Z"))
        XCTAssertEqual(r?.pid, 101)
    }

    func testCrashDiagnosticWritingAndReading() throws {
        let fm = FileManager.default
        let referenceDate = Date()
        let date = formatter.string(from: referenceDate)
        let fileName = "\(date)-\(ProcessInfo().processIdentifier).log"
        let dir = fm.temporaryDirectory
        let url = dir.appendingPathComponent(fileName)
        extractor = CrashLogMessageExtractor(diagnosticsDirectory: dir, dateProvider: { referenceDate })

        let exception =  NSException(name: NSExceptionName(rawValue: "TestException"), reason: "Test crash message /with/file/path", userInfo: ["key1": "value1"])
        exception.setValue(["callStackSymbols": [
            "0   CoreFoundation                      0x00000001930072ec __exceptionPreprocess + 176,",
            "1   libobjc.A.dylib                     0x0000000192aee788 objc_exception_throw + 60,",
            "2   AppKit                              0x00000001968dc20c -[NSTableRowData _availableRowViewWhileUpdatingAtRow:] + 0,",
        ]], forKey: "reserved")

        try extractor.writeDiagnostic(for: exception)

        guard let diag = extractor.crashDiagnostic(for: referenceDate, pid: ProcessInfo().processIdentifier) else {
            XCTFail("could not find crash diagnostic")
            return
        }
        XCTAssertEqual(diag.url, url)
        XCTAssertEqual(formatter.string(from: diag.timestamp), date)
        XCTAssertEqual(diag.pid, ProcessInfo().processIdentifier)

        let r = try diag.diagnosticData()
        let resultJson = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r))
        XCTAssertEqual(resultJson as! NSDictionary, [
            "message": """
            TestException: Test crash message <removed>
            key1: value1
            """,
            "stackTrace": [
                "0   CoreFoundation                      0x00000001930072ec __exceptionPreprocess + 176,",
                "1   libobjc.A.dylib                     0x0000000192aee788 objc_exception_throw + 60,",
                "2   AppKit                              0x00000001968dc20c -[NSTableRowData _availableRowViewWhileUpdatingAtRow:] + 0,",
            ]
        ] as NSDictionary)
    }

}

private class FileManagerMock: FileManager {

    var error: Error?
    var contents = [String]()

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        XCTAssertEqual(path, self.diagnosticsDirectory.path)
        if let error {
            throw error
        }
        return contents
    }

}
