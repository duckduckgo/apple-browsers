//
//  ActionsHandlerTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class ActionsHandlerTests: XCTestCase {

    // MARK: - Initialization

    func testWhenCreatingActionHandlerWithStep_thenStepTypeIsAccurate() {
        let scanStep = Step(type: .scan, actions: [])
        let optOutStep = Step(type: .optOut, actions: [])

        let scanSut = ActionsHandler.forScan(scanStep)
        let optOutSut = ActionsHandler.forOptOut(optOutStep, haltsAtEmailConfirmation: false)

        XCTAssertEqual(scanSut.stepType, .scan)
        XCTAssertEqual(optOutSut.stepType, .optOut)
    }

    // MARK: - Next Action

    func testWhenStepHasNoActions_thenNilIsReturned() {
        let step = Step(type: .scan, actions: [Action]())
        let sut = ActionsHandler.forScan(step)

        XCTAssertNil(sut.nextAction())
    }

    func testWhenNextStepDoesNotFindAnyMoreActions_thenNilIsReturned() {
        let firstAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let secondAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let step = Step(type: .scan, actions: [firstAction, secondAction])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction() // Returns the first action
        _ = sut.nextAction() // Returns the second action

        XCTAssertNil(sut.nextAction())
    }

    func testWhenNextStepFindsAnAction_thenThatNextActionIsReturned() {
        let firstAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let secondAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let step = Step(type: .scan, actions: [firstAction, secondAction])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction() // Returns the first action
        let action = sut.nextAction() // Returns the second and last action

        XCTAssertEqual(action?.id, secondAction.id)
    }

    // MARK: - Current Action

    func testWhenNoActionExecuted_thenCurrentActionReturnsNil() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler.forScan(step)

        XCTAssertNil(sut.currentAction())
    }

    func testWhenFirstActionExecuted_thenCurrentActionReturnsFirstAction() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler.forScan(step)

        let firstAction = sut.nextAction()
        let currentAction = sut.currentAction()

        XCTAssertNotNil(firstAction)
        XCTAssertEqual(currentAction?.id, firstAction?.id)
        XCTAssertEqual(currentAction?.id, "action1")
    }

    func testWhenMiddleActionExecuted_thenCurrentActionReturnsMiddleAction() {
        let step = createStepWithActions(["action1", "action2", "action3"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction() // Execute first action
        let secondAction = sut.nextAction() // Execute second action
        let currentAction = sut.currentAction()

        XCTAssertEqual(currentAction?.id, secondAction?.id)
        XCTAssertEqual(currentAction?.id, "action2")
    }

    func testWhenLastActionExecuted_thenCurrentActionReturnsLastAction() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction() // Execute first action
        let lastAction = sut.nextAction() // Execute last action
        let currentAction = sut.currentAction()

        XCTAssertEqual(currentAction?.id, lastAction?.id)
        XCTAssertEqual(currentAction?.id, "action2")
    }

    func testWhenEmptyActionsArray_thenCurrentActionReturnsNil() {
        let step = createStepWithActions([])
        let sut = ActionsHandler.forScan(step)
        _ = sut.nextAction()

        XCTAssertNil(sut.currentAction())
    }

    func testWhenCurrentActionCalledMultipleTimes_thenReturnsSameAction() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction()
        let firstCall = sut.currentAction()
        let secondCall = sut.currentAction()
        let thirdCall = sut.currentAction()

        XCTAssertEqual(firstCall?.id, "action1")
        XCTAssertEqual(secondCall?.id, "action1")
        XCTAssertEqual(thirdCall?.id, "action1")
    }

    // MARK: - Insert Action

    func testWhenInsertingActionsWithNoExecutedAction_thenActionsAppendedToEnd() {
        let step = createStepWithActions(["original1", "original2"])
        let sut = ActionsHandler.forScan(step)

        let newActions = [createTestAction(id: "new1"), createTestAction(id: "new2")]
        sut.insert(actions: newActions)

        XCTAssertEqual(sut.nextAction()?.id, "original1")
        XCTAssertEqual(sut.nextAction()?.id, "original2")
        XCTAssertEqual(sut.nextAction()?.id, "new1")
        XCTAssertEqual(sut.nextAction()?.id, "new2")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenInsertingActionsAfterFirstActionExecuted_thenActionsInsertedAtCorrectPosition() {
        let step = createStepWithActions(["original1", "original2", "original3"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction()

        let newActions = [createTestAction(id: "new1"), createTestAction(id: "new2")]
        sut.insert(actions: newActions)

        // Should get inserted actions next, then remaining original actions
        XCTAssertEqual(sut.nextAction()?.id, "new1")
        XCTAssertEqual(sut.nextAction()?.id, "new2")
        XCTAssertEqual(sut.nextAction()?.id, "original2")
        XCTAssertEqual(sut.nextAction()?.id, "original3")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenInsertingActionsAfterMiddleActionExecuted_thenActionsInsertedAtCorrectPosition() {
        let step = createStepWithActions(["original1", "original2", "original3", "original4"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction() // Execute first action (original1)
        _ = sut.nextAction() // Execute second action (original2)

        let newActions = [createTestAction(id: "new1")]
        sut.insert(actions: newActions)

        // Should get inserted action next, then remaining original actions
        XCTAssertEqual(sut.nextAction()?.id, "new1")
        XCTAssertEqual(sut.nextAction()?.id, "original3")
        XCTAssertEqual(sut.nextAction()?.id, "original4")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenInsertingSingleAction_thenActionInsertedCorrectly() {
        let step = createStepWithActions(["original1"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction()

        let newActions = [createTestAction(id: "new1")]
        sut.insert(actions: newActions)

        XCTAssertEqual(sut.nextAction()?.id, "new1")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenInsertingEmptyArray_thenNoActionsAdded() {
        let step = createStepWithActions(["original1"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction()

        sut.insert(actions: [])

        XCTAssertNil(sut.nextAction())
    }

    func testInsertingActionsPreservesCurrentActionState() {
        let step = createStepWithActions(["original1", "original2"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction() // Execute first action
        let currentBeforeInsert = sut.currentAction()

        let newActions = [createTestAction(id: "new1")]
        sut.insert(actions: newActions)

        let currentAfterInsert = sut.currentAction()

        XCTAssertEqual(currentBeforeInsert?.id, "original1")
        XCTAssertEqual(currentAfterInsert?.id, "original1")
    }

    func testWhenInsertingActionsMultipleTimes_thenSubsequentActionsAreRunNext() {
        let step = createStepWithActions(["original1"])
        let sut = ActionsHandler.forScan(step)

        _ = sut.nextAction()

        sut.insert(actions: [createTestAction(id: "first1")])
        sut.insert(actions: [createTestAction(id: "second1"), createTestAction(id: "second2")])

        XCTAssertEqual(sut.nextAction()?.id, "second1")
        XCTAssertEqual(sut.nextAction()?.id, "second2")
        XCTAssertEqual(sut.nextAction()?.id, "first1")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenOptOutHaltsAtEmailConfirmation_thenStopsBeforeEmailConfirmationAction() {
        let action1 = createTestAction(id: "navigate1")
        let action2 = createTestAction(id: "navigate2")
        let emailAction = EmailConfirmationAction(id: "email", actionType: .emailConfirmation, pollingTime: 1, dataSource: nil)
        let action3 = createTestAction(id: "navigate3")
        let action4 = createTestAction(id: "navigate4")

        let step = Step(type: .optOut, actions: [action1, action2, emailAction, action3, action4])
        let sut = ActionsHandler.forOptOut(step, haltsAtEmailConfirmation: true)

        XCTAssertEqual(sut.nextAction()?.id, "navigate1")
        XCTAssertEqual(sut.nextAction()?.id, "navigate2")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenOptOutDoesNotHaltAtEmailConfirmation_thenIncludesAllActions() {
        let action1 = createTestAction(id: "navigate1")
        let action2 = createTestAction(id: "navigate2")
        let emailAction = EmailConfirmationAction(id: "email", actionType: .emailConfirmation, pollingTime: 1, dataSource: nil)
        let action3 = createTestAction(id: "navigate3")
        let action4 = createTestAction(id: "navigate4")

        let step = Step(type: .optOut, actions: [action1, action2, emailAction, action3, action4])
        let sut = ActionsHandler.forOptOut(step, haltsAtEmailConfirmation: false)

        XCTAssertEqual(sut.nextAction()?.id, "navigate1")
        XCTAssertEqual(sut.nextAction()?.id, "navigate2")
        XCTAssertEqual(sut.nextAction()?.id, "email")
        XCTAssertEqual(sut.nextAction()?.id, "navigate3")
        XCTAssertEqual(sut.nextAction()?.id, "navigate4")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenEmailConfirmationContinuation_thenReplacesEmailActionWithNavigateAndContinues() throws {
        let action1 = createTestAction(id: "navigate1")
        let action2 = createTestAction(id: "navigate2")
        let emailAction = EmailConfirmationAction(id: "email", actionType: .emailConfirmation, pollingTime: 1, dataSource: nil)
        let action3 = createTestAction(id: "navigate3")
        let action4 = createTestAction(id: "navigate4")

        let step = Step(type: .optOut, actions: [action1, action2, emailAction, action3, action4])
        let confirmationURL = URL(string: "https://example.com/confirm")!
        let sut = ActionsHandler.forEmailConfirmationContinuation(step, confirmationURL: confirmationURL)

        let firstAction = sut.nextAction()
        XCTAssertEqual(firstAction?.id, "email")
        XCTAssertTrue(firstAction is NavigateAction)
        XCTAssertEqual((firstAction as? NavigateAction)?.url, confirmationURL.absoluteString)
        XCTAssertEqual(sut.nextAction()?.id, "navigate3")
        XCTAssertEqual(sut.nextAction()?.id, "navigate4")
        XCTAssertNil(sut.nextAction())
    }

    // MARK: - Test Helpers

    private func createTestAction(id: String) -> NavigateAction {
        return NavigateAction(id: id, actionType: .navigate, url: "https://example.com", ageRange: [], dataSource: nil)
    }

    private func createStepWithActions(_ actionIds: [String]) -> Step {
        let actions = actionIds.map { createTestAction(id: $0) }
        return Step(type: .scan, actions: actions)
    }

}
