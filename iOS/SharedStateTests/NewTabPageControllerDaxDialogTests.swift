//
//  NewTabPageControllerDaxDialogTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo
import Bookmarks
import Combine
import Core
import SwiftUI
@_spi(Testing) import Persistence
import BrowserServicesKit
import RemoteMessaging
import RemoteMessagingTestsUtils
import SubscriptionTestingUtilities
import Onboarding

@testable import Configuration

private class MockURLBasedDebugCommands: URLBasedDebugCommands {
    func handle(url: URL) -> Bool {
        return false
    }
}

@MainActor
final class NewTabPageControllerDaxDialogTests: XCTestCase {

    var variantManager: CapturingVariantManager!
    var dialogFactory: CapturingNewTabDaxDialogProvider!
    var specProvider: MockDaxDialogsManager!
    var flowProvider: MockOnboardingFlowProvider!
    var tutorialSettings: MockTutorialSettings!
    var hvc: NewTabPageViewController!
    private var testWindow: UIWindow?

    override func setUpWithError() throws {
        variantManager = CapturingVariantManager()
        dialogFactory = CapturingNewTabDaxDialogProvider()
        specProvider = MockDaxDialogsManager()
        flowProvider = MockOnboardingFlowProvider()
        tutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)

        let homePageConfiguration = HomePageConfiguration(remoteMessagingStore: MockRemoteMessagingStore(), subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { true }, promptExposureReporter: MockPromptExposureReporter())
        hvc = NewTabPageViewController(
            isFocussedState: false,
            dismissKeyboardOnScroll: false,
            tab: Tab(),
            interactionModel: MockFavoritesListInteracting(),
            homePageMessagesConfiguration: homePageConfiguration,
            newTabDialogFactory: dialogFactory,
            daxDialogsManager: specProvider,
            onboardingFlowProvider: flowProvider,
            faviconLoader: EmptyFaviconLoading(),
            remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
            remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
            appSettings: AppSettingsMock(),
            faviconsCache: Favicons(),
            subscriptionManager: SubscriptionManagerMock(),
            internalUserCommands: MockURLBasedDebugCommands(),
            tutorialSettings: tutorialSettings,
        )

        let window = UIWindow(frame: UIScreen.main.bounds)
        testWindow = window
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.present(hvc, animated: false, completion: nil)

        let viewLoadedExpectation = expectation(description: "View is loaded")
        DispatchQueue.main.async {
            XCTAssertNotNil(self.hvc.view, "The view should be loaded")
            viewLoadedExpectation.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
        specProvider.nextHomeScreenMessageCalled = false
        specProvider.nextHomeScreenMessageNewCalled = false
    }

    override func tearDownWithError() throws {
        testWindow?.rootViewController?.dismiss(animated: false)
        testWindow?.isHidden = true
        testWindow = nil
        variantManager = nil
        dialogFactory = nil
        specProvider = nil
        flowProvider = nil
        tutorialSettings = nil
        hvc = nil
    }

    func testWhenFocusedContentIsConfiguredBeforeLoadingThenHostedPageIsTransparent() throws {
        let (configuration, _) = makeConfiguration(withScheduledMessage: false)
        let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: configuration)
        XCTAssertFalse(controller.isViewLoaded)

        controller.setFocusedContent(LegacyFocusedNewTabPageContent(isAddressBarAtBottom: false))
        XCTAssertFalse(controller.isViewLoaded)
        controller.loadViewIfNeeded()

        let page = try XCTUnwrap(controller.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(page.parent === controller)
        XCTAssertTrue(page.view.superview === controller.view)
        XCTAssertEqual(controller.view.backgroundColor, .clear)
        XCTAssertEqual(page.view.backgroundColor, .clear)
    }

    func testWhenLoadedPageChangesFocusedContentThenItRetainsHostAndRestoresBackground() throws {
        let restingBackground = try XCTUnwrap(hvc.view.backgroundColor)
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)

        hvc.setFocusedContent(LegacyFocusedNewTabPageContent(isAddressBarAtBottom: true))
        XCTAssertEqual(hvc.view.backgroundColor, .clear)
        XCTAssertEqual(page.view.backgroundColor, .clear)

        hvc.setFocusedContent(nil)
        let restoredBackground = try XCTUnwrap(hvc.view.backgroundColor)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(restoredBackground.resolvedColor(with: traits), restingBackground.resolvedColor(with: traits))
        }
        XCTAssertEqual(page.view.backgroundColor, .clear)
        XCTAssertEqual(hvc.children.count, 1)
        XCTAssertTrue(hvc.children.first === page)
    }

    func testWhenPageResizesThenHostedContentFillsContainerAndInheritsSafeArea() throws {
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        XCTAssertTrue(page.parent === hvc)
        XCTAssertTrue(page.view.superview === hvc.view)

        hvc.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 16, right: 0)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            hvc.view.frame = CGRect(origin: .zero, size: size)
            hvc.view.setNeedsLayout()
            hvc.view.layoutIfNeeded()

            XCTAssertEqual(page.view.frame, hvc.view.bounds)
            XCTAssertEqual(page.view.safeAreaInsets, hvc.view.safeAreaInsets)
            XCTAssertFalse(page.view.hasAmbiguousLayout)
        }
    }

    func testWhenLegacyFocusedTopClearanceShrinksThenScrollableContentTracksItOnce() throws {
        try assertFocusedContentTracksTopClearance(usesRedesign: false)
    }

    func testWhenRedesignedFocusedTopClearanceShrinksThenScrollableContentTracksItOnce() throws {
        try assertFocusedContentTracksTopClearance(usesRedesign: true)
    }

    func testWhenLegacyFocusedContentIsScrolledThenDismissalReturnsToAlignedTop() throws {
        try assertFocusedContentTracksTopClearance(usesRedesign: false, resetsScrolledContent: true)
    }

    func testWhenLegacyFocusedContentIsScrolledThenResetReturnsToAlignedTopBeforeClearanceChanges() throws {
        try assertFocusedContentTracksTopClearance(usesRedesign: false, resetsScrolledContent: true, resetsBeforeClearanceChanges: true)
    }

    func testWhenTypingTopClearanceShrinksThenNativeListTracksItInBothFlagStates() throws {
        for usesScrollableEscapeHatch in [false, true] {
            try assertTypingListTracksTopClearance(usesScrollableEscapeHatch: usesScrollableEscapeHatch)
        }
    }

    private func assertFocusedContentTracksTopClearance(
        usesRedesign: Bool,
        resetsScrolledContent: Bool = false,
        resetsBeforeClearanceChanges: Bool = false
    ) throws {
        let (configuration, _) = makeConfiguration(withScheduledMessage: false)
        let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: configuration)
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .aiChat, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: true, resultsPending: false))
        let host = UnifiedSuggestionsHost(config: UnifiedSuggestionsHostConfig(
            source: EmptySuggestionsSource(),
            inputsPublisher: inputs.eraseToAnyPublisher(),
            isAddressBarAtBottom: false,
            favoritesProvider: { controller },
            onSelectRow: { _ in },
            onDeleteRow: { _ in },
            onTapAheadRow: { _ in }), usesScrollableEscapeHatch: true)
        var probeFrame: CGRect?
        var probeRevision = 0
        let probe = AnyView(Color.clear.frame(height: 1_200)
            .onFrameUpdate(in: .global, using: FocusedScrollProbeFrameKey.self) { frame in
                probeFrame = frame
                probeRevision += 1
            })
        host.setUsesRedesignedNewTabPageLayout(usesRedesign)
        host.setFocusedContent(mode: .aiChat, escapeHatch: nil, syncPromo: probe)

        let parent = UIViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        window.rootViewController = parent
        window.makeKeyAndVisible()
        host.start(in: parent.view, parentViewController: parent, isFloatingUIEnabled: true, textPublisher: Just(""))
        defer {
            host.tearDown()
            window.isHidden = true
            window.rootViewController = nil
            testWindow?.makeKeyAndVisible()
        }
        host.setContentInsets(UIEdgeInsets(top: 184, left: 0, bottom: 0, right: 0))
        let mounted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            parent.view.layoutIfNeeded()
            return probeFrame?.height == 1_200 && self.outerContentScrollView(in: parent.view) != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [mounted], timeout: 5), .completed)
        let scrollView = try XCTUnwrap(outerContentScrollView(in: parent.view))
        print("[EHScrollTest] mounted scene=\(scene.activationState.rawValue) parentWindow=\(parent.view.window === window) controllerWindow=\(controller.viewIfLoaded?.window === window)")
        XCTAssertTrue(parent.view.window === window)
        if !usesRedesign { XCTAssertTrue(controller.view.window === window) }
        let initialFrame = try XCTUnwrap(probeFrame)
        let initialViewport = scrollView.convert(scrollView.bounds, to: window)
        let initialNativeTopInset = scrollView.adjustedContentInset.top
        XCTAssertEqual(initialViewport.minY, 0, accuracy: 1)
        XCTAssertEqual(initialNativeTopInset, parent.view.safeAreaInsets.top, accuracy: 1)

        for topInset in [CGFloat(177), 131, 60] {
            if resetsScrolledContent && topInset == 60 {
                scrollView.contentOffset.y = 250
                let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    parent.view.layoutIfNeeded()
                    return (probeFrame?.maxY ?? 0) > 0 && (probeFrame?.minY ?? 0) < 0
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed)
                XCTAssertTrue(outerContentScrollView(in: controller.view) === scrollView)
                XCTAssertTrue(controller.isViewLoaded)
                print("[EHScrollTest] reset.begin offset=\(scrollView.contentOffset) inset=\(scrollView.adjustedContentInset) content=\(scrollView.contentSize) probe=\(String(describing: probeFrame))")
                host.scrollLegacyContentToTop(duration: 0.2)
                if resetsBeforeClearanceChanges {
                    let alignedTop = NSPredicate { _, _ in
                        parent.view.layoutIfNeeded()
                        return abs(scrollView.contentOffset.y + scrollView.adjustedContentInset.top) <= 1
                            && abs((probeFrame?.minY ?? .infinity) - initialFrame.minY - 131 + 184) <= 1
                    }
                    let reset = XCTNSPredicateExpectation(predicate: alignedTop, object: nil)
                    let animatedResult = XCTWaiter.wait(for: [reset], timeout: 5)
                    XCTAssertEqual(animatedResult, .completed)
                    print("[EHScrollTest] reset.fixedClearance animated=\(animatedResult) offset=\(scrollView.contentOffset) probe=\(String(describing: probeFrame))")
                    if animatedResult != .completed {
                        controller.scrollToTop(duration: 0.2)
                        let controllerReset = XCTNSPredicateExpectation(predicate: alignedTop, object: nil)
                        let controllerResult = XCTWaiter.wait(for: [controllerReset], timeout: 5)
                        XCTAssertEqual(controllerResult, .completed)
                        print("[EHScrollTest] reset.fixedClearance directController=\(controllerResult) offset=\(scrollView.contentOffset) loaded=\(controller.isViewLoaded)")
                        host.scrollLegacyContentToTop(duration: 0)
                        let immediateReset = XCTNSPredicateExpectation(predicate: alignedTop, object: nil)
                        let immediateResult = XCTWaiter.wait(for: [immediateReset], timeout: 5)
                        XCTAssertEqual(immediateResult, .completed)
                        print("[EHScrollTest] reset.fixedClearance immediate=\(immediateResult) offset=\(scrollView.contentOffset) probe=\(String(describing: probeFrame))")
                        if immediateResult != .completed {
                            scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
                            let nativeReset = XCTNSPredicateExpectation(predicate: alignedTop, object: nil)
                            let nativeResult = XCTWaiter.wait(for: [nativeReset], timeout: 5)
                            XCTAssertEqual(nativeResult, .completed)
                            print("[EHScrollTest] reset.fixedClearance directNative=\(nativeResult) offset=\(scrollView.contentOffset) probe=\(String(describing: probeFrame))")
                        }
                    }
                }
            }
            let revision = probeRevision
            let animated = expectation(description: "Focused top clearance animation completes")
            let animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
                host.setContentInsets(UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0))
                parent.view.layoutIfNeeded()
            }
            animator.addCompletion { _ in animated.fulfill() }
            animator.startAnimation()
            wait(for: [animated], timeout: 5)
            let expectedOrigin = initialFrame.minY + topInset - 184
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                parent.view.layoutIfNeeded()
                return probeRevision > revision && abs((probeFrame?.minY ?? .infinity) - expectedOrigin) <= 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)

            let frame = try XCTUnwrap(probeFrame)
            if resetsScrolledContent && topInset == 60 {
                print("[EHScrollTest] reset.end offset=\(scrollView.contentOffset) inset=\(scrollView.adjustedContentInset) content=\(scrollView.contentSize) probe=\(frame)")
            }
            XCTAssertEqual(frame.minY, initialFrame.minY + topInset - 184, accuracy: 1,
                           "The scrolling content must follow the input clearance exactly once")
            XCTAssertTrue(outerContentScrollView(in: parent.view) === scrollView)
            XCTAssertEqual(scrollView.convert(scrollView.bounds, to: window).minY, initialViewport.minY, accuracy: 1)
            XCTAssertEqual(scrollView.adjustedContentInset.top, initialNativeTopInset, accuracy: 1,
                           "Input clearance belongs to the scrolling content, not the native safe area")
        }
    }

    private func outerContentScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, !(scrollView is UICollectionView), !(scrollView is UITableView) { return scrollView }
        return view.subviews.lazy.compactMap { self.outerContentScrollView(in: $0) }.first
    }

    private func assertTypingListTracksTopClearance(usesScrollableEscapeHatch: Bool) throws {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let host = UnifiedSuggestionsHost(config: UnifiedSuggestionsHostConfig(
            source: FocusedGeometrySuggestionsSource(),
            inputsPublisher: inputs.eraseToAnyPublisher(),
            isAddressBarAtBottom: false,
            favoritesProvider: { nil },
            onSelectRow: { _ in },
            onDeleteRow: { _ in },
            onTapAheadRow: { _ in }), usesScrollableEscapeHatch: usesScrollableEscapeHatch)
        host.setFocusedContent(mode: .search, escapeHatch: nil, syncPromo: nil)
        let parent = UIViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        window.rootViewController = parent
        window.makeKeyAndVisible()
        host.start(in: parent.view, parentViewController: parent, isFloatingUIEnabled: true, textPublisher: Just("a"))
        defer {
            host.tearDown()
            window.isHidden = true
            window.rootViewController = nil
            testWindow?.makeKeyAndVisible()
        }

        func nativeList(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView, scrollView is UICollectionView || scrollView is UITableView { return scrollView }
            return view.subviews.lazy.compactMap { nativeList(in: $0) }.first
        }
        func visibleCell(in list: UIScrollView) -> UIView? {
            if let list = list as? UICollectionView { return list.visibleCells.first }
            return (list as? UITableView)?.visibleCells.first
        }
        let hostingController = try XCTUnwrap(parent.children.compactMap { $0 as? UIHostingController<UnifiedSuggestionsView> }.first)
        print("[EHScrollTest] typing.mounted scene=\(scene.activationState.rawValue) parentWindow=\(parent.view.window === window) controllerWindow=\(hostingController.view.window === window)")
        XCTAssertTrue(parent.view.window === window)
        XCTAssertTrue(hostingController.view.window === window)
        host.setContentInsets(UIEdgeInsets(top: 184, left: 0, bottom: 0, right: 0))
        let mounted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            parent.view.layoutIfNeeded()
            guard let list = nativeList(in: parent.view), visibleCell(in: list) != nil else { return false }
            return abs(list.convert(CGPoint.zero, to: window).y - parent.view.safeAreaInsets.top - 184) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [mounted], timeout: 5), .completed)
        let list = try XCTUnwrap(nativeList(in: parent.view))
        let initialOrigin = list.convert(CGPoint.zero, to: window).y
        let initialCell = try XCTUnwrap(visibleCell(in: list))
        let initialCellOrigin = initialCell.convert(initialCell.bounds, to: window).minY
        let initialViewportOrigin = list.convert(list.bounds, to: window).minY
        XCTAssertEqual(hostingController.rootView.viewModel.contentTopInset, usesScrollableEscapeHatch ? 184 : 0)

        for topInset in [CGFloat(177), 131, 60] {
            let animated = expectation(description: "Typing list clearance animation completes")
            let animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
                host.setContentInsets(UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0))
                parent.view.layoutIfNeeded()
            }
            animator.addCompletion { _ in animated.fulfill() }
            animator.startAnimation()
            wait(for: [animated], timeout: 5)
            let expectedOrigin = initialOrigin + topInset - 184
            let expectedCellOrigin = initialCellOrigin + topInset - 184
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                parent.view.layoutIfNeeded()
                guard let cell = visibleCell(in: list) else { return false }
                return abs(list.convert(CGPoint.zero, to: window).y - expectedOrigin) <= 1
                    && abs(cell.convert(cell.bounds, to: window).minY - expectedCellOrigin) <= 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
            print("[EHScrollTest] typing scrolling=\(usesScrollableEscapeHatch) top=\(topInset) origin=\(list.convert(CGPoint.zero, to: window).y) offset=\(list.contentOffset) inset=\(list.adjustedContentInset) parentSafe=\(parent.view.safeAreaInsets)")
            print("[EHScrollTest] typing modelTop=\(hostingController.rootView.viewModel.contentTopInset) viewport=\(list.convert(list.bounds, to: window)) cell=\(String(describing: visibleCell(in: list).map { $0.convert($0.bounds, to: window) }))")
            XCTAssertEqual(hostingController.rootView.viewModel.contentTopInset, usesScrollableEscapeHatch ? topInset : 0)
            XCTAssertEqual(list.convert(CGPoint.zero, to: window).y, expectedOrigin, accuracy: 1)
            let cell = try XCTUnwrap(visibleCell(in: list))
            XCTAssertEqual(cell.convert(cell.bounds, to: window).minY, expectedCellOrigin, accuracy: 1)
            XCTAssertEqual(list.convert(list.bounds, to: window).minY, initialViewportOrigin, accuracy: 1)
            XCTAssertTrue(nativeList(in: parent.view) === list)
        }
    }

    func testLegacyFocusedHatchScrollsOnlyWithOtherContent() throws {
        try assertFocusedHatchContentPolicy(usesRedesign: false)
    }

    func testRedesignedFocusedHatchScrollsOnlyWithOtherContent() throws {
        try assertFocusedHatchContentPolicy(usesRedesign: true)
    }

    private func assertFocusedHatchContentPolicy(usesRedesign: Bool) throws {
        let configuration = HomePageMessagesConfigurationMock(homeMessages: [])
        let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: configuration, usesContentDependentScrolling: true)
        let source = MutableHatchRowsSource()
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .aiChat, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let host = UnifiedSuggestionsHost(config: UnifiedSuggestionsHostConfig(
            source: EmptySuggestionsSource(), inputsPublisher: inputs.eraseToAnyPublisher(), isAddressBarAtBottom: false,
            favoritesProvider: { controller }, onSelectRow: { _ in }, onDeleteRow: { _ in }, onTapAheadRow: { _ in }),
            usesScrollableEscapeHatch: true)
        let hatch = makeScrollingHatch()
        host.setUsesRedesignedNewTabPageLayout(usesRedesign)
        host.attachDuckAISurface(.init(source: source, onSelectRow: { _ in }, onDeleteRow: { _ in },
                                      onTapAheadRow: { _ in }, onFireDeleteRow: { _ in }), textPublisher: Just("").eraseToAnyPublisher())
        host.setFocusedContent(mode: .aiChat, escapeHatch: hatch, syncPromo: AnyView(Color.clear.frame(height: 1_200)))
        let parent = UIViewController()
        let window = try mountScrollingPage(parent)
        host.start(in: parent.view, parentViewController: parent, textPublisher: Just(""))
        defer { host.tearDown(); window.isHidden = true; window.rootViewController = nil; testWindow?.makeKeyAndVisible() }
        let mounted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let scrollView = self.outerContentScrollView(in: parent.view) else { return false }
            return scrollView.bounds.height > 0 && scrollView.contentSize.height > scrollView.bounds.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [mounted], timeout: 5), .completed)
        let scrollView = try XCTUnwrap(outerContentScrollView(in: parent.view))
        assertScrollingPermission(false, scrollView: scrollView)
        XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height, "A promo alone must not enable even overflowing content")
        source.sections.send([SuggestionSection(id: "recent", rows: [
            SuggestionRow(id: "chat", icon: .aiChat, title: "Chat", accessory: .fire, accessibilityID: "chat")
        ])])
        assertScrollingPermission(true, scrollView: scrollView)
        scrollView.contentOffset.y = 100
        source.sections.send([])
        assertScrollingPermission(false, scrollView: scrollView)
        XCTAssertEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top, accuracy: 1)

        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        host.setFocusedContent(mode: .search, escapeHatch: hatch, syncPromo: nil)
        configuration.homeMessages = [.placeholder]
        controller.messagesModel.refresh()
        assertScrollingPermission(false, scrollView: scrollView)
        configuration.homeMessages = [scrollingRemoteMessage()]
        controller.messagesModel.refresh()
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: true, hasRecents: false, resultsPending: false))
        assertScrollingPermission(true, scrollView: scrollView)
        configuration.homeMessages = [.placeholder]
        controller.messagesModel.refresh()
        assertScrollingPermission(false, scrollView: scrollView)
        configuration.homeMessages = [scrollingRemoteMessage()]
        controller.messagesModel.refresh()
        assertScrollingPermission(true, scrollView: scrollView)
        configuration.homeMessages = []
        controller.messagesModel.refresh()
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        assertScrollingPermission(false, scrollView: scrollView)
    }

    func testRestingLegacyHatchPolicyPreservesFlagOffAndRespondsToMessages() throws {
        for isEnabled in [false, true] {
            let configuration = HomePageMessagesConfigurationMock(homeMessages: [])
            let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: configuration,
                                            usesContentDependentScrolling: isEnabled, isFocussedState: false)
            controller.setEscapeHatch(makeScrollingHatch())
            let window = try mountScrollingPage(controller)
            defer { window.isHidden = true; window.rootViewController = nil; testWindow?.makeKeyAndVisible() }
            let scrollView = try XCTUnwrap(outerContentScrollView(in: controller.view))
            if !isEnabled { XCTAssertTrue(scrollView.isScrollEnabled); continue }
            assertScrollingPermission(false, scrollView: scrollView)
            configuration.homeMessages = [scrollingRemoteMessage()]
            controller.messagesModel.refresh()
            assertScrollingPermission(true, scrollView: scrollView)
            configuration.homeMessages = []
            controller.messagesModel.refresh()
            assertScrollingPermission(false, scrollView: scrollView)
            controller.setEscapeHatch(nil)
            XCTAssertTrue(scrollView.isScrollEnabled)
        }
    }

    func testRestingRedesignedHatchPolicyTracksFavoritesVisibilityAndEditing() throws {
        var customization = NewTabPageCustomizationStore()
        let wasVisible = customization.isFavoritesSectionVisible
        customization.isFavoritesSectionVisible = true
        defer { customization.isFavoritesSectionVisible = wasVisible }
        let source = MutableHatchFavoritesSource()
        let favorites = FavoritesViewModel(isFocussedState: false, favoriteDataSource: source,
                                           faviconLoader: EmptyFaviconLoading(), faviconsCache: Favicons())
        let model = NewTabPageViewModel(fireTab: false)
        let page = RedesignedNewTabPageViewController(blocks: [], favoritesModel: favorites, pageModel: model,
                                                      usesContentDependentEscapeHatchScrolling: true)
        let window = try mountScrollingPage(page)
        defer { window.isHidden = true; window.rootViewController = nil; testWindow?.makeKeyAndVisible() }
        let scrollView = try XCTUnwrap(outerContentScrollView(in: page.view))
        XCTAssertTrue(scrollView.isScrollEnabled, "Without a hatch, other redesign modules retain their existing scrolling")
        page.setEscapeHatch(makeScrollingHatch())
        assertScrollingPermission(false, scrollView: scrollView)
        source.favorites = [Favorite(id: "one", title: "One", domain: "example.com")]
        source.updates.send(())
        assertScrollingPermission(true, scrollView: scrollView)
        customization.isFavoritesSectionVisible = false
        assertScrollingPermission(false, scrollView: scrollView)
        customization.isFavoritesSectionVisible = true
        assertScrollingPermission(true, scrollView: scrollView)
        page.setSearchInputEditing(true)
        XCTAssertFalse(scrollView.isScrollEnabled)
        source.favorites = []
        source.updates.send(())
        assertScrollingPermission(false, scrollView: scrollView)
        page.setSearchInputEditing(false)
        assertScrollingPermission(false, scrollView: scrollView)
        XCTAssertEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top, accuracy: 1)
        page.setEscapeHatch(nil)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in scrollView.isScrollEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }

    func testRestingRedesignedEmptyHatchResetsSavedOffsetAfterDetachment() throws {
        var customization = NewTabPageCustomizationStore()
        let wasVisible = customization.isFavoritesSectionVisible
        customization.isFavoritesSectionVisible = true
        defer { customization.isFavoritesSectionVisible = wasVisible }
        let source = MutableHatchFavoritesSource()
        source.favorites = [Favorite(id: "one", title: "One", domain: "example.com")]
        let favorites = FavoritesViewModel(isFocussedState: false, favoriteDataSource: source,
                                           faviconLoader: EmptyFaviconLoading(), faviconsCache: Favicons())
        let model = NewTabPageViewModel(fireTab: false)
        let page = RedesignedNewTabPageViewController(
            blocks: [NewTabPageSwiftUIBlock(id: .welcome, rootView: Color.clear.frame(height: 2_000))],
            favoritesModel: favorites, pageModel: model, usesContentDependentEscapeHatchScrolling: true)
        page.setEscapeHatch(makeScrollingHatch())
        let window = try mountScrollingPage(page)
        defer { window.isHidden = true; window.rootViewController = nil; testWindow?.makeKeyAndVisible() }
        let scrollView = try XCTUnwrap(outerContentScrollView(in: page.view))
        assertScrollingPermission(true, scrollView: scrollView)
        let overflowing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom > 200
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [overflowing], timeout: 5), .completed)
        scrollView.contentOffset.y = 200
        XCTAssertEqual(scrollView.contentOffset.y, 200, accuracy: 1)
        page.dismiss()
        source.favorites = []
        source.updates.send(())
        assertScrollingPermission(false, scrollView: scrollView)
        XCTAssertGreaterThan(scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom, 200)
        page.viewDidAppear(false)
        XCTAssertFalse(scrollView.isScrollEnabled)
        XCTAssertEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top, accuracy: 1)
    }

    func testRestingRedesignedFlagOffKeepsScrollingWithOnlyHatch() throws {
        let model = NewTabPageViewModel(fireTab: false)
        let page = RedesignedNewTabPageViewController(blocks: [], pageModel: model, usesContentDependentEscapeHatchScrolling: false)
        page.setEscapeHatch(makeScrollingHatch())
        let window = try mountScrollingPage(page)
        defer { window.isHidden = true; window.rootViewController = nil; testWindow?.makeKeyAndVisible() }
        let scrollView = try XCTUnwrap(outerContentScrollView(in: page.view))
        assertScrollingPermission(true, scrollView: scrollView)
    }

    private func assertScrollingPermission(_ allowed: Bool, scrollView: UIScrollView, file: StaticString = #filePath, line: UInt = #line) {
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            scrollView.isScrollEnabled == allowed && scrollView.alwaysBounceVertical == allowed
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed, file: file, line: line)
    }

    private func mountScrollingPage(_ controller: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return window
    }

    private func scrollingRemoteMessage() -> HomeMessage {
        .remoteMessage(remoteMessage: .init(id: "scrolling", surfaces: .newTabPage,
                                           content: .small(titleText: "Title", descriptionText: "Message"),
                                           matchingRules: [], exclusionRules: [], isMetricsEnabled: false))
    }

    private func makeScrollingHatch() -> EscapeHatchModel {
        let tab = Tab()
        return EscapeHatchModel(title: "Return", subtitle: "Tab", tabType: .regular, domain: nil, targetTab: tab,
                                tabsSource: HatchTabsSource(tab: tab),
                                afterInactivityOptionAdapter: AfterInactivityOptionAdapter(initialOption: .lastUsedTab, keyValueStore: MockKeyValueFileStore()),
                                lastTabShortcutAdapter: LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore()),
                                onCardTap: {}, onTabSwitcherTap: {}, onCloseTab: {}, onBurnTabWithConfirmation: { _ in }, onBurnTabImmediately: {})
    }

    func testWhenDialogIsReplacedThenItRemainsAboveHostedPageInContainer() throws {
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        specProvider.specToReturn = .initial
        hvc.showNextDaxDialog()
        let firstDialog = try XCTUnwrap(hvc.children.first { $0 !== page })

        hvc.showNextDaxDialog()
        let replacement = try XCTUnwrap(hvc.children.first { $0 !== page })
        hvc.view.layoutIfNeeded()

        XCTAssertNil(firstDialog.parent)
        XCTAssertNil(firstDialog.view.superview)
        XCTAssertEqual(hvc.children.count, 2)
        XCTAssertTrue(replacement.view.superview === page.view.superview)
        let pageIndex = try XCTUnwrap(hvc.view.subviews.firstIndex(of: page.view))
        let dialogIndex = try XCTUnwrap(hvc.view.subviews.firstIndex(of: replacement.view))
        XCTAssertGreaterThan(dialogIndex, pageIndex)
        XCTAssertEqual(replacement.view.frame, hvc.view.bounds)
        XCTAssertFalse(replacement.view.hasAmbiguousLayout)
    }

    func testWhenDialogIsDismissedThenHostedPageRemainsAttached() throws {
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        specProvider.specToReturn = .initial
        hvc.showNextDaxDialog()
        let dialog = try XCTUnwrap(hvc.children.first { $0 !== page })

        specProvider.specToReturn = nil
        let dismiss = try XCTUnwrap(dialogFactory.onDismiss)
        dismiss(false)

        XCTAssertNil(dialog.parent)
        XCTAssertNil(dialog.view.superview)
        XCTAssertEqual(hvc.children.count, 1)
        XCTAssertTrue(page.parent === hvc)
        XCTAssertTrue(page.view.superview === hvc.view)
    }

    // MARK: - After-idle remote message signal

    /// Builds an NTP the way the focused UTI embedded surface does: a shared messages config and the
    /// after-idle signal passed in (the embedded surface suppresses its own escape hatch, so the
    /// signal can't be derived from it).
    private func makeNewTabPage(openedAfterIdle: Bool,
                                homePageMessagesConfiguration: HomePageMessagesConfiguration,
                                usesContentDependentScrolling: Bool = false,
                                isFocussedState: Bool = true) -> NewTabPageViewController {
        NewTabPageViewController(
            isFocussedState: isFocussedState,
            openedAfterIdle: openedAfterIdle,
            dismissKeyboardOnScroll: false,
            tab: Tab(),
            interactionModel: MockFavoritesListInteracting(),
            homePageMessagesConfiguration: homePageMessagesConfiguration,
            newTabDialogFactory: dialogFactory,
            daxDialogsManager: specProvider,
            onboardingFlowProvider: flowProvider,
            faviconLoader: EmptyFaviconLoading(),
            remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
            remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
            appSettings: AppSettingsMock(),
            faviconsCache: Favicons(),
            subscriptionManager: SubscriptionManagerMock(),
            internalUserCommands: MockURLBasedDebugCommands(),
            tutorialSettings: tutorialSettings,
            usesContentDependentEscapeHatchScrolling: usesContentDependentScrolling)
    }

    private func makeConfiguration(withScheduledMessage: Bool) -> (HomePageConfiguration, MockRemoteMessagingStore) {
        let store = MockRemoteMessagingStore()
        if withScheduledMessage {
            store.scheduledRemoteMessage = RemoteMessageModel(
                id: "idle-msg", surfaces: .newTabPage, content: nil, matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        }
        let config = HomePageConfiguration(remoteMessagingStore: store,
                                           subscriptionDataReporter: MockSubscriptionDataReporter(),
                                           isStillOnboarding: { false }, promptExposureReporter: MockPromptExposureReporter())
        return (config, store)
    }

    func testWhenOpenedAfterIdleTrueThenMessagesConfigFetchesWithAfterIdleTrigger() {
        // GIVEN a shared config with a scheduled after-idle message
        let (config, store) = makeConfiguration(withScheduledMessage: true)

        // WHEN an embedded (hatch-suppressed) NTP is built seeded with the after-idle signal
        _ = makeNewTabPage(openedAfterIdle: true, homePageMessagesConfiguration: config)

        // THEN its first refresh fetches the after-idle message (not .noTrigger) and keeps it in the
        // shared config the focused-content gate reads
        XCTAssertEqual(store.capturedTriggerFilter, .specific(.afterIdle))
        XCTAssertFalse(config.homeMessages.isEmpty)
    }

    func testWhenOpenedAfterIdleFalseThenMessagesConfigFetchesWithNoTrigger() {
        // GIVEN
        let (config, store) = makeConfiguration(withScheduledMessage: true)

        // WHEN a non-after-idle NTP is built
        _ = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: config)

        // THEN it fetches the standard (.noTrigger) message, not the after-idle one
        XCTAssertEqual(store.capturedTriggerFilter, .noTrigger)
    }

    func testWhenSetOpenedAfterIdleTrueThenMessagesConfigRefetchesWithAfterIdleTrigger() {
        // GIVEN a cached NTP originally built without the after-idle signal
        let (config, store) = makeConfiguration(withScheduledMessage: true)
        let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: config)
        store.capturedTriggerFilter = nil

        // WHEN a later after-idle session pushes the signal into the cached controller
        controller.setOpenedAfterIdle(true)

        // THEN it re-fetches with the after-idle trigger
        XCTAssertEqual(store.capturedTriggerFilter, .specific(.afterIdle))
    }

    func testWhenViewDidAppearWithInitialSpecThenDaxDialogIsCreated() throws {
        // GIVEN
        let expectedSpec = DaxDialogs.HomeScreenSpec.initial
        specProvider.specToReturn = expectedSpec

        // WHEN
        hvc.viewDidAppear(false)

        // THEN
        XCTAssertFalse(self.specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(self.specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(self.dialogFactory.homeDialog, expectedSpec)
        XCTAssertNotNil(self.dialogFactory.onDismiss)
        XCTAssertNil(self.dialogFactory.endOfJourneyContent)
    }

    func testWhenOnboardingCompletesWithInitialSpecThenDaxDialogIsCreated() throws {
        // GIVEN
        let expectedSpec = DaxDialogs.HomeScreenSpec.initial
        specProvider.specToReturn = expectedSpec

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        XCTAssertFalse(self.specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(self.specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(self.dialogFactory.homeDialog, expectedSpec)
        XCTAssertNotNil(self.dialogFactory.onDismiss)
        XCTAssertNil(self.dialogFactory.endOfJourneyContent)
    }

    func testWhenOnboardingCompletesWithFinalSpecThenEndOfJourneyDialogIsCreated() throws {
        // GIVEN
        specProvider.specToReturn = .final

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        XCTAssertFalse(specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertNil(dialogFactory.homeDialog)
        XCTAssertNil(dialogFactory.onDismiss)
        XCTAssertNotNil(dialogFactory.endOfJourneyContent)
        XCTAssertNotNil(dialogFactory.onEndOfJourneyAction)
    }

    func testWhenShowNextDaxDialog_AndShouldShowDaxDialogs_ThenReturnTrue() {
        // WHEN
        hvc.showNextDaxDialog()

        // THEN
        XCTAssertTrue(specProvider.nextHomeScreenMessageNewCalled)
    }

    // MARK: - Duck.ai tailored flow router branches

    func testWhenDuckAITailoredFlow_AndOnboardingCompleted_AndNotSkipped_ThenDoesNotPeekRegularSpec() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        tutorialSettings.hasSkippedOnboarding = false

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        // Tailored completion routes to `showDuckAIOnboardingCompletionWithActiveAddressBar`, not
        // through the regular Dax sequence — confirms the tailored branch is taken, not default.
        XCTAssertFalse(specProvider.nextHomeScreenMessageNewCalled)
    }

    func testWhenDuckAITailoredFlow_AndOnboardingCompleted_AndSkipped_ThenDoesNotPeekRegularSpec() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        tutorialSettings.hasSkippedOnboarding = true

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        // Skip branch only calls `omniBar.beginEditing` for AI chat; no Dax dialog should be peeked.
        XCTAssertFalse(specProvider.nextHomeScreenMessageNewCalled)
    }

    func testWhenDuckAITailoredFlow_AndDialogRequested_AndSubscriptionPromoPending_ThenPeeksSpecToRenderPromo() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        specProvider.subscriptionPromotionPending = true

        // WHEN
        hvc.showNextDaxDialog()

        // THEN
        // Tailored router only proceeds to showNextDaxDialogNew (which peeks the spec) when the
        // subscription promo is pending — confirming the gate is read and the promo path is taken.
        XCTAssertTrue(specProvider.nextHomeScreenMessageNewCalled)
    }

    func testWhenDuckAITailoredFlow_AndDialogRequested_AndSubscriptionPromoNotPending_ThenDoesNotPeekSpec() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        specProvider.subscriptionPromotionPending = false

        // WHEN
        hvc.showNextDaxDialog()

        // THEN
        // Tailored router must NOT enter the regular Dax sequence when there is no promo — otherwise
        // a stray `.initial`/`.subsequent` dialog could leak into the Duck.ai onboarding completion UX.
        XCTAssertFalse(specProvider.nextHomeScreenMessageNewCalled)
    }
}

@MainActor
private final class FocusedGeometrySuggestionsSource: SuggestionsSource {
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> {
        Just([SuggestionSection(id: "geometry", rows: [SuggestionRowMapper.searchRow(query: "geometry", idPrefix: "geometry")])])
            .eraseToAnyPublisher()
    }

    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}

private struct FocusedScrollProbeFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

class CapturingVariantManager: VariantManager {
    var currentVariant: Variant?
    var capturedFeatureName: FeatureName?
    var supportedFeatures: [FeatureName] = []

    func assignVariantIfNeeded(_ newInstallCompletion: (BrowserServicesKit.VariantManager) -> Void) {
    }

    func isSupported(feature: FeatureName) -> Bool {
        capturedFeatureName = feature
        return supportedFeatures.contains(feature)
    }
}

class CapturingNewTabDaxDialogProvider: NewTabDaxDialogProviding {
    var homeDialog: DaxDialogs.HomeScreenSpec?
    var onDismiss: ((_ activateSearch: Bool) -> Void)?
    var endOfJourneyContent: OnboardingEndOfJourneyContent?
    var onEndOfJourneyAction: ((OnboardingEndOfJourneyAction) -> Void)?

    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        self.homeDialog = homeDialog
        self.onDismiss = onCompletion
        return EmptyView()
    }

    func createDuckAIFireOnboardingCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func createEndOfJourneyDialog(content: OnboardingEndOfJourneyContent, onAction: @escaping (OnboardingEndOfJourneyAction) -> Void) -> AnyView {
        endOfJourneyContent = content
        onEndOfJourneyAction = onAction
        return AnyView(EmptyView())
    }
}

final class MockOnboardingFlowProvider: OnboardingFlowProviding {
    var currentOnboardingFlow: OnboardingFlowType = .default
}

struct MockVariant: Variant {
    var name: String = ""
    var weight: Int = 0
    var isIncluded: () -> Bool = { false }
    var features: [BrowserServicesKit.FeatureName] = []

    init(features: [BrowserServicesKit.FeatureName]) {
        self.features = features
    }
}

private struct HatchTabsSource: EscapeHatchTabsSource {
    let tab: DuckDuckGo.Tab
    func tabsPublisher(for mode: BrowsingMode) -> AnyPublisher<[DuckDuckGo.Tab], Never> { Just([tab]).eraseToAnyPublisher() }
}

@MainActor
private final class MutableHatchRowsSource: SuggestionsSource {
    let sections = CurrentValueSubject<[SuggestionSection], Never>([])
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> { sections.eraseToAnyPublisher() }
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}

private final class MutableHatchFavoritesSource: NewTabPageFavoriteDataSource {
    var favorites: [Favorite] = []
    let updates = PassthroughSubject<Void, Never>()
    var externalUpdates: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }
    func moveFavorite(_ favorite: Favorite, fromIndex: Int, toIndex: Int) {}
    func bookmarkEntity(for favorite: Favorite) -> BookmarkEntity? { nil }
    func favorite(at index: Int) throws -> Favorite? { favorites.indices.contains(index) ? favorites[index] : nil }
    func removeFavorite(_ favorite: Favorite) {}
}
