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
    @Test("The lifted card follows horizontal finger travel in both directions", .timeLimit(.minutes(1)),
          arguments: [CGFloat(-90), 90])
    func cardFollowsHorizontalTravel(horizontalTravel: CGFloat) {
        let centered = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 200, in: screen)
        let dragged = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 200, horizontalTravel: horizontalTravel, in: screen)

        #expect(dragged.midX == centered.midX + horizontalTravel)
        #expect(dragged.minY == centered.minY)
        #expect(dragged.size == centered.size)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Neighbor cards keep a fixed size and follow the current card's top", .timeLimit(.minutes(1)),
          arguments: [CGFloat(0), 60, 150, 400])
    func neighborSizeAndTop(travel: CGFloat) {
        let current = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: travel, horizontalTravel: -80, in: screen)
        let neighbor = TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: travel,
                                                                   horizontalTravel: -80,
                                                                   offset: 1,
                                                                   in: screen)

        #expect(neighbor.width == screen.width * 0.78)
        #expect(neighbor.height == screen.height * 0.78)
        #expect(neighbor.minY == current.minY)
        #expect(abs(neighbor.height / neighbor.width - screen.height / screen.width) < 0.001)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Neighbor cards are mirrored and follow horizontal finger movement", .timeLimit(.minutes(1)))
    func mirroredNeighborCards() {
        let left = TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: 150, horizontalTravel: 80, offset: -1, in: screen)
        let right = TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: 150, horizontalTravel: 80, offset: 1, in: screen)
        let centered = TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: 150, horizontalTravel: 0, offset: 1, in: screen)

        #expect(abs(left.midX + right.midX - 2 * (screen.midX + 80)) < 0.001)
        #expect(abs(right.minX - centered.minX - 80) < 0.001)
        #expect(TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: 150, horizontalTravel: 80, offset: 0, in: screen)
                == TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 150, horizontalTravel: 80, in: screen))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Neighbor cards slide in progressively and keep a gap from the current card", .timeLimit(.minutes(1)))
    func progressiveNeighborEntry() {
        let travels: [CGFloat] = [0, 40, 80, 150]
        let neighbors = travels.map {
            TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: $0, horizontalTravel: 0, offset: 1, in: screen)
        }
        #expect(neighbors[0].minX > screen.maxX)
        for (previous, next) in zip(neighbors, neighbors.dropFirst()) {
            #expect(next.minX < previous.minX)
        }
        let current = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: 150, in: screen)
        #expect(abs(neighbors[3].minX - current.maxX - screen.width * 0.085) < 0.001)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("Both neighbors stay separated through lifting and horizontal travel, including perspective", .timeLimit(.minutes(1)),
          arguments: [
            (travel: CGFloat(0), horizontal: CGFloat(0)),
            (travel: CGFloat(40), horizontal: CGFloat(-80)),
            (travel: CGFloat(80), horizontal: CGFloat(80)),
            (travel: CGFloat(150), horizontal: CGFloat(-100)),
            (travel: CGFloat(400), horizontal: CGFloat(100)),
          ])
    func neighborSpacingWithPerspective(travel: CGFloat, horizontal: CGFloat) {
        let current = TabSwitcherSwipeUpGeometry.cardFrame(forTravel: travel, horizontalTravel: horizontal, in: screen)
        for offset in [-1, 1] {
            let frame = TabSwitcherSwipeUpGeometry.neighborCardFrame(forTravel: travel, horizontalTravel: horizontal, offset: offset, in: screen)
            let gap = offset < 0 ? current.minX - frame.maxX : frame.minX - current.maxX
            #expect(gap >= screen.width * 0.085 - 0.001)

            let card = TabSwitcherCardView(content: UIView(),
                                           contentFrameInScreen: screen,
                                           contentCropTop: 0,
                                           screenBounds: screen,
                                           screenCornerRadius: 50,
                                           screenBackgroundColor: .white)
            let tilt = TabSwitcherSwipeUpGeometry.neighborTilt(forTravel: travel, screenHeight: screen.height, offset: offset)
            card.applyScreenPose(cardFrame: frame, tilt: tilt)
            let surface = card.subviews[1]
            let transform = surface.layer.transform
            let localX = -CGFloat(offset) * surface.bounds.width / 2
            let projectedEdge = surface.center.x + (localX * transform.m11 + transform.m41) / (localX * transform.m14 + transform.m44)
            let projectedGap = offset < 0 ? current.minX - projectedEdge : projectedEdge - current.maxX
            #expect(projectedGap >= gap - 0.001)
            if travel >= screen.height * 0.15 {
                #expect(abs(projectedGap / screen.width - 0.095) < 0.001)
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Neighbor cards tilt inward progressively up to seven degrees", .timeLimit(.minutes(1)),
          arguments: [
            (travel: CGFloat(-100), degrees: CGFloat(0)),
            (travel: CGFloat(0), degrees: CGFloat(0)),
            (travel: CGFloat(75), degrees: CGFloat(3.5)),
            (travel: CGFloat(150), degrees: CGFloat(7)),
            (travel: CGFloat(300), degrees: CGFloat(7)),
          ])
    func neighborTilt(travel: CGFloat, degrees: CGFloat) {
        let left = TabSwitcherSwipeUpGeometry.neighborTilt(forTravel: travel, screenHeight: 1000, offset: -1)
        let right = TabSwitcherSwipeUpGeometry.neighborTilt(forTravel: travel, screenHeight: 1000, offset: 1)
        #expect(abs(left - degrees * .pi / 180) < 0.001)
        #expect(abs(left + right) < 0.001)
        #expect(TabSwitcherSwipeUpGeometry.neighborTilt(forTravel: travel, screenHeight: 0, offset: 1) == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A slow horizontal drag selects an adjacent tab after eighteen percent of the screen", .timeLimit(.minutes(1)),
          arguments: [
            (horizontal: CGFloat(0), width: CGFloat(400), offset: 0),
            (horizontal: CGFloat(-100), width: CGFloat(400), offset: 1),
            (horizontal: CGFloat(-40), width: CGFloat(400), offset: 0),
            (horizontal: CGFloat(40), width: CGFloat(400), offset: 0),
            (horizontal: CGFloat(100), width: CGFloat(400), offset: -1),
            (horizontal: CGFloat(-72), width: CGFloat(400), offset: 0),
            (horizontal: CGFloat(72), width: CGFloat(400), offset: 0),
            (horizontal: CGFloat(-73), width: CGFloat(400), offset: 1),
            (horizontal: CGFloat(73), width: CGFloat(400), offset: -1),
            (horizontal: CGFloat(-200), width: CGFloat(0), offset: 0),
          ])
    func selectedTabOffset(horizontal: CGFloat, width: CGFloat, offset: Int) {
        #expect(TabSwitcherSwipeUpGeometry.selectedTabOffset(horizontalTravel: horizontal, screenWidth: width) == offset)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The destination stays hidden initially and clears progressively as the card rises", .timeLimit(.minutes(1)),
          arguments: [
            (travel: CGFloat(-0.1), progress: CGFloat(0)),
            (travel: CGFloat(0.04), progress: CGFloat(0)),
            (travel: CGFloat(0.08), progress: CGFloat(1) / 6),
            (travel: CGFloat(0.16), progress: CGFloat(0.5)),
            (travel: CGFloat(0.28), progress: CGFloat(1)),
            (travel: CGFloat(0.8), progress: CGFloat(1)),
          ])
    func progressiveReveal(travel: CGFloat, progress: CGFloat) {
        let reveal = TabSwitcherSwipeUpGeometry.revealProgress(forTravel: travel * screen.height, screenHeight: screen.height)
        #expect(abs(reveal - progress) < 0.001)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The destination stays hidden without a screen height", .timeLimit(.minutes(1)))
    func revealWithoutScreenHeight() {
        #expect(TabSwitcherSwipeUpGeometry.revealProgress(forTravel: 100, screenHeight: 0) == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("All Tabs stays blurred while held and uses lighter blur when released", .timeLimit(.minutes(1)),
          arguments: [
            (travel: CGFloat(0), held: CGFloat(1), released: CGFloat(0.3)),
            (travel: CGFloat(160), held: CGFloat(0.5), released: CGFloat(0.3)),
            (travel: CGFloat(208), held: CGFloat(0.3), released: CGFloat(0.3)),
            (travel: CGFloat(280), held: CGFloat(0.3), released: CGFloat(0)),
            (travel: CGFloat(800), held: CGFloat(0.3), released: CGFloat(0)),
            (travel: CGFloat(1500), held: CGFloat(0.3), released: CGFloat(0)),
          ])
    func retainedInteractiveBlur(travel: CGFloat, held: CGFloat, released: CGFloat) {
        let reveal = TabSwitcherSwipeUpGeometry.revealProgress(forTravel: travel, screenHeight: 1000)
        let blur = TabSwitcherSwipeUpGeometry.blurProgress(forRevealProgress: reveal, isCommitted: false)
        #expect(abs(blur - held) < 0.001)
        let releasedBlur = TabSwitcherSwipeUpGeometry.blurProgress(forRevealProgress: reveal, isCommitted: true)
        #expect(abs(releasedBlur - released) < 0.001)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The address bar returns during the last five percent of the downward drag", .timeLimit(.minutes(1)),
          arguments: [
            (travel: CGFloat(-0.1), visibility: CGFloat(1)),
            (travel: CGFloat(0), visibility: CGFloat(1)),
            (travel: CGFloat(0.025), visibility: CGFloat(0.5)),
            (travel: CGFloat(0.05), visibility: CGFloat(0)),
            (travel: CGFloat(0.2), visibility: CGFloat(0)),
          ])
    func chromeVisibility(travel: CGFloat, visibility: CGFloat) {
        let alpha = TabSwitcherSwipeUpGeometry.chromeVisibility(forTravel: travel * screen.height, screenHeight: screen.height)
        #expect(abs(alpha - visibility) < 0.001)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The address bar stays visible without a screen height", .timeLimit(.minutes(1)))
    func chromeVisibleWithoutScreenHeight() {
        #expect(TabSwitcherSwipeUpGeometry.chromeVisibility(forTravel: 100, screenHeight: 0) == 1)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("The card gains a shadow while lifted and loses it when restored", .timeLimit(.minutes(1)))
    func liftedCardShadow() throws {
        let card = TabSwitcherCardView(content: UIView(),
                                       contentFrameInScreen: screen,
                                       contentCropTop: 0,
                                       screenBounds: screen,
                                       screenCornerRadius: 50,
                                       screenBackgroundColor: .white)
        let shadow = try #require(card.subviews.first)
        let cellShadowAlpha = try #require(shadow.layer.shadowColor).alpha

        card.applyScreenPose(cardFrame: screen)
        #expect(shadow.layer.shadowOpacity == 0)
        card.applyScreenPose(cardFrame: screen.insetBy(dx: screen.width * 0.0375, dy: screen.height * 0.0375))
        #expect(abs(shadow.layer.shadowOpacity - 0.5) < 0.001)
        let liftedShadowAlpha = try #require(shadow.layer.shadowColor).alpha
        #expect(abs(liftedShadowAlpha - cellShadowAlpha * 1.2) < 0.001)
        card.applyScreenPose(cardFrame: screen.insetBy(dx: screen.width * 0.075, dy: screen.height * 0.075))
        #expect(shadow.layer.shadowOpacity == 1)
        card.applyCellPose(cellFrame: CGRect(x: 20, y: 150, width: 160, height: 200))
        #expect(shadow.layer.shadowOpacity == 1)
        #expect(shadow.layer.shadowColor?.alpha == cellShadowAlpha)
        card.applyScreenPose(cardFrame: screen)
        #expect(shadow.layer.shadowOpacity == 0)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("Perspective yaws each card surface around its own center and resets before another pose", .timeLimit(.minutes(1)))
    func tiltedCardLayout() {
        let card = TabSwitcherCardView(content: UIView(),
                                       contentFrameInScreen: screen,
                                       contentCropTop: 0,
                                       screenBounds: screen,
                                       screenCornerRadius: 50,
                                       screenBackgroundColor: .white)
        let untilted = TabSwitcherCardView(content: UIView(),
                                           contentFrameInScreen: screen,
                                           contentCropTop: 0,
                                           screenBounds: screen,
                                           screenCornerRadius: 50,
                                           screenBackgroundColor: .white)
        #expect(card.subviews.count == 3)
        var transforms: [CATransform3D] = []
        for (frame, angle) in [(CGRect(x: -180, y: 90, width: 300, height: 650), CGFloat(0.12)),
                               (CGRect(x: 230, y: 150, width: 240, height: 520), CGFloat(-0.12))] {
            untilted.applyScreenPose(cardFrame: frame)
            card.applyScreenPose(cardFrame: frame, tilt: angle)

            #expect(card.cardFrame == frame)
            #expect(CATransform3DIsIdentity(card.layer.transform))
            for (shape, expected) in zip(card.subviews, untilted.subviews) {
                #expect(shape.center == expected.center)
                #expect(shape.bounds == expected.bounds)
                let transform = shape.layer.transform
                #expect(transform.m34 < 0)
                #expect(abs(transform.m11 - cos(angle)) < 0.001)
                #expect(abs(transform.m13 + sin(angle)) < 0.001)
                #expect(abs(transform.m31 - sin(angle)) < 0.001)
                #expect(transform.m12 == 0)
                #expect(transform.m21 == 0)
                #expect(transform.m22 == 1)
            }
            transforms.append(card.subviews[1].layer.transform)
        }
        #expect(abs(transforms[0].m13 + transforms[1].m13) < 0.001)
        #expect(abs(transforms[0].m31 + transforms[1].m31) < 0.001)
        #expect(transforms[0].m34 == transforms[1].m34)
        card.applyScreenPose(cardFrame: screen)
        #expect(card.cardFrame == screen)
        #expect(card.subviews.allSatisfy { CATransform3DIsIdentity($0.layer.transform) })

        card.applyScreenPose(cardFrame: screen.insetBy(dx: 50, dy: 100), tilt: 0.12)
        let cellFrame = CGRect(x: 20, y: 150, width: 160, height: 200)
        untilted.applyCellPose(cellFrame: cellFrame)
        card.applyCellPose(cellFrame: cellFrame)
        #expect(card.cardFrame == cellFrame)
        for (shape, expected) in zip(card.subviews, untilted.subviews) {
            #expect(CATransform3DIsIdentity(shape.layer.transform))
            #expect(shape.center == expected.center)
            #expect(shape.bounds == expected.bounds)
        }
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

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("The card heads for where the current tab's cell was last laid out", .timeLimit(.minutes(1)))
    func storedCellFrame() {
        let screen = CGRect(x: 0, y: 0, width: 999, height: 874)
        let cellFrame = CGRect(x: 30, y: 200, width: 150, height: 180)

        TabSwitcherCellFrameCache.store(cellFrame, row: 3, screenWidth: screen.width, isGrid: true)

        #expect(TabSwitcherCellFrameCache.frame(forRow: 3, in: screen, isGrid: true) == cellFrame)
        #expect(TabSwitcherCellFrameCache.frame(forRow: 3, in: screen, isGrid: false) != cellFrame)
    }

    @MainActor
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

    @MainActor
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
