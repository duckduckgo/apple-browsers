//
//  NewTabPageFocusedPoseTests.swift
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

import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
struct NewTabPageFocusedPoseTests {

    private let restingInputFrame = CGRect(x: 16, y: 400, width: 300, height: 56)
    private let focusedInputFrame = CGRect(x: 8, y: 60, width: 320, height: 64)

    @available(iOS 16, macOS 13, *)
    @Test("Top input moves the resting input and modules to meet the focused input", .timeLimit(.minutes(1)))
    func topInputPoseFollowsFocusedInput() {
        let pose = NewTabPageFocusedPose(restingInputFrame: restingInputFrame,
                                         focusedInputFrame: focusedInputFrame,
                                         cardPosition: .top,
                                         safeAreaTop: 47,
                                         showsModules: true)

        #expect(pose.inputOffset == focusedInputFrame.midY - restingInputFrame.midY)
        #expect(pose.greetingOffset == pose.inputOffset)
        #expect(pose.modulesOffset == focusedInputFrame.maxY - restingInputFrame.maxY)
        #expect(pose.showsModules)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Bottom input moves the resting input to the focused input, keeps the greeting in place and raises the modules below the status bar",
          .timeLimit(.minutes(1)))
    func bottomInputPoseRaisesModulesToTop() {
        let bottomFocusedInputFrame = CGRect(x: 8, y: 700, width: 320, height: 64)
        let pose = NewTabPageFocusedPose(restingInputFrame: restingInputFrame,
                                         focusedInputFrame: bottomFocusedInputFrame,
                                         cardPosition: .bottom,
                                         safeAreaTop: 47,
                                         showsModules: false)

        #expect(pose.inputOffset == bottomFocusedInputFrame.midY - restingInputFrame.midY)
        #expect(pose.greetingOffset == 0)
        #expect(restingInputFrame.maxY + pose.modulesOffset == 47 + NewTabPageFocusedPose.bottomInputModulesTopMargin)
        #expect(!pose.showsModules)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Resting transform places the focused input over the resting input", .timeLimit(.minutes(1)))
    func restingTransformPlacesFocusedInputOverRestingInput() {
        let pose = NewTabPageFocusedPose(restingInputFrame: restingInputFrame,
                                         focusedInputFrame: focusedInputFrame,
                                         cardPosition: .top,
                                         safeAreaTop: 47,
                                         showsModules: true)

        let startFrame = focusedInputFrame.applying(pose.focusedInputRestingTransform)

        #expect(startFrame.midY == restingInputFrame.midY)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Untransformed frame ignores the view's own transform", .timeLimit(.minutes(1)))
    func untransformedFrameIgnoresTransform() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let movedView = UIView(frame: CGRect(x: 10, y: 100, width: 200, height: 80))
        container.addSubview(movedView)
        let card = CGRect(x: 8, y: 4, width: 100, height: 40)
        let expectedFrame = movedView.untransformedFrame(of: card, in: container)

        movedView.transform = CGAffineTransform(translationX: 0, y: 250)

        #expect(movedView.untransformedFrame(of: card, in: container) == expectedFrame)
        #expect(expectedFrame == CGRect(x: 18, y: 104, width: 100, height: 40))
    }
}

@MainActor
struct RedesignedNewTabPageFocusedMessagesTests {

    private final class NotificationCounter {
        var count = 0
    }

    @available(iOS 16, macOS 13, *)
    @Test("The message surface is re-checked when the focused pose shows or hides the modules", .timeLimit(.minutes(1)))
    func surfaceChangesWhenModulesVisibilityChanges() {
        let page = RedesignedNewTabPageViewController(blocks: [], returnSettings: .makeForTests())
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: RemoteMessageImpressionReporter.remoteMessageSurfaceDidChange,
                                                              object: page,
                                                              queue: nil) { _ in counter.count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        var pose = NewTabPageFocusedPose(inputOffset: -300, modulesOffset: -280, showsModules: true)

        page.setFocusedPose(pose)
        let countAfterFocus = counter.count
        pose.modulesOffset = -260
        page.setFocusedPose(pose)
        let countAfterOffsetChange = counter.count
        pose.showsModules = false
        page.setFocusedPose(pose)

        #expect(countAfterFocus == 1)
        #expect(countAfterOffsetChange == 1)
        #expect(counter.count == 2)
    }
}

struct RestingSearchCardHandoffTests {

    @available(iOS 16, macOS 13, *)
    @Test("Top input keeps the resting card until the cards swap", .timeLimit(.minutes(1)))
    func topInputFadesRestingCardAfterSwap() {
        let handoff = RestingSearchCardHandoff(cardPosition: .top)
        let timing = handoff.showFadeTiming(transitionDuration: 0.4)

        #expect(handoff == .staysUnderTravellingCard)
        #expect(timing.delay == NewTabPageInputPresentation.inlineInputCardSwapDuration)
        #expect(abs(timing.delay + timing.duration - 0.4) < 0.0001)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Bottom input swaps the resting card for the travelling focused card at the start", .timeLimit(.minutes(1)))
    func bottomInputSwapsRestingCardWithFocusedCard() {
        let handoff = RestingSearchCardHandoff(cardPosition: .bottom)
        let timing = handoff.showFadeTiming(transitionDuration: 0.4)

        #expect(handoff == .swapsWithFocusedCard)
        #expect(timing.delay == 0)
        #expect(timing.duration == NewTabPageInputPresentation.inlineInputCardSwapDuration)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A transition shorter than the swap never gets a negative fade", .timeLimit(.minutes(1)))
    func zeroDurationTransitionHasNoNegativeFade() {
        let timing = RestingSearchCardHandoff.staysUnderTravellingCard.showFadeTiming(transitionDuration: 0)

        #expect(timing.delay == 0)
        #expect(timing.duration == 0)
    }
}

struct RedesignedNewTabPageAccessibilityReachTests {

    private static let pose = NewTabPageFocusedPose(inputOffset: -300, modulesOffset: -280, showsModules: true)

    @available(iOS 16, macOS 13, *)
    @Test("Resting page or onboarding dialog keeps the whole page reachable",
          .timeLimit(.minutes(1)),
          arguments: [(false, false), (false, true), (true, true)])
    func wholePageWhenNotEditingOrOnboarding(isEditing: Bool, isPresentingOnboardingDialog: Bool) {
        let reach = RedesignedNewTabPageAccessibilityReach(isEditing: isEditing,
                                                           isPresentingOnboardingDialog: isPresentingOnboardingDialog,
                                                           focusedPose: Self.pose)

        #expect(reach == .wholePage)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Focused pose with modules exposes only the modules", .timeLimit(.minutes(1)))
    func focusedModulesOnlyWhenPoseShowsModules() {
        let reach = RedesignedNewTabPageAccessibilityReach(isEditing: true, isPresentingOnboardingDialog: false, focusedPose: Self.pose)

        #expect(reach == .focusedModulesOnly)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Editing without visible modules hides the page", .timeLimit(.minutes(1)))
    func nothingWhenModulesHidden() {
        var hiddenModulesPose = Self.pose
        hiddenModulesPose.showsModules = false

        #expect(RedesignedNewTabPageAccessibilityReach(isEditing: true, isPresentingOnboardingDialog: false,
                                                       focusedPose: hiddenModulesPose) == .nothing)
        #expect(RedesignedNewTabPageAccessibilityReach(isEditing: true, isPresentingOnboardingDialog: false,
                                                       focusedPose: nil) == .nothing)
    }
}
