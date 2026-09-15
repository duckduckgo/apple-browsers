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

    func testOrdinaryPageAlwaysUsesBrowserPresentationRegardlessOfEditingState() {
        for usesUnifiedInput in [false, true] {
            for legacyEditing in [false, true] {
                for unifiedEditing in [false, true] {
                    for handingOff in [false, true] {
                        let presentation = NewTabPageInputPresentation.resolve(
                            hasInlineInput: false,
                            usesUnifiedInput: usesUnifiedInput,
                            isLegacyInputEditing: legacyEditing,
                            isUnifiedInputEditing: unifiedEditing,
                            isHandingOff: handingOff)
                        XCTAssertEqual(presentation, .browser)
                        XCTAssertFalse(presentation.hidesNavigationContainer)
                        XCTAssertFalse(presentation.hidesRestingOmnibar)
                        XCTAssertTrue(presentation.reservesAddressBarSpace)
                        XCTAssertEqual(presentation.transition, .omnibar)
                    }
                }
            }
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

    func testUnifiedEditingRevealsOnlyTheEditorAndKeepsThePageStationary() {
        let presentation = resolve(unifiedEditing: true)
        XCTAssertFalse(presentation.hidesNavigationContainer)
        XCTAssertTrue(presentation.hidesRestingOmnibar)
        XCTAssertFalse(presentation.reservesAddressBarSpace)
        XCTAssertEqual(presentation.transition, .inlineInput)
    }

    func testFailedHandoffReturnsToRestingPresentation() {
        XCTAssertEqual(resolve(handingOff: true), .editing(usesUnifiedInput: true))
        XCTAssertEqual(resolve(handingOff: false), .resting(usesUnifiedInput: true))
    }

    func testSuccessfulHandoffStaysEditingUntilTheSessionEnds() {
        XCTAssertEqual(resolve(handingOff: true), resolve(unifiedEditing: true))
        XCTAssertEqual(resolve(unifiedEditing: true, handingOff: false), .editing(usesUnifiedInput: true))
        XCTAssertEqual(resolve(unifiedEditing: false), .resting(usesUnifiedInput: true))
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

    func testInlineFocusAndCancelKeepContentAnchorsStationaryAcrossChromeConfigurations() {
        for position in [AddressBarPosition.top, .bottom] {
            for floating in [false, true] {
                let coordinator = makeCoordinator(position: position)
                coordinator.setFloatingUIEnabled(floating)
                for presentation in [NewTabPageInputPresentation.resting(usesUnifiedInput: true),
                                     .editing(usesUnifiedInput: true),
                                     .resting(usesUnifiedInput: true),
                                     .editing(usesUnifiedInput: true)] {
                    coordinator.setNewTabPageInputPresentation(presentation)
                    coordinator.ensureBottomOmnibarAttachedToToolbarIfNeeded()
                    XCTAssertFalse(coordinator.isOmnibarInToolbar)
                    XCTAssertTrue(coordinator.navigationBarCollectionView.isHidden)
                    XCTAssertTrue(coordinator.constraints.contentContainerTopToSafeArea.isActive)
                    XCTAssertFalse(coordinator.constraints.contentContainerTop.isActive)
                    XCTAssertTrue(coordinator.constraints.statusBackgroundBottomToSafeAreaTop.isActive)
                    XCTAssertFalse(coordinator.constraints.statusBackgroundToNavigationBarContainerBottom.isActive)
                    XCTAssertEqual(coordinator.navigationBarContainer.isHidden, presentation.hidesNavigationContainer)
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

    func testRepeatedPresentationDoesNotResetAnAnimationAlpha() {
        let coordinator = makeCoordinator()
        coordinator.setNewTabPageInputPresentation(.editing(usesUnifiedInput: true))
        coordinator.navigationBarContainer.alpha = 0.3
        coordinator.setNewTabPageInputPresentation(.editing(usesUnifiedInput: true))
        XCTAssertEqual(coordinator.navigationBarContainer.alpha, 0.3, accuracy: 0.001)
    }

    func testLeavingInlinePageInterruptsDismissWithoutRunningItsCompletion() {
        let coordinator = makeCoordinator()
        coordinator.unifiedToggleInputContainer = UIView()
        coordinator.setNewTabPageInputPresentation(.editing(usesUnifiedInput: true))
        var interrupted = false
        var completed = false
        coordinator.hideUnifiedToggleInputOmnibar(
            transition: .inlineInput,
            interruptCleanup: { interrupted = true },
            completion: { completed = true })
        coordinator.setNewTabPageInputPresentation(.browser)
        XCTAssertTrue(interrupted)
        XCTAssertFalse(completed)
        XCTAssertFalse(coordinator.navigationBarCollectionView.isHidden)
        XCTAssertTrue(coordinator.constraints.contentContainerTop.isActive)
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
