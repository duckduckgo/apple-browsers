// FORCED-FAILURE for PR #4493 verification — remove before merge.

import XCTest

final class ForcedFailureTests: XCTestCase {
    func testForcedFailureForWorkflowVerification() {
        XCTFail("Forced failure to verify BSK test-report workflow (PR #4493)")
    }

    func testForcedCrashForWorkflowVerification() {
        fatalError("Forced crash to verify BSK crash-injection workflow (PR #4493)")
    }
}
