//
//  PixelKitATBTests.swift
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
@testable import PixelKit

/// Covers the `atb` parameter: who opts in, where the value comes from, and when it is read.
final class PixelKitATBTests: XCTestCase {

    /// A reference type on purpose, so a test can change the value between two fires and prove
    /// PixelKit re-reads it rather than snapshotting it.
    private final class MockParameterProvider: PixelKitParameterProviding {

        var atb: String?

        init(atb: String? = nil) {
            self.atb = atb
        }
    }

    private enum TestEvent: String, PixelKit.Event {

        case testEvent

        var name: String {
            rawValue
        }

        var parameters: [String: String]? {
            nil
        }

        var standardParameters: [PixelKitStandardParameter]? {
            nil
        }
    }

    private func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

    private func makePixelKit(parameterProvider: PixelKitParameterProviding?,
                              onFire: @escaping ([String: String]) -> Void) -> PixelKit {
        PixelKit(dryRun: false,
                 appVersion: "1.0.5",
                 defaultHeaders: [:],
                 pixelCalendar: nil,
                 defaults: userDefaults(),
                 parameterProvider: parameterProvider) { _, _, parameters, _, _, _ in
            onFire(parameters)
        }
    }

    /// The default is off, so migrating a pixel to PixelKit cannot silently start sending a cohort.
    func testATBIsOmittedWhenThePixelDoesNotOptIn() {
        let fired = expectation(description: "Expect the pixel firing callback to be called")
        var firedParameters = [String: String]()

        let pixelKit = makePixelKit(parameterProvider: MockParameterProvider(atb: "v123-4ma")) { parameters in
            firedParameters = parameters
            fired.fulfill()
        }

        pixelKit.fire(TestEvent.testEvent)
        wait(for: [fired], timeout: 0.5)

        XCTAssertNil(firedParameters[PixelKit.Parameters.atb])
    }

    func testATBIsSentWhenThePixelOptsIn() {
        let fired = expectation(description: "Expect the pixel firing callback to be called")
        var firedParameters = [String: String]()

        let pixelKit = makePixelKit(parameterProvider: MockParameterProvider(atb: "v123-4ma")) { parameters in
            firedParameters = parameters
            fired.fulfill()
        }

        pixelKit.fire(TestEvent.testEvent, options: .withATB)
        wait(for: [fired], timeout: 0.5)

        XCTAssertEqual(firedParameters[PixelKit.Parameters.atb], "v123-4ma")
    }

    /// Parity with the legacy `Pixel`, which sent `statisticsStore.atbWithVariant ?? ""`. The
    /// parameter is present with an empty value rather than missing.
    func testATBIsSentEmptyWhenTheProviderHasNoValueYet() {
        let fired = expectation(description: "Expect the pixel firing callback to be called")
        var firedParameters = [String: String]()

        let pixelKit = makePixelKit(parameterProvider: MockParameterProvider(atb: nil)) { parameters in
            firedParameters = parameters
            fired.fulfill()
        }

        pixelKit.fire(TestEvent.testEvent, options: .withATB)
        wait(for: [fired], timeout: 0.5)

        XCTAssertEqual(firedParameters[PixelKit.Parameters.atb], "")
    }

    /// A host that never injects a provider keeps its previous behaviour, even for a shared event
    /// that opts in. Sending an empty cohort here would be fabricating data from a misconfiguration.
    func testATBIsOmittedWhenNoProviderIsInjected() {
        let fired = expectation(description: "Expect the pixel firing callback to be called")
        var firedParameters = [String: String]()

        let pixelKit = makePixelKit(parameterProvider: nil) { parameters in
            firedParameters = parameters
            fired.fulfill()
        }

        pixelKit.fire(TestEvent.testEvent, options: .withATB)
        wait(for: [fired], timeout: 0.5)

        XCTAssertNil(firedParameters[PixelKit.Parameters.atb])
    }

    /// The value is read on every fire, not captured at `setUp`. This matters because there is no
    /// ATB until the app has completed its first ATB request.
    func testATBIsResolvedAtFireTimeRatherThanAtSetUpTime() {
        let provider = MockParameterProvider(atb: nil)
        let firstFire = expectation(description: "Expect the first pixel firing callback to be called")
        let secondFire = expectation(description: "Expect the second pixel firing callback to be called")
        var firedATBs = [String?]()

        let pixelKit = makePixelKit(parameterProvider: provider) { parameters in
            firedATBs.append(parameters[PixelKit.Parameters.atb])
            if firedATBs.count == 1 {
                firstFire.fulfill()
            } else {
                secondFire.fulfill()
            }
        }

        pixelKit.fire(TestEvent.testEvent, options: .withATB)
        wait(for: [firstFire], timeout: 0.5)

        provider.atb = "v123-4ma"
        pixelKit.fire(TestEvent.testEvent, options: .withATB)
        wait(for: [secondFire], timeout: 0.5)

        XCTAssertEqual(firedATBs, ["", "v123-4ma"])
    }

    /// Exercises the shape the app actually uses: the static `setUp`, with `parameterProvider:`
    /// sitting immediately before the trailing `fireRequest` closure.
    func testSharedSetUpAcceptsAParameterProviderAndAppliesIt() {
        let fired = expectation(description: "Expect the pixel firing callback to be called")
        var firedParameters = [String: String]()

        PixelKit.tearDown()
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.5",
                       session: "atb-tests",
                       defaultHeaders: [:],
                       defaults: userDefaults(),
                       parameterProvider: MockParameterProvider(atb: "v123-4ma")) { _, _, parameters, _, _, _ in
            firedParameters = parameters
            fired.fulfill()
        }
        defer { PixelKit.tearDown() }

        PixelKit.fire(TestEvent.testEvent, options: .withATB)
        wait(for: [fired], timeout: 0.5)

        XCTAssertEqual(firedParameters[PixelKit.Parameters.atb], "v123-4ma")
    }

    // MARK: - Options

    func testIncludeATBIsOffByDefault() {
        XCTAssertFalse(PixelKit.Options.default.includeATB)
        XCTAssertFalse(PixelKit.Options().includeATB)
    }

    func testWithATBPresetOnlyChangesIncludeATB() {
        XCTAssertEqual(PixelKit.Options.withATB, PixelKit.Options(includeATB: true))
        XCTAssertTrue(PixelKit.Options.withATB.includeATB)
        XCTAssertTrue(PixelKit.Options.withATB.includeAppVersionParameter)
        XCTAssertFalse(PixelKit.Options.withATB.retryOnFailure)
    }
}
