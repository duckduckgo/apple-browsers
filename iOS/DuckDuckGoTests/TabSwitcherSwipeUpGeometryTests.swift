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
    @Test("The card fills the screen before the finger moves", .timeLimit(.minutes(1)))
    func cardFillsScreenAtRest() {
        #expect(TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 0, in: screen) == screen)
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
    @Test("The card heads for where the current tab's cell was last laid out", .timeLimit(.minutes(1)))
    func storedCellFrame() {
        let screen = CGRect(x: 0, y: 0, width: 999, height: 874)
        let cellFrame = CGRect(x: 30, y: 200, width: 150, height: 180)

        TabSwitcherCellFrameCache.store(cellFrame, row: 3, screenWidth: screen.width, isGrid: true)

        #expect(TabSwitcherCellFrameCache.frame(forRow: 3, in: screen, isGrid: true) == cellFrame)
        #expect(TabSwitcherCellFrameCache.frame(forRow: 3, in: screen, isGrid: false) != cellFrame)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before any cell was laid out, the card heads for the cell's place in the grid", .timeLimit(.minutes(1)))
    func estimatedCellFrame() {
        let first = TabSwitcherCellFrameCache.frame(forRow: 0, in: screen, isGrid: true)
        let second = TabSwitcherCellFrameCache.frame(forRow: 1, in: screen, isGrid: true)
        let third = TabSwitcherCellFrameCache.frame(forRow: 2, in: screen, isGrid: true)

        #expect(first.width == floor(TabSwitcherGridLayoutGeometry.columnWidth(for: screen.width)))
        #expect(second.minY == first.minY)
        #expect(second.minX - first.maxX == TabSwitcherGridLayoutGeometry.spacing)
        #expect(third.minX == first.minX)
        #expect(third.minY > first.minY)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before any list row was laid out, the card heads for the row's place in the list", .timeLimit(.minutes(1)))
    func estimatedListRowFrame() {
        let first = TabSwitcherCellFrameCache.frame(forRow: 0, in: screen, isGrid: false)
        let second = TabSwitcherCellFrameCache.frame(forRow: 1, in: screen, isGrid: false)

        #expect(first.height == TabSwitcherPageViewController.Constants.listCellHeight)
        #expect(first.minX == TabSwitcherGridLayoutGeometry.spacing)
        #expect(first.midX == screen.midX)
        #expect(second.minX == first.minX)
        #expect(second.minY - first.maxY == TabSwitcherGridLayoutGeometry.spacing)
    }
}
