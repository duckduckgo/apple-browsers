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
import CxxCrashHandler
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

    func testWhenMultipleDiagnosticsNearTimestamp_closestIsChosen() {
        fileManager.contents = [
            "2024-07-05T09:36:15Z-101.log",
            "2024-07-05T09:36:56Z-102.log",
            "2024-07-05T09:36:11Z-103.log", // <- closest to the crash timestamp
            "2024-07-05T08:36:15Z-104.log",
            "2024-07-05T010:36:15Z-105.log",
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2024-07-05T09:36:00Z"), pid: nil)

        XCTAssertEqual(r?.url, fileManager.diagnosticsDirectory.appendingPathComponent(fileManager.contents[2]))
        XCTAssertEqual(r?.timestamp, formatter.date(from: "2024-07-05T09:36:11Z"))
        XCTAssertEqual(r?.pid, 103)
    }

    // MetricKit rounds `timeStampBegin` to the *nearest* minute (a crash at 11:20:39 is reported
    // as 11:21:00), so a diagnostic written a few seconds before the reported minute must match.
    func testWhenCrashTimestampIsRoundedUpToNextMinute_diagnosticIsChosen() {
        fileManager.contents = ["2026-10-19T11:20:39Z-519.log"]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:21:00Z"), pid: nil)

        XCTAssertEqual(r?.pid, 519)
        XCTAssertEqual(r?.timestamp, formatter.date(from: "2026-10-19T11:20:39Z"))
    }

    func testWhenTwoDiagnosticsAreEquidistant_latestIsChosen() {
        fileManager.contents = [
            "2026-10-19T11:20:50Z-519.log",
            "2026-10-19T11:21:10Z-520.log", // <- same distance, later
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:21:00Z"), pid: nil)

        XCTAssertEqual(r?.pid, 520)
    }

    func testWhenDiagnosticIsOutsideTheToleranceWindow_noCrashDiagnosticReturned() {
        fileManager.contents = [
            "2026-10-19T11:20:27Z-519.log", // 33s before the reported minute
            "2026-10-19T11:21:31Z-520.log", // 31s after the reported minute
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:21:00Z"), pid: nil)

        XCTAssertNil(r)
    }

    // The file is written before the abort and its name is truncated to whole seconds: a crash at 11:20:29.9
    // produces `11:20:29Z` while MetricKit rounds the real crash time (≥ 11:20:30) up to 11:21:00 — 31s apart.
    func testWhenDiagnosticIsWrittenJustBeforeTheHalfMinute_diagnosticIsChosen() {
        fileManager.contents = ["2026-10-19T11:20:29Z-519.log"]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:21:00Z"), pid: nil)

        XCTAssertEqual(r?.pid, 519)
    }

    // macOS crash reports carry the real pid; a delayed report timestamp must not drop the pid-matched diagnostic.
    func testWhenPidMatches_timestampDistanceDoesNotRejectDiagnostic() {
        fileManager.contents = ["2026-10-19T11:20:05Z-519.log"]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:24:40Z"), pid: 519)

        XCTAssertEqual(r?.pid, 519)
    }

    // Crash loop: an NSException crash at 11:33:10 (reported as 11:33:00) followed by an unrelated crash
    // at 11:33:46 (reported as 11:34:00). The second report must not pick up the first crash's message.
    func testWhenAnotherCrashHappensLaterInTheSameMinute_itsReportDoesNotGetTheEarlierDiagnostic() {
        fileManager.contents = ["2026-10-19T11:33:10Z-659.log"]

        XCTAssertEqual(extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:33:00Z"), pid: nil)?.pid, 659)
        XCTAssertNil(extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:34:00Z"), pid: nil))
    }

    // pid is the primary key; when no file matches it, fall back to the time window.
    func testWhenPidDoesNotMatch_fallsBackToDiagnosticWithinTimeWindow() {
        fileManager.contents = ["2026-10-19T11:20:39Z-519.log"]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:21:00Z"), pid: 546)

        XCTAssertEqual(r?.pid, 519)
    }

    func testWhenPidMatchesAndOtherFilesAreCloserInTime_pidMatchWins() {
        fileManager.contents = [
            "2026-10-19T11:20:59Z-700.log", // closest in time, different pid
            "2026-10-19T11:18:30Z-519.log", // <- matching pid
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2026-10-19T11:21:00Z"), pid: 519)

        XCTAssertEqual(r?.pid, 519)
    }

    func testWhenMultipleDiagnosticsNearTimestampAndPid_closestWithMatchingPidIsChosen() {
        fileManager.contents = [
            "2024-07-05T09:36:15Z-101.log", // <- closest to the crash timestamp with matching pid
            "2024-07-05T09:36:11Z-102.log",
            "2024-07-05T09:36:21Z-101.log",
            "2024-07-05T08:36:15Z-101.log",
            "2024-07-05T010:36:15Z-101.log",
        ]

        let r = extractor.crashDiagnostic(for: formatter.date(from: "2024-07-05T09:36:00Z"), pid: 101)

        XCTAssertEqual(r?.url, fileManager.diagnosticsDirectory.appendingPathComponent(fileManager.contents[0]))
        XCTAssertEqual(r?.timestamp, formatter.date(from: "2024-07-05T09:36:15Z"))
        XCTAssertEqual(r?.pid, 101)
    }

    // Tests the `throw;` path — the only safe way to drive it is from inside a C++ catch block.
    //
    // `_currentCxxExceptionInsideCatchBlock()` throws a `std::runtime_error` and then calls
    // `currentCxxException()` from the resulting catch block.  With an active exception and a
    // real catch context, `__cxa_current_exception_type()` returns non-null, the ObjC guard is
    // false, and `throw;` / `catch(std::exception& exc)` runs as intended.
    func testCurrentCxxException_withActiveCxxExceptionInCatchBlock_returnsExceptionWithDescription() {
        let exception = _currentCxxExceptionInsideCatchBlock()
        XCTAssertNotNil(exception)
        XCTAssertEqual(exception?.reason, "test cxx exception")
    }

    // Tests that callStackSymbols on the returned exception is the throw-site stack captured by
    // captureStackTrace, NOT the call stack of whoever later calls currentCxxException().
    //
    // This exercises the full chain:
    //   captureStackTrace (simulates __cxa_throw hook) → stores stack in thread dictionary
    //   currentCxxException() → reads thread dictionary → attaches to NSException.reserved
    //
    // Without the hook the thread dictionary is empty and callStackSymbols would be nil.
    func testCurrentCxxException_withCapturedThrowSiteStack_returnsThrowSiteStackNotHandlerStack() {
        var throwSiteStack: NSArray?
        let exception = _currentCxxExceptionWithCapturedThrowSiteStack(&throwSiteStack)

        XCTAssertNotNil(exception, "expected a non-nil NSException")
        XCTAssertNotNil(throwSiteStack, "captureStackTrace should have stored a stack trace")
        XCTAssertFalse(throwSiteStack?.count == 0, "throw-site stack must not be empty")

        // The exception's callStackSymbols must be exactly the stack captured at throw time.
        let exceptionStack = exception?.callStackSymbols as? [String]
        XCTAssertEqual(exceptionStack, throwSiteStack as? [String],
                       "callStackSymbols must match the throw-site snapshot, not the catch-site stack")

        // Sanity: the throw-site helper function itself must appear in the captured stack,
        // confirming it is the throw-site trace and not the handler's trace.
        let containsThrowSite = exceptionStack?.contains {
            $0.contains("currentCxxExceptionWithCapturedThrowSiteStack")
        } ?? false
        XCTAssertTrue(containsThrowSite,
                      "throw-site function must appear in callStackSymbols; got: \(exceptionStack ?? [])")
    }

    // Concrete crash scenario (regression test for commit ab01ecc697)
    //
    // Trigger: an ObjC NSException *subclass* propagates through a noexcept C++ boundary
    // → std::terminate is called → handleTerminateOnCxxException invokes currentCxxException()
    // with the ObjC exception still active.
    //
    // Key: `_currentCxxExceptionForObjCExceptionSubclass` throws an instance of
    // `TestNSExceptionSubclass : NSException` — a real ObjC subclass — so that
    // `__cxa_current_exception_type()->name()` returns `"TestNSExceptionSubclass"`,
    // NOT `"NSException"`.  (Throwing `[NSException exceptionWithName:NSRangeException ...]`
    // would NOT reproduce this: that's still class NSException, so tinfo->name() == "NSException"
    // and the old strcmp would have passed it anyway.)
    //
    // Old behaviour (strcmp check):
    //   strcmp("TestNSExceptionSubclass", "NSException") != 0
    //   → fell through to throw; → __cxa_rethrow with no catch context
    //   → std::terminate again → infinite recursion → stack overflow
    //
    // New behaviour (isObjCException vtable check):
    //   isObjCException() compares the vtable pointer (shared by ALL ObjC exception classes)
    //   → returns YES for any subclass regardless of name
    //   → returns nil immediately, never touching throw;
    // Reproduces the real crash: measures recursion depth when currentCxxException() is
    // called from inside a std::terminate handler with a real ObjC NSException subclass active.
    //
    // `_measureTerminateRecursionDepth()` throws `TestNSExceptionSubclass : NSException`
    // through a noexcept boundary so std::terminate fires with the subclass as the active
    // but *uncaught* exception — the exact state of the production crash.  A custom
    // terminate handler calls currentCxxException() and escapes via longjmp.
    //
    // With isObjCException() fix:
    //   currentCxxException() detects the ObjC vtable → returns nil, never touches throw;
    //   → handler fires exactly once → depth == 1.
    //
    // Without the fix (old strcmp check) on Darwin 25+ / iOS:
    //   strcmp("TestNSExceptionSubclass", "NSException") != 0 → reaches throw;
    //   → __cxa_rethrow with no catch context → std::terminate fires again
    //   → handler called recursively → depth > 1.
    //
    // Without the fix on macOS (test host):
    //   throw; rethrows into currentCxxException's own catch(NSException*) block instead of
    //   re-triggering std::terminate.  The handler detects the non-nil return value and
    //   simulates the recursive call, giving the same depth > 1 result.
    func testCurrentCxxException_inTerminateContext_doesNotRecurseForObjCSubclass() {
        let depth = Int(_measureTerminateRecursionDepth())
        XCTAssertEqual(depth, 1,
                       "currentCxxException() must return nil for ObjC exception subclasses " +
                       "without calling throw;; depth \(depth) > 1 means isObjCException() " +
                       "failed and throw; triggered recursive std::terminate")
    }

    func testCurrentCxxException_forObjCExceptionSubclass_returnsNilWithoutCallingThrow() {
        // Under the old strcmp check this would return non-nil (fell through to throw;,
        // recursing into std::terminate).  With isObjCException() it must return nil.
        let result = _currentCxxExceptionForObjCExceptionSubclass()
        XCTAssertNil(result,
                     "ObjC exception subclass must be detected by isObjCException() and return nil; " +
                     "a non-nil result means the vtable check failed, which would have caused throw; " +
                     "to fire and triggered infinite recursion via std::terminate")
    }

    // Regression test — null tinfo guard
    //
    // Before the fix, calling currentCxxException() when __cxa_current_exception_type() returns
    // null (no active C++ exception) would reach `throw;` with nothing to rethrow.  On
    // Apple's libc++abi (Darwin 25+) that calls std::terminate immediately, crashing the process.
    // After the fix the early `if (!tinfo) { return nil; }` fires instead.
    //
    // This test would crash the test runner (via std::terminate → abort) without the tinfo guard.
    func testCurrentCxxException_whenNoActiveException_returnsNilInsteadOfCrashing() {
        XCTAssertNil(NSException.currentCxxException())
    }

    // Regression test — re-entrancy guard
    //
    // Crash scenario on Darwin 25+:
    //   handleCxxTerminate()          ← std::terminate fires; our handler is called
    //     isHandlingTermination = true
    //     currentCxxException()       ← throw; triggers another std::terminate
    //       handleCxxTerminate()      ← re-entrant call
    //         currentCxxException()   ← throw; triggers yet another std::terminate
    //           ...                   ← stack overflow
    //
    // We reproduce the re-entrant call by setting isHandlingTermination = true and then
    // calling handleCxxTerminate() directly — exactly what happens when Darwin 25+ calls
    // std::terminate from inside throw; mid-handler.
    //
    // Without the guard: the re-entrant call would run the full handler body again (and
    // again), causing a stack overflow.  With the guard: the call is short-circuited and
    // nextCppTerminateHandler is invoked exactly once.
    func testHandleCxxTerminate_reEntrancyGuard_shortCircuitsRecursiveTerminate() {
        let savedFlag = CrashLogMessageExtractor.isHandlingTermination
        defer { CrashLogMessageExtractor.isHandlingTermination = savedFlag }

        var terminateCallCount = 0
        let savedHandler = CrashLogMessageExtractor.nextCppTerminateHandler
        CrashLogMessageExtractor.nextCppTerminateHandler = { terminateCallCount += 1 }
        defer { CrashLogMessageExtractor.nextCppTerminateHandler = savedHandler }

        // Simulate the re-entrant std::terminate invocation: the flag is already true because
        // the outer handleCxxTerminate call set it before reaching currentCxxException().
        CrashLogMessageExtractor.isHandlingTermination = true
        CrashLogMessageExtractor.handleCxxTerminate()

        // Guard must fire immediately → nextCppTerminateHandler called exactly once → no recursion.
        XCTAssertEqual(terminateCallCount, 1,
                       "re-entrant terminate must call nextCppTerminateHandler once then stop; " +
                       "callCount > 1 means the guard is broken")
        // Flag remains set — we are still logically inside the outer crash handler.
        XCTAssertTrue(CrashLogMessageExtractor.isHandlingTermination)
    }

    // Real std::terminate context with a real C++ exception.
    //
    // Verifies the production path end to end on the current libc++abi: an uncaught
    // `std::runtime_error` reaches `std::terminate`, the handler calls
    // `currentCxxException()` (which executes `throw;`), and that `throw;` is caught
    // inside `currentCxxException` instead of re-triggering `std::terminate`.
    // Both ways of reaching terminate are covered: a `noexcept` frame and a throw with
    // no handler anywhere on the thread's stack (`__cxa_throw` → `failed_throw`).
    func testCurrentCxxException_inRealTerminateHandler_rethrowIsCaughtAndHandlerFiresOnce() {
        for viaNoexcept in [true, false] {
            var callCount: Int32 = 0
            let exception = _currentCxxExceptionInTerminateHandler(viaNoexcept, &callCount)
            XCTAssertEqual(callCount, 1, "viaNoexcept=\(viaNoexcept): terminate handler must fire exactly once")
            XCTAssertEqual(exception?.reason, "terminate probe exception", "viaNoexcept=\(viaNoexcept)")
        }
    }

    // ── MetricKit report lookup ──────────────────────────────────────────────────

    // iOS: `timeStampBegin` is the crash time rounded to the nearest minute → the window lookup wins.
    func testMetricKitLookup_whenDiagnosticIsWithinWindow_closestIsChosen() {
        fileManager.contents = [
            "2026-10-20T13:58:19Z-69367.log",
            "2026-10-20T14:00:26Z-78270.log", // <-
        ]

        let r = extractor.crashDiagnostic(forMetricKitReportAt: formatter.date(from: "2026-10-20T14:00:00Z")!)

        XCTAssertEqual(r?.pid, 78270)
    }

    // macOS: `timeStampBegin` was observed to be the next launch time, minutes after the crashes → oldest file first,
    // consumed one by one so that each report gets the next crash's diagnostics.
    func testMetricKitLookup_whenNoDiagnosticIsWithinWindow_oldestUnconsumedIsChosen() {
        fileManager.contents = [
            "2026-10-20T13:58:19Z-69367.log",
            "2026-10-20T14:00:26Z-78270.log",
            "2026-10-20T13:59:09Z-74951.log",
        ]
        let reportTimestamp = formatter.date(from: "2026-10-20T14:04:00Z")!

        let first = extractor.crashDiagnostic(forMetricKitReportAt: reportTimestamp)
        XCTAssertEqual(first?.pid, 69367)
        extractor.consume(first!)

        let second = extractor.crashDiagnostic(forMetricKitReportAt: reportTimestamp)
        XCTAssertEqual(second?.pid, 74951)
        extractor.consume(second!)

        let third = extractor.crashDiagnostic(forMetricKitReportAt: reportTimestamp)
        XCTAssertEqual(third?.pid, 78270)
        extractor.consume(third!)

        XCTAssertNil(extractor.crashDiagnostic(forMetricKitReportAt: reportTimestamp))
        XCTAssertEqual(fileManager.removedFileNames.count, 3)
    }

    func testMetricKitLookup_whenDiagnosticIsNewerThanTheReport_itIsNotChosen() {
        fileManager.contents = ["2026-10-20T14:05:30Z-80000.log"] // 90s after the reported minute

        let r = extractor.crashDiagnostic(forMetricKitReportAt: formatter.date(from: "2026-10-20T14:04:00Z")!)

        XCTAssertNil(r)
    }

    func testMetricKitLookup_whenDiagnosticIsWrittenInTheReportedMinute_itIsChosenByFallback() {
        fileManager.contents = ["2026-10-20T14:04:45Z-80000.log"] // report minute 14:04, file 45s into it

        let r = extractor.crashDiagnostic(forMetricKitReportAt: formatter.date(from: "2026-10-20T14:04:00Z")!)

        XCTAssertEqual(r?.pid, 80000)
    }

    // ── Integration tests: exception → writeDiagnostic → readable file ───────────
    //
    // These verify that the extractor serves its end-to-end purpose for the three
    // exception kinds it must handle: pure C++, plain NSException, and an NSException
    // subclass (as thrown by system frameworks like WebKit).
    //
    // Each test drives the real write → read cycle so we know the exception name,
    // reason, and stack trace survive the full pipeline, not just isolated components.

    // C++ exception path: currentCxxException() extracts name/reason from a live
    // std::runtime_error and the result is correctly persisted and recovered.
    func testExtractorPipeline_cxxException_writesAndReadsCorrectDiagnostic() throws {
        let dir = FileManager.default.temporaryDirectory
        let referenceDate = Date()
        let ext = CrashLogMessageExtractor(diagnosticsDirectory: dir, dateProvider: { referenceDate })

        guard let exception = _currentCxxExceptionInsideCatchBlock() else {
            XCTFail("expected currentCxxException to return an NSException for an active std::runtime_error")
            return
        }
        try ext.writeDiagnostic(for: exception)

        guard let diag = ext.crashDiagnostic(for: referenceDate, pid: ProcessInfo().processIdentifier) else {
            XCTFail("diagnostic file not found after write")
            return
        }
        let data = try diag.diagnosticData()
        // The C++ exception name is the mangled type name; reason is exc.what().
        XCTAssertTrue(data.message.contains("test cxx exception"),
                      "diagnostic message must contain the C++ exception reason; got: \(data.message)")
        XCTAssertFalse(data.message.isEmpty)
    }

    // NSException path: a plain NSException thrown via @throw → writeDiagnostic → readable.
    func testExtractorPipeline_nsException_writesAndReadsCorrectDiagnostic() throws {
        let dir = FileManager.default.temporaryDirectory
        let referenceDate = Date()
        let ext = CrashLogMessageExtractor(diagnosticsDirectory: dir, dateProvider: { referenceDate })

        let exception = NSException(name: NSExceptionName("TestNSException"),
                                    reason: "plain NSException test reason",
                                    userInfo: ["key": "value"])
        try ext.writeDiagnostic(for: exception)

        guard let diag = ext.crashDiagnostic(for: referenceDate, pid: ProcessInfo().processIdentifier) else {
            XCTFail("diagnostic file not found after write")
            return
        }
        let data = try diag.diagnosticData()
        XCTAssertTrue(data.message.contains("TestNSException"))
        XCTAssertTrue(data.message.contains("plain NSException test reason"))
        XCTAssertTrue(data.message.contains("key: value"))
    }

    // NSException subclass path: a real ObjC subclass of NSException (as thrown by system
    // frameworks) arrives via NSUncaughtExceptionHandler → writeDiagnostic → readable.
    func testExtractorPipeline_nsExceptionSubclass_writesAndReadsCorrectDiagnostic() throws {
        let dir = FileManager.default.temporaryDirectory
        let referenceDate = Date()
        let ext = CrashLogMessageExtractor(diagnosticsDirectory: dir, dateProvider: { referenceDate })

        // Use a Swift subclass of NSException — same scenario as a WebKit NSRangeException
        // subclass arriving through the NSUncaughtExceptionHandler.
        final class TestSwiftExceptionSubclass: NSException {}
        let exception = TestSwiftExceptionSubclass(name: NSExceptionName("TestSwiftExceptionSubclass"),
                                                   reason: "NSException subclass test reason",
                                                   userInfo: nil)
        try ext.writeDiagnostic(for: exception)

        guard let diag = ext.crashDiagnostic(for: referenceDate, pid: ProcessInfo().processIdentifier) else {
            XCTFail("diagnostic file not found after write")
            return
        }
        let data = try diag.diagnosticData()
        XCTAssertTrue(data.message.contains("TestSwiftExceptionSubclass"),
                      "subclass name must appear in diagnostic message; got: \(data.message)")
        XCTAssertTrue(data.message.contains("NSException subclass test reason"))
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

    var removedFileNames = [String]()

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        XCTAssertEqual(path, self.diagnosticsDirectory.path)
        if let error {
            throw error
        }
        return contents.filter { !removedFileNames.contains($0) }
    }

    override func removeItem(at URL: URL) throws {
        removedFileNames.append(URL.lastPathComponent)
    }

}
