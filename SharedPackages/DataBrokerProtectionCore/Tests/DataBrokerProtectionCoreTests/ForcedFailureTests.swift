// FORCED-FAILURE for PR #4493 verification — remove before merge.

import XCTest

final class ForcedFailureTests: XCTestCase {
    func testForcedFailureForWorkflowVerification() {
        XCTFail("Forced failure to verify DBP test-report workflow (PR #4493)")
    }

    func testForcedCrashForWorkflowVerification() {
        fatalError("Forced crash to verify DBP crash-injection workflow (PR #4493)")
    }
}
