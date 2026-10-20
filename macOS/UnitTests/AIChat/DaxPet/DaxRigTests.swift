//
//  DaxRigTests.swift
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

final class DaxRigTests: XCTestCase {

    func testWhenLoadedFromTheOnboardingAnimationThenDaxIsLiftedOutOfItsPrecomp() throws {
        let rig = try XCTUnwrap(DaxRig())

        XCTAssertEqual(rig.canvasSize, CGSize(width: 1170, height: 1222))
        XCTAssertEqual(rig.animation.size, rig.canvasSize)
        XCTAssertGreaterThanOrEqual(rig.animation.endFrame, DaxRig.Frames.wave.upperBound)
        XCTAssertTrue(CGRect(origin: .zero, size: rig.canvasSize).contains(DaxRig.bodyRect))
    }

    func testWhenAssetIsMissingThenRigIsNil() {
        XCTAssertNil(DaxRig(assetName: "missing-dax"))
    }

    func testEyesPositionFollowsTheSourceKeyframes() throws {
        let rig = try XCTUnwrap(DaxRig())

        // Keyframes at 0 and 7 in the source animation.
        XCTAssertEqual(rig.eyesPosition(at: 0).x, 131.937, accuracy: 0.001)
        XCTAssertEqual(rig.eyesPosition(at: 7).y, -529.966, accuracy: 0.001)
        XCTAssertEqual(rig.eyesPosition(at: 3.5).y, (-508.3 + -529.966) / 2, accuracy: 0.001)
        // Clamped outside the keyframes.
        XCTAssertEqual(rig.eyesPosition(at: -10), rig.eyesPosition(at: 0))
        XCTAssertEqual(rig.eyesPosition(at: 500), rig.eyesPosition(at: 46))
    }
}
