//
//  RMFSheetTests.swift
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
struct RMFSheetTests {

    private typealias Choice = RMFSheetContent.ChoiceList.Choice

    private let choices = [
        Choice(id: "a", title: "A", description: nil),
        Choice(id: "b", title: "B", description: "Description"),
        Choice(id: "c", title: "C", description: nil)
    ]

    private func content(height: RMFSheetContent.Height) -> RMFSheetContent {
        RMFSheetContent(height: height, title: "Title", primaryButtonTitle: "OK", exit: .closeButton)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A choice list takes 2 or 3 choices with a known preselection", .timeLimit(.minutes(1)))
    func choiceListAcceptsTwoOrThreeChoices() {
        #expect(RMFSheetContent.ChoiceList(choices: Array(choices.prefix(2)), preselectedID: "b") != nil)
        #expect(RMFSheetContent.ChoiceList(choices: choices, preselectedID: "c") != nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A choice list rejects the wrong count, an unknown preselection or duplicate ids", .timeLimit(.minutes(1)))
    func choiceListRejectsInvalidInput() {
        #expect(RMFSheetContent.ChoiceList(choices: Array(choices.prefix(1)), preselectedID: "a") == nil)
        #expect(RMFSheetContent.ChoiceList(choices: choices + [Choice(id: "d", title: "D", description: nil)], preselectedID: "a") == nil)
        #expect(RMFSheetContent.ChoiceList(choices: choices, preselectedID: "missing") == nil)
        #expect(RMFSheetContent.ChoiceList(choices: [choices[0], choices[0]], preselectedID: "a") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every exit keeps a way out of the sheet", .timeLimit(.minutes(1)))
    func everyExitKeepsAWayOut() {
        let exits: [RMFSheetContent.Exit] = [.closeButton, .secondaryButton("Not now"), .closeAndSecondaryButton("Not now")]
        for exit in exits {
            #expect(exit.showsCloseButton || exit.secondaryButtonTitle != nil)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A content-height sheet uses the content detent and a full one the large detent", .timeLimit(.minutes(1)))
    func heightSetsDetent() {
        let contentSheet = RMFSheetViewController(content: content(height: .content)) { _ in }
        let fullSheet = RMFSheetViewController(content: content(height: .full)) { _ in }

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        #expect(contentSheet.modalPresentationStyle == (isPad ? .formSheet : .pageSheet))
        #expect(contentSheet.sheetPresentationController?.detents.map(\.identifier) == [RMFSheetViewController.contentDetentIdentifier])
        #expect(fullSheet.sheetPresentationController?.detents.map(\.identifier) == [.large])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Swiping the sheet away reports a close", .timeLimit(.minutes(1)))
    func swipeDismissReportsClose() throws {
        var actions: [RMFSheetAction] = []
        let sheet = RMFSheetViewController(content: content(height: .content)) { actions.append($0) }
        let presentationController = try #require(sheet.presentationController)

        sheet.presentationControllerDidDismiss(presentationController)

        #expect(actions == [.close])
    }
}
