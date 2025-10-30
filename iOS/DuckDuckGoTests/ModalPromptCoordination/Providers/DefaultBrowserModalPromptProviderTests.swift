//
//  DefaultBrowserModalPromptProviderTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Testing
import SetDefaultBrowserUI
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Default Browser Modal Prompt Provider")
final class DefaultBrowserModalPromptProviderTests {

    @Test("Check No Prompt Configuration Is Returned When Presenter Returns Nil")
    func whenPresenterReturnsNilThenProvideModalPromptReturnsNil() {
        // GIVEN
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: nil)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let result = sut.provideModalPrompt()

        // THEN
        #expect(result == nil)
        #expect(presenter.didCallMakePresentDefaultModalPrompt)
    }

    @Test("Check Prompt Configuration Is Returned When Presenter Returns View Controller")
    func whenPresenterReturnsViewControllerThenProvideModalPromptReturnsConfiguration() {
        // GIVEN
        let mockViewController = UIViewController()
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let result = sut.provideModalPrompt()

        // THEN
        #expect(result != nil)
        #expect(result?.viewController == mockViewController)
        #expect(presenter.didCallMakePresentDefaultModalPrompt)
    }

    @Test("Check View Controller Preserves Modal Presentation Style")
    func whenPresenterReturnsViewControllerThenModalPresentationStyleIsPreserved() {
        // GIVEN
        let mockViewController = UIViewController()
        mockViewController.modalPresentationStyle = .fullScreen
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == .fullScreen)
    }

    @Test(
        "Check View Controller Preserves Different Presentation Styles",
        arguments: [
            UIModalPresentationStyle.fullScreen,
            .pageSheet,
            .formSheet,
            .overFullScreen,
            .popover
        ]
    )
    func whenViewControllerHasDifferentPresentationStylesThenTheyArePreserved(style: UIModalPresentationStyle) {
        // GIVEN
        let mockViewController = UIViewController()
        mockViewController.modalPresentationStyle = style
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == style)
    }

    @Test(
        "Check View Controller Preserves Different Transition Styles",
        arguments: [
            UIModalTransitionStyle.coverVertical,
            .flipHorizontal,
            .crossDissolve,
            .partialCurl
        ]
    )
    func whenViewControllerHasDifferentTransitionStylesThenTheyArePreserved(style: UIModalTransitionStyle) {
        // GIVEN
        let mockViewController = UIViewController()
        mockViewController.modalTransitionStyle = style
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalTransitionStyle == style)
    }

    @Test("Check View Controller Preserves isModalInPresentation Property")
    func whenViewControllerHasIsModalInPresentationSetThenItIsPreserved() {
        // GIVEN
        let mockViewController = UIViewController()
        mockViewController.isModalInPresentation = false
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.isModalInPresentation == false)
    }

    @Test("Check Configuration Sets Animated To True")
    func whenProvideModalPromptCalledThenConfigurationSetsAnimatedToTrue() {
        // GIVEN
        let mockViewController = UIViewController()
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.animated == true)
    }
}

// This should belong to SetAsDefaultBrowserTestSupport. Had linking issue as UI depends on DesignResourceKitIcons. Possibly TestSupport needs to depend on that too. Will investigate in a follow up task
@MainActor
public final class MockDefaultBrowserPromptPresenter: DefaultBrowserPromptPresenting {
    private let viewControllerToReturn: UIViewController?
    public private(set) var didCallMakePresentDefaultModalPrompt = false
    public private(set) var makeCallCount = 0

    public init(viewControllerToReturn: UIViewController?) {
        self.viewControllerToReturn = viewControllerToReturn
    }

    public func makePresentDefaultModalPrompt() -> UIViewController? {
        didCallMakePresentDefaultModalPrompt = true
        makeCallCount += 1
        return viewControllerToReturn
    }
}
