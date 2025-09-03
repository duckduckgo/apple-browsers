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

        let scanSut = ActionsHandler(step: scanStep, isEmailConfirmationDecouplingFeatureOn: false)
        let optOutSut = ActionsHandler(step: optOutStep, isEmailConfirmationDecouplingFeatureOn: false)

        XCTAssertEqual(scanSut.stepType, .scan)
        XCTAssertEqual(optOutSut.stepType, .optOut)
    }

    // MARK: - Next Action

    func testWhenStepHasNoActions_thenNilIsReturned() {
        let step = Step(type: .scan, actions: [Action]())
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        XCTAssertNil(sut.nextAction())
    }

    func testWhenNextStepDoesNotFindAnyMoreActions_thenNilIsReturned() {
        let firstAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let secondAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let step = Step(type: .scan, actions: [firstAction, secondAction])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction() // Returns the first action
        _ = sut.nextAction() // Returns the second action

        XCTAssertNil(sut.nextAction())
    }

    func testWhenNextStepFindsAnAction_thenThatNextActionIsReturned() {
        let firstAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let secondAction = NavigateAction(id: "navigate", actionType: .navigate, url: "url", ageRange: [String](), dataSource: nil)
        let step = Step(type: .scan, actions: [firstAction, secondAction])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction() // Returns the first action
        let action = sut.nextAction() // Returns the second and last action

        XCTAssertEqual(action?.id, secondAction.id)
    }

    // MARK: - Current Action

    func testWhenNoActionExecuted_thenCurrentActionReturnsNil() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        XCTAssertNil(sut.currentAction())
    }

    func testWhenFirstActionExecuted_thenCurrentActionReturnsFirstAction() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        let firstAction = sut.nextAction()
        let currentAction = sut.currentAction()

        XCTAssertNotNil(firstAction)
        XCTAssertEqual(currentAction?.id, firstAction?.id)
        XCTAssertEqual(currentAction?.id, "action1")
    }

    func testWhenMiddleActionExecuted_thenCurrentActionReturnsMiddleAction() {
        let step = createStepWithActions(["action1", "action2", "action3"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction() // Execute first action
        let secondAction = sut.nextAction() // Execute second action
        let currentAction = sut.currentAction()

        XCTAssertEqual(currentAction?.id, secondAction?.id)
        XCTAssertEqual(currentAction?.id, "action2")
    }

    func testWhenLastActionExecuted_thenCurrentActionReturnsLastAction() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction() // Execute first action
        let lastAction = sut.nextAction() // Execute last action
        let currentAction = sut.currentAction()

        XCTAssertEqual(currentAction?.id, lastAction?.id)
        XCTAssertEqual(currentAction?.id, "action2")
    }

    func testWhenEmptyActionsArray_thenCurrentActionReturnsNil() {
        let step = createStepWithActions([])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)
        _ = sut.nextAction()

        XCTAssertNil(sut.currentAction())
    }

    func testWhenCurrentActionCalledMultipleTimes_thenReturnsSameAction() {
        let step = createStepWithActions(["action1", "action2"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

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
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

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
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

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
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

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
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction()

        let newActions = [createTestAction(id: "new1")]
        sut.insert(actions: newActions)

        XCTAssertEqual(sut.nextAction()?.id, "new1")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenInsertingEmptyArray_thenNoActionsAdded() {
        let step = createStepWithActions(["original1"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction()

        sut.insert(actions: [])

        XCTAssertNil(sut.nextAction())
    }

    func testInsertingActionsPreservesCurrentActionState() {
        let step = createStepWithActions(["original1", "original2"])
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

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
        let sut = ActionsHandler(step: step, isEmailConfirmationDecouplingFeatureOn: false)

        _ = sut.nextAction()

        sut.insert(actions: [createTestAction(id: "first1")])
        sut.insert(actions: [createTestAction(id: "second1"), createTestAction(id: "second2")])

        XCTAssertEqual(sut.nextAction()?.id, "second1")
        XCTAssertEqual(sut.nextAction()?.id, "second2")
        XCTAssertEqual(sut.nextAction()?.id, "first1")
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
