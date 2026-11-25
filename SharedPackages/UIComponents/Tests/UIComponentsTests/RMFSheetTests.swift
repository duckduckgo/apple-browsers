//
//  RMFSheetTests.swift
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

#if os(iOS)

import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite("Sheet choice list selection")
struct SheetChoiceListViewModelTests {

    private let options = [
        SheetChoiceOption(title: "Accept", description: "Saves you a click"),
        SheetChoiceOption(title: "Keep accepting myself"),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("The first option is pre-selected by default", .timeLimit(.minutes(1)))
    func firstOptionIsPreselectedByDefault() {
        let viewModel = SheetChoiceListViewModel(options: options)

        #expect(viewModel.selectedIndex == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An out-of-range pre-selection selects nothing", .timeLimit(.minutes(1)))
    func outOfRangePreselectionSelectsNothing() {
        #expect(SheetChoiceListViewModel(options: options, selectedIndex: 5).selectedIndex == nil)
        #expect(SheetChoiceListViewModel(options: options, selectedIndex: nil).selectedIndex == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Selecting an option updates the selection and reports its index", .timeLimit(.minutes(1)))
    func selectingAnOptionUpdatesSelectionAndReportsIndex() {
        var reported: [Int] = []
        let viewModel = SheetChoiceListViewModel(options: options) { reported.append($0) }

        viewModel.select(index: 1)

        #expect(viewModel.selectedIndex == 1)
        #expect(reported == [1])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tapping a row's item selects it and reports its index", .timeLimit(.minutes(1)))
    func selectingAnItemReportsItsIndex() {
        var reported: [Int] = []
        let viewModel = SheetChoiceListViewModel(options: options) { reported.append($0) }

        viewModel.selectItem(viewModel.items[1])
        viewModel.selectItem(viewModel.items[0])

        #expect(viewModel.selectedIndex == 0)
        #expect(reported == [1, 0])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Out-of-range and unknown selections are ignored", .timeLimit(.minutes(1)))
    func outOfRangeAndUnknownSelectionsAreIgnored() {
        var reported: [Int] = []
        let viewModel = SheetChoiceListViewModel(options: options) { reported.append($0) }

        viewModel.select(index: 2)
        viewModel.select(index: -1)
        viewModel.selectItem(RadioButtonItem(text: "Not in the list"))

        #expect(viewModel.selectedIndex == 0)
        #expect(reported.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Options map to radio items with their description as secondary text", .timeLimit(.minutes(1)))
    func optionsMapToRadioItems() {
        let viewModel = SheetChoiceListViewModel(options: options)

        #expect(viewModel.items.map(\.text) == ["Accept", "Keep accepting myself"])
        #expect(viewModel.items.map(\.secondaryText) == ["Saves you a click", nil])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Radio items without secondary text keep their existing initialiser", .timeLimit(.minutes(1)))
    func radioItemDefaultsToNoSecondaryText() {
        let item = RadioButtonItem(text: "Option", value: 1)

        #expect(item.secondaryText == nil)
        #expect(item.value == AnyHashable(1))
    }
}

@Suite("RMF sheet layout")
struct RMFSheetLayoutTests {

    @available(iOS 16, macOS 13, *)
    @Test("Phones use the fullscreen flag", .timeLimit(.minutes(1)))
    func phonesUseTheFullscreenFlag() {
        #expect(RMFSheetLayout.resolve(idiom: .phone, horizontalSizeClass: .compact, fullscreen: false) == .phone)
        #expect(RMFSheetLayout.resolve(idiom: .phone, horizontalSizeClass: .compact, fullscreen: true) == .phoneFullscreen)
        #expect(RMFSheetLayout.resolve(idiom: .phone, horizontalSizeClass: .regular, fullscreen: false) == .phone)
    }

    @available(iOS 16, macOS 13, *)
    @Test("iPad uses the size class and ignores the fullscreen flag", .timeLimit(.minutes(1)))
    func iPadUsesTheSizeClass() {
        #expect(RMFSheetLayout.resolve(idiom: .pad, horizontalSizeClass: .regular, fullscreen: true) == .padRegular)
        #expect(RMFSheetLayout.resolve(idiom: .pad, horizontalSizeClass: .compact, fullscreen: false) == .padCompact)
        #expect(RMFSheetLayout.resolve(idiom: .pad, horizontalSizeClass: nil, fullscreen: false) == .padRegular)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tall layouts pin the actions to the bottom", .timeLimit(.minutes(1)))
    func tallLayoutsPinTheActions() {
        let pinned = RMFSheetLayout.allCases.filter { $0.metrics.pinsActionsToBottom }

        #expect(pinned == [.phoneFullscreen, .padCompact])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Message padding follows the spec for each layout", .timeLimit(.minutes(1)))
    func messagePaddingFollowsTheSpec() {
        #expect(RMFSheetLayout.phone.metrics.messageHorizontalPadding == 24)
        #expect(RMFSheetLayout.phoneFullscreen.metrics.messageHorizontalPadding == 0)
        #expect(RMFSheetLayout.phoneFullscreen.metrics.cardHorizontalMargin == 24)
        #expect(RMFSheetLayout.padRegular.metrics.messageHorizontalPadding == 32)
        #expect(RMFSheetLayout.padCompact.metrics.messageHorizontalPadding == 24)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Actions sit 20 below content on phone and 24 on iPad", .timeLimit(.minutes(1)))
    func actionsTopPaddingDiffersByPlatform() {
        #expect(RMFSheetLayout.phone.metrics.actionsTopPadding == 20)
        #expect(RMFSheetLayout.padRegular.metrics.actionsTopPadding == 24)
        #expect(RMFSheetLayout.padCompact.metrics.actionsTopPadding == 24)
    }
}

#endif
