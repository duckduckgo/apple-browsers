//
//  DottedStepIndicatorViewTests.swift
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

import Testing
@testable import UIComponents

@MainActor
struct DottedStepIndicatorViewTests {

    @Test("Check that total dots is clamped to a minimum of 1")
    func whenTotalDotsIsZero_ThenTotalDotsIsClampedToOne() {
        let sut = DottedStepIndicatorView(selectedDot: 1, totalDots: 0)

        #expect(sut.totalDots == 1)
    }

    @Test("Check that selected dot is clamped to a minimum of 1")
    func whenSelectedDotIsLessThanOne_ThenSelectedDotIsClampedToOne() {
        let sut = DottedStepIndicatorView(selectedDot: 0, totalDots: 5)

        #expect(sut.selectedDot == 1)
    }

    @Test("Check that selected dot is clamped to the total number of dots")
    func whenSelectedDotIsGreaterThanTotalDots_ThenSelectedDotIsClampedToTotalDots() {
        let sut = DottedStepIndicatorView(selectedDot: 8, totalDots: 5)

        #expect(sut.totalDots == 5)
        #expect(sut.selectedDot == 5)
    }

    @Test("Check that custom style values are preserved")
    func whenCustomStyleIsProvided_ThenStyleValuesArePreserved() {
        let style = DottedStepIndicatorView.Style(
            dotSpacing: 12,
            selectedDotSize: 16,
            unselectedDotSize: 7
        )
        let sut = DottedStepIndicatorView(selectedDot: 2, totalDots: 4, style: style)

        #expect(sut.style.dotSpacing == 12)
        #expect(sut.style.selectedDotSize == 16)
        #expect(sut.style.unselectedDotSize == 7)
    }

}
