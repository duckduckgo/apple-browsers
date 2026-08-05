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

    @Test("Prepared Prompt Is Invalid After Browser Becomes Default")
    func whenBrowserBecomesDefaultThenPreparedPromptIsInvalid() throws {
        let mockViewController = UIViewController()
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)
        let configuration = try #require(sut.provideModalPrompt())
        presenter.isPreparedPromptStillValidResult = false

        let isStillValid = sut.isPreparedModalPromptStillValid(configuration)

        #expect(!isStillValid)
        #expect(presenter.makeCallCount == 1)
        #expect(presenter.isPreparedPromptStillValidCallCount == 1)
    }

    @Test("Prepared Prompt Remains Valid When Presenter Revalidation Succeeds")
    func whenPresenterRevalidationSucceedsThenPreparedPromptRemainsValid() throws {
        let mockViewController = UIViewController()
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: mockViewController)
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)
        let configuration = try #require(sut.provideModalPrompt())

        let isStillValid = sut.isPreparedModalPromptStillValid(configuration)

        #expect(isStillValid)
        #expect(presenter.makeCallCount == 1)
        #expect(presenter.isPreparedPromptStillValidCallCount == 1)
    }

    @Test("Retained Prepared Prompt Uses Current Browser Revalidation")
    func whenPreparedPromptWasRetainedThenProviderUsesCurrentBrowserRevalidation() throws {
        let presenter = MockDefaultBrowserPromptPresenter(viewControllerToReturn: UIViewController())
        let sut = DefaultBrowserModalPromptProvider(presenter: presenter)
        let configuration = try #require(sut.provideModalPrompt())
        presenter.isRetainedPreparedPromptStillValidResult = false

        let isStillValid = sut.isRetainedPreparedModalPromptStillValid(configuration)

        #expect(!isStillValid)
        #expect(presenter.isPreparedPromptStillValidCallCount == 0)
        #expect(presenter.isRetainedPreparedPromptStillValidCallCount == 1)
    }
}

// This should belong to SetAsDefaultBrowserTestSupport. Had linking issue as UI depends on DesignResourceKitIcons. Possibly TestSupport needs to depend on that too. Will investigate in a follow up task
@MainActor
public final class MockDefaultBrowserPromptPresenter: DefaultBrowserPromptPresenting {
    private let viewControllerToReturn: UIViewController?
    public var isPreparedPromptStillValidResult = true
    public var isRetainedPreparedPromptStillValidResult = true
    public private(set) var didCallMakePresentDefaultModalPrompt = false
    public private(set) var makeCallCount = 0
    public private(set) var isPreparedPromptStillValidCallCount = 0
    public private(set) var isRetainedPreparedPromptStillValidCallCount = 0

    public init(viewControllerToReturn: UIViewController?) {
        self.viewControllerToReturn = viewControllerToReturn
    }

    public func makePresentDefaultModalPrompt() -> UIViewController? {
        didCallMakePresentDefaultModalPrompt = true
        makeCallCount += 1
        return viewControllerToReturn
    }

    public func isPreparedDefaultModalPromptStillValid() -> Bool {
        isPreparedPromptStillValidCallCount += 1
        return isPreparedPromptStillValidResult
    }

    public func isRetainedPreparedDefaultModalPromptStillValid() -> Bool {
        isRetainedPreparedPromptStillValidCallCount += 1
        return isRetainedPreparedPromptStillValidResult
    }
}
