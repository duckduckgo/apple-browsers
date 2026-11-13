//
//  ChromeMorphTraceRecorder.swift
//  DuckDuckGo
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

import UIKit

/// UI tests only. Records what was actually put on screen for each frame of the last chrome
/// hide/show, so a test can check the motion between the two resting states, which XCUITest
/// cannot observe from outside.
final class ChromeMorphTraceRecorder {

    static let accessibilityIdentifier = "Browser.ChromeMorphTrace"

    struct Sample: Equatable {
        let percent: CGFloat
        let pillFrame: CGRect
        let pillAlpha: CGFloat
        let barAlpha: CGFloat
        let bottomObscuredHeight: CGFloat
        let timestamp: CFTimeInterval

        /// `percent,width,height,midY,pillAlpha,barAlpha,bottomObscuredHeight,milliseconds`
        var encoded: String {
            let values = [percent * 1000, pillFrame.width, pillFrame.height, pillFrame.midY,
                          pillAlpha * 1000, barAlpha * 1000, bottomObscuredHeight, timestamp * 1000]
            return values.map { String(Int(($0 * 10).rounded())) }.joined(separator: ",")
        }
    }

    private let probe: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = ChromeMorphTraceRecorder.accessibilityIdentifier
        view.accessibilityValue = ""
        return view
    }()

    private(set) var samples: [Sample] = []

    func install(in view: UIView) {
        guard probe.superview !== view else { return }
        view.insertSubview(probe, at: 0)
    }

    /// A trace runs from one resting state to the next; leaving a resting state starts a new one.
    func record(_ sample: Sample) {
        if let last = samples.last, Self.isAtRest(last.percent) {
            guard last.percent != sample.percent else { return }
            samples = [last]
        }
        samples.append(sample)
        if Self.isAtRest(sample.percent) {
            probe.accessibilityValue = samples.map(\.encoded).joined(separator: ";")
        }
    }

    private static func isAtRest(_ percent: CGFloat) -> Bool {
        percent == 0 || percent == 1
    }
}
