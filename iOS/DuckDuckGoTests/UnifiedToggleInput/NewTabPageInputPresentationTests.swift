//
//  NewTabPageInputPresentationTests.swift
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
import XCTest
@testable import DuckDuckGo

final class NewTabPageInputPresentationTests: XCTestCase {

    func testWhenPageHasNoInlineInputThenBrowserChromeIsPreserved() {
        let configurations = [(usesUnifiedInput: false, isEditing: false),
                              (usesUnifiedInput: true, isEditing: false),
                              (usesUnifiedInput: true, isEditing: true)]
        for configuration in configurations {
            let presentation = NewTabPageInputPresentation.resolve(
                hasInlineInput: false,
                usesUnifiedInput: configuration.usesUnifiedInput,
                isLegacyInputEditing: false,
                isUnifiedInputEditing: configuration.isEditing,
                isHandingOff: false)
            XCTAssertEqual(presentation, .browser)
            XCTAssertFalse(presentation.hidesNavigationContainer)
            XCTAssertFalse(presentation.hidesRestingOmnibar)
            XCTAssertTrue(presentation.reservesAddressBarSpace)
            XCTAssertEqual(presentation.transition, .omnibar)
        }
    }

    func testRestingInputHidesChromeWithAndWithoutUnifiedInput() {
        for usesUnifiedInput in [false, true] {
            let presentation = resolve(usesUnifiedInput: usesUnifiedInput)
            XCTAssertEqual(presentation, .resting(usesUnifiedInput: usesUnifiedInput))
            XCTAssertTrue(presentation.hidesNavigationContainer)
            XCTAssertFalse(presentation.reservesAddressBarSpace)
        }
    }

    func testLegacyEditingRevealsTheRealOmnibarAndUsesItsExistingTransition() {
        let presentation = resolve(usesUnifiedInput: false, legacyEditing: true)
        XCTAssertEqual(presentation, .editing(usesUnifiedInput: false))
        XCTAssertFalse(presentation.hidesNavigationContainer)
        XCTAssertFalse(presentation.hidesRestingOmnibar)
        XCTAssertTrue(presentation.reservesAddressBarSpace)
        XCTAssertEqual(presentation.transition, .omnibar)
    }

    func testWhenUnifiedInputIsEditingThenOnlyTheEditorIsRevealedWithoutReservingAddressBarSpace() {
        let presentation = resolve(unifiedEditing: true)
        XCTAssertFalse(presentation.hidesNavigationContainer)
        XCTAssertTrue(presentation.hidesRestingOmnibar)
        XCTAssertFalse(presentation.reservesAddressBarSpace)
        XCTAssertEqual(presentation.transition, .inlineInput)
    }

    func testWhenHandoffStartsBeforeEitherEditorIsActiveThenEditingPresentationIsUsed() {
        for usesUnifiedInput in [false, true] {
            let presentation = resolve(usesUnifiedInput: usesUnifiedInput, handingOff: true)
            XCTAssertEqual(presentation, .editing(usesUnifiedInput: usesUnifiedInput))
            XCTAssertFalse(presentation.hidesNavigationContainer)
        }
    }

    func testWhenEditorSessionEndsDuringDismissThenEditingPresentationIsKept() {
        let presentation = NewTabPageInputPresentation.resolve(
            hasInlineInput: true,
            usesUnifiedInput: true,
            isLegacyInputEditing: false,
            isUnifiedInputEditing: false,
            isHandingOff: false,
            isDismissing: true)

        XCTAssertFalse(presentation.hidesNavigationContainer)
        XCTAssertTrue(presentation.hidesRestingOmnibar)
        XCTAssertFalse(presentation.reservesAddressBarSpace)
    }

    private func resolve(usesUnifiedInput: Bool = true,
                         legacyEditing: Bool = false,
                         unifiedEditing: Bool = false,
                         handingOff: Bool = false) -> NewTabPageInputPresentation {
        .resolve(hasInlineInput: true,
                 usesUnifiedInput: usesUnifiedInput,
                 isLegacyInputEditing: legacyEditing,
                 isUnifiedInputEditing: unifiedEditing,
                 isHandingOff: handingOff)
    }
}

@MainActor
final class NewTabPageInputCoordinatorTests: XCTestCase {

    func testBrowserReconciliationDoesNotTouchExistingChrome() {
        let coordinator = makeCoordinator()
        coordinator.navigationBarContainer.alpha = 0.4
        coordinator.navigationBarContainer.isUserInteractionEnabled = false
        coordinator.navigationBarCollectionView.isHidden = true
        coordinator.setNewTabPageInputPresentation(.browser)
        XCTAssertEqual(coordinator.navigationBarContainer.alpha, 0.4, accuracy: 0.001)
        XCTAssertFalse(coordinator.navigationBarContainer.isUserInteractionEnabled)
        XCTAssertTrue(coordinator.navigationBarCollectionView.isHidden)
        XCTAssertTrue(coordinator.constraints.contentContainerTop.isActive)
    }

    func testLegacyHideOnlyPathPreservesAlphaAndInteraction() {
        let coordinator = makeCoordinator(position: .bottom)
        coordinator.navigationBarContainer.alpha = 0.4
        coordinator.navigationBarContainer.isUserInteractionEnabled = true
        coordinator.hideNavigationBarWithBottomPosition()
        XCTAssertTrue(coordinator.navigationBarContainer.isHidden)
        XCTAssertEqual(coordinator.navigationBarContainer.alpha, 0.4, accuracy: 0.001)
        XCTAssertTrue(coordinator.navigationBarContainer.isUserInteractionEnabled)
    }

    func testLegacyShowRestoresTheExistingChromePose() {
        let coordinator = makeCoordinator(position: .bottom)
        coordinator.navigationBarContainer.alpha = 0.4
        coordinator.navigationBarContainer.isHidden = true
        coordinator.navigationBarContainer.isUserInteractionEnabled = false
        coordinator.showNavigationBarWithBottomPosition()
        XCTAssertFalse(coordinator.navigationBarContainer.isHidden)
        XCTAssertEqual(coordinator.navigationBarContainer.alpha, 1)
        XCTAssertTrue(coordinator.navigationBarContainer.isUserInteractionEnabled)
        XCTAssertTrue(coordinator.constraints.contentContainerBottomToToolbarTop.isActive)
    }

    func testSuppressionRestoresExistingInteractionAndAlpha() {
        let coordinator = makeCoordinator()
        coordinator.navigationBarContainer.alpha = 0.4
        coordinator.navigationBarContainer.isUserInteractionEnabled = false
        coordinator.setNewTabPageInputPresentation(.resting(usesUnifiedInput: true))
        coordinator.setNewTabPageInputPresentation(.browser)
        XCTAssertEqual(coordinator.navigationBarContainer.alpha, 0.4, accuracy: 0.001)
        XCTAssertFalse(coordinator.navigationBarContainer.isUserInteractionEnabled)
    }

    func testLegacyFocusReclaimsAndRestoresTheChromeSpace() {
        let coordinator = makeCoordinator()
        coordinator.setNewTabPageInputPresentation(.resting(usesUnifiedInput: false))
        XCTAssertTrue(coordinator.navigationBarContainer.isHidden)
        XCTAssertTrue(coordinator.constraints.contentContainerTopToSafeArea.isActive)
        coordinator.setNewTabPageInputPresentation(.editing(usesUnifiedInput: false))
        XCTAssertFalse(coordinator.navigationBarContainer.isHidden)
        XCTAssertFalse(coordinator.navigationBarCollectionView.isHidden)
        XCTAssertTrue(coordinator.constraints.contentContainerTop.isActive)
        coordinator.setNewTabPageInputPresentation(.resting(usesUnifiedInput: false))
        XCTAssertTrue(coordinator.navigationBarContainer.isHidden)
        XCTAssertTrue(coordinator.constraints.contentContainerTopToSafeArea.isActive)
    }

    func testWhenInlinePresentationChangesThenContentAndStatusBackgroundUseSafeAreaAnchors() {
        for position in [AddressBarPosition.top, .bottom] {
            for floating in [false, true] {
                let coordinator = makeCoordinator(position: position)
                coordinator.setFloatingUIEnabled(floating)
                let states: [(presentation: NewTabPageInputPresentation, hidesNavigation: Bool)] = [
                    (.resting(usesUnifiedInput: true), true),
                    (.editing(usesUnifiedInput: true), false),
                    (.resting(usesUnifiedInput: true), true)
                ]
                for state in states {
                    coordinator.setNewTabPageInputPresentation(state.presentation)
                    XCTAssertTrue(coordinator.navigationBarCollectionView.isHidden)
                    XCTAssertTrue(coordinator.constraints.contentContainerTopToSafeArea.isActive)
                    XCTAssertFalse(coordinator.constraints.contentContainerTop.isActive)
                    XCTAssertTrue(coordinator.constraints.statusBackgroundBottomToSafeAreaTop.isActive)
                    XCTAssertFalse(coordinator.constraints.statusBackgroundToNavigationBarContainerBottom.isActive)
                    XCTAssertEqual(coordinator.navigationBarContainer.isHidden, state.hidesNavigation)
                }
            }
        }
    }

    func testLeavingInlinePageRestoresTopAnchorAndRestingOmnibar() {
        let coordinator = makeCoordinator()
        coordinator.setNewTabPageInputPresentation(.resting(usesUnifiedInput: true))
        coordinator.setNewTabPageInputPresentation(.browser)
        XCTAssertFalse(coordinator.navigationBarContainer.isHidden)
        XCTAssertFalse(coordinator.navigationBarCollectionView.isHidden)
        XCTAssertTrue(coordinator.navigationBarContainer.isUserInteractionEnabled)
        XCTAssertTrue(coordinator.constraints.contentContainerTop.isActive)
        XCTAssertFalse(coordinator.constraints.contentContainerTopToSafeArea.isActive)
        XCTAssertTrue(coordinator.constraints.statusBackgroundToNavigationBarContainerBottom.isActive)
        XCTAssertFalse(coordinator.constraints.statusBackgroundBottomToSafeAreaTop.isActive)
    }

    func testLiftingSuppressionPreservesLayoutRequestedHiddenState() {
        let coordinator = makeCoordinator(position: .bottom)
        coordinator.hideNavigationBarWithBottomPosition()
        coordinator.setNewTabPageInputPresentation(.resting(usesUnifiedInput: true))
        coordinator.setNewTabPageInputPresentation(.browser)
        XCTAssertTrue(coordinator.navigationBarContainer.isHidden)
    }

    func testLeavingInlinePageInterruptsDismissWithoutRunningItsCompletion() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.isOmnibarDismissInProgress)
        coordinator.unifiedToggleInputContainer = UIView()
        coordinator.setNewTabPageInputPresentation(.editing(usesUnifiedInput: true))
        var interrupted = false
        var completed = false
        coordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            interruptCleanup: { interrupted = true },
            completion: { completed = true })
        XCTAssertTrue(coordinator.isInlineInputDismissInProgress)
        XCTAssertTrue(coordinator.isOmnibarDismissInProgress)
        coordinator.setNewTabPageInputPresentation(.browser)
        XCTAssertFalse(coordinator.isInlineInputDismissInProgress)
        XCTAssertFalse(coordinator.isOmnibarDismissInProgress)
        XCTAssertTrue(interrupted)
        XCTAssertFalse(completed)
        XCTAssertFalse(coordinator.navigationBarCollectionView.isHidden)
        XCTAssertTrue(coordinator.constraints.contentContainerTop.isActive)
    }

    func testWhenDismissIsReplacedThenOnlyTheCurrentTransitionRemainsInProgress() {
        let coordinator = makeCoordinator()
        coordinator.unifiedToggleInputContainer = UIView()
        var oldCompletionCalled = false
        coordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            completion: { oldCompletionCalled = true })
        coordinator.hideUnifiedToggleInputOmnibar(transition: .inlineInput)

        XCTAssertTrue(coordinator.isOmnibarDismissInProgress)
        XCTAssertFalse(oldCompletionCalled)

        coordinator.stopInFlightOmnibarDismiss(runningInterruptCleanup: true)
        XCTAssertFalse(coordinator.isOmnibarDismissInProgress)
        XCTAssertFalse(oldCompletionCalled)
    }

    private func makeCoordinator(position: AddressBarPosition = .top) -> MainViewCoordinator {
        let parent = UIViewController()
        let coordinator = MainViewCoordinator(parentController: parent)
        let root = coordinator.superview
        let content = UIView()
        let status = UIView()
        let navigation = MainViewFactory.NavigationBarContainer(frame: .zero)
        let collection = MainViewFactory.NavigationBarCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        root.addSubview(content)
        root.addSubview(status)
        root.addSubview(navigation)
        navigation.addSubview(collection)
        coordinator.contentContainer = content
        coordinator.navigationBarContainer = navigation
        coordinator.navigationBarCollectionView = collection
        coordinator.addressBarPosition = position
        let constraints = coordinator.constraints
        constraints.contentContainerTop = content.topAnchor.constraint(equalTo: navigation.bottomAnchor)
        constraints.contentContainerTop.isActive = true
        constraints.contentContainerTopToSafeArea = content.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor)
        constraints.contentContainerTopToSuperview = content.topAnchor.constraint(equalTo: root.topAnchor)
        constraints.statusBackgroundToNavigationBarContainerBottom = status.bottomAnchor.constraint(equalTo: navigation.bottomAnchor)
        constraints.statusBackgroundToNavigationBarContainerBottom.isActive = true
        constraints.statusBackgroundBottomToSafeAreaTop = status.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor)
        constraints.contentContainerBottomToToolbarTop = content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        constraints.contentContainerBottomToUnifiedToggleInputTop = content.bottomAnchor.constraint(equalTo: navigation.topAnchor)
        constraints.contentContainerBottomToSafeArea = content.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor)
        return coordinator
    }
}
