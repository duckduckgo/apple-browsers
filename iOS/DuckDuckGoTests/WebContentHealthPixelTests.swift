//
//  WebContentHealthPixelTests.swift
//  DuckDuckGoTests
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

import PixelKit
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class WebContentHealthPixelTests: XCTestCase {

    func testWhenTerminationReloadEndsThenResultPixelFiresOnceWithOutcomeAndRecovery() throws {
        let pixelFiring = MockWebContentHealthPixelFiring()
        var tracker = TerminationReloadMonitor(pixelFiring: pixelFiring)

        tracker.didFinish()
        XCTAssertTrue(pixelFiring.calls.isEmpty, "Navigations without a termination reload are not reported")

        tracker.begin(.deferred)
        tracker.didFail(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        tracker.didFail(with: NSError(domain: WKError.WebKitErrorDomain, code: WKError.Code.frameLoadInterruptedByPolicyChange.rawValue))
        XCTAssertTrue(pixelFiring.calls.isEmpty, "Cancellations keep waiting for the real result")

        tracker.didFinish()
        tracker.didFinish()

        let call = try XCTUnwrap(pixelFiring.call(named: "web-content_termination-reload-result"))
        XCTAssertEqual(call.event.parameters, ["outcome": "finished", "recovery": "deferred"])
        XCTAssertEqual(call.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.calls.count, 1)
    }

    func testWhenTerminationReloadFailsOrTerminatesThenOutcomeIsReported() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        var tracker = TerminationReloadMonitor(pixelFiring: pixelFiring)

        tracker.begin(.immediate)
        tracker.didFail(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        tracker.begin(.immediate)
        tracker.didTerminate()

        XCTAssertEqual(pixelFiring.calls.map { $0.event.parameters?["outcome"] }, ["failed", "terminated"])
        XCTAssertNil(tracker.pendingRecovery)
    }

    func testUnresponsivePixelNameAndParameters() {
        let pixel = WebContentHealthPixel.unresponsive(appState: "foreground")
        XCTAssertEqual(pixel.name, "web-content_unresponsive")
        XCTAssertEqual(pixel.parameters, ["app_state": "foreground"])
    }

}

private final class MockWebContentHealthPixelFiring: PixelFiring {

    struct Call {
        let event: PixelKit.Event
        let frequency: PixelKit.Frequency
    }

    private(set) var calls: [Call] = []

    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock) {
        calls.append(.init(event: event, frequency: frequency))
        onComplete(true, nil)
    }

    func call(named name: String) -> Call? {
        calls.first { $0.event.name == name }
    }
}
