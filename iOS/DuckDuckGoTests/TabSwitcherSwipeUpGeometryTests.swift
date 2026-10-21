//
//  TabSwitcherSwipeUpGeometryTests.swift
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

@Suite("Tab switcher swipe-up geometry")
struct TabSwitcherSwipeUpGeometryTests {

    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    @available(iOS 16, macOS 13, *)
    @Test("The card fills the screen until the finger passes the touch slop", .timeLimit(.minutes(1)))
    func cardFillsScreenAtRest() {
        #expect(TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 0, in: screen) == screen)
        #expect(TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 12, in: screen) == screen)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The card stays centred and keeps the screen's proportions", .timeLimit(.minutes(1)))
    func cardKeepsScreenProportions() {
        let frame = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 200, in: screen)

        #expect(abs(frame.midX - screen.midX) < 0.001)
        #expect(abs(frame.height / frame.width - screen.height / screen.width) < 0.001)
        #expect(frame.width < screen.width)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dragging further always lifts and shrinks the card", .timeLimit(.minutes(1)))
    func cardMovesMonotonically() {
        let travels = stride(from: CGFloat(0), through: 800, by: 10)
        let poses = travels.map { TabSwitcherSwipeUpGeometry.pose(forTravel: $0, screenHeight: screen.height) }

        for (previous, next) in zip(poses, poses.dropFirst()) {
            #expect(next.lift >= previous.lift)
            #expect(next.scale <= previous.scale)
        }
        #expect(poses.last?.scale == TabSwitcherSwipeUpGeometry.minimumScale)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dragging down below the touch point leaves the card full screen", .timeLimit(.minutes(1)))
    func downwardTravelIsIgnored() {
        #expect(TabSwitcherSwipeUpGeometry.cardFrame(forTravel: -50, in: screen) == screen)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A flick commits, a short or downward release cancels", .timeLimit(.minutes(1)),
          arguments: [
            (travel: CGFloat(20), velocity: CGFloat(-600), commits: true),
            (travel: CGFloat(150), velocity: CGFloat(0), commits: true),
            (travel: CGFloat(30), velocity: CGFloat(0), commits: false),
            (travel: CGFloat(300), velocity: CGFloat(600), commits: false),
          ])
    func commitDecision(travel: CGFloat, velocity: CGFloat, commits: Bool) {
        #expect(TabSwitcherSwipeUpGeometry.shouldCommit(travel: travel, velocity: velocity) == commits)
    }

    @available(iOS 16, macOS 13, *)
    @Test("In a grid cell the page sits below the header, inset, pinned to the top at full width", .timeLimit(.minutes(1)))
    func gridPreviewLayoutMatchesCell() {
        let layout = TabSwitcherSwipeUpGeometry.previewLayout(forCellSize: CGSize(width: 180, height: 209),
                                                              contentSize: CGSize(width: 402, height: 874),
                                                              contentCropTop: 62)

        let inset = TabViewGridCell.Constants.previewHorizontalInset / 2
        #expect(layout.clipFrame.minX == inset)
        #expect(layout.clipFrame.minY == TabViewGridCell.Constants.headerHeight)
        #expect(layout.clipFrame.width == 180 - inset * 2)
        #expect(layout.contentFrame.width == layout.clipFrame.width)
        #expect(layout.contentFrame.minY < 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The classic new tab page's Dax circle is found within its aspect-fitted animation", .timeLimit(.minutes(1)))
    func classicDaxCircle() {
        let animationFrame = CGRect(x: 0, y: 300, width: 393, height: 162)
        let circle = NewTabPageDaxLogoView.daxCircle(inAnimationFrame: animationFrame)

        #expect(abs(circle.width - 94) < 0.001)
        #expect(circle.width == circle.height)
        #expect(abs(circle.midX - (animationFrame.midX + 0.8)) < 0.001)
        #expect(abs(circle.midY - (animationFrame.midY - 18)) < 0.001)
    }
}
