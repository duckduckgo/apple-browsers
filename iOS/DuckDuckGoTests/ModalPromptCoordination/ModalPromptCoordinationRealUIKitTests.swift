//
//  ModalPromptCoordinationRealUIKitTests.swift
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
import Combine
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Real UIKit", .serialized)
final class ModalPromptCoordinationRealUIKitTests {
    private let cooldownManagerMock: MockPromptCooldownManager
    private let schedulerMock: MockModalPromptScheduler
    private let presenterMock: MockModalPromptPresenter
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: ModalPromptCoordinationManager!

    init() {
        cooldownManagerMock = MockPromptCooldownManager()
        schedulerMock = MockModalPromptScheduler()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    // MARK: - Root Attachment Checker

    @available(iOS 16, *)
    @Test("Presented Root Is Attached", .timeLimit(.minutes(1)))
    func whenRootIsPresentedThenAttachmentCheckPasses() {
        // GIVEN
        let attachmentChecker = ModalPromptRootAttachmentChecker()
        let presenter = UIViewController()
        let window = makeKeyWindow(withRoot: presenter)
        defer { window.isHidden = true }
        let root = UIViewController()

        // WHEN
        presenter.present(root, animated: false, completion: nil)

        // THEN
        #expect(root.presentingViewController === presenter)
        #expect(attachmentChecker.isAttached(root))
    }

    @available(iOS 16, *)
    @Test("Root Presenting Its Own Child Stays Attached", .timeLimit(.minutes(1)))
    func whenRootPresentsNestedChildThenRootRemainsAttached() async {
        // GIVEN
        let attachmentChecker = ModalPromptRootAttachmentChecker()
        let intendedPresenter = UIViewController()
        let window = makeKeyWindow(withRoot: intendedPresenter)
        defer { window.isHidden = true }
        let root = UIViewController()
        let nestedChild = UIViewController()
        // Wait on UIKit's own presentation completion rather than a delay. A nested `present` requested while the
        // outer presentation is still in flight is refused, leaving `root.presentedViewController` nil — so the
        // nesting this test draws its conclusion from would never be established.
        await withCheckedContinuation { continuation in
            intendedPresenter.present(root, animated: false) {
                continuation.resume()
            }
        }

        // WHEN
        await withCheckedContinuation { continuation in
            root.present(nestedChild, animated: false) {
                continuation.resume()
            }
        }

        // THEN — a child flow presented by the root does not detach the root itself.
        #expect(root.presentingViewController === intendedPresenter)
        #expect(root.presentedViewController === nestedChild)
        #expect(nestedChild.presentingViewController === root)
        #expect(attachmentChecker.isAttached(root))
    }

    @available(iOS 16, *)
    @Test("Root Being Dismissed Stays Attached Until Dismissal Completes", .timeLimit(.minutes(1)))
    func whenRootIsBeingDismissedThenAttachmentCheckPassesUntilDetachment() async {
        // GIVEN
        let attachmentChecker = ModalPromptRootAttachmentChecker()
        let presenter = UIViewController()
        let window = makeKeyWindow(withRoot: presenter)
        defer { window.isHidden = true }
        let root = UIViewController()
        // Wait on UIKit's own presentation completion rather than a delay. `isBeingDismissed` is only raised once the
        // presentation transition has finished; a dismissal requested while the presentation is still in flight is
        // coalesced into it and never raises the flag, which would make this test pass for the wrong reason.
        await withCheckedContinuation { continuation in
            presenter.present(root, animated: false) {
                continuation.resume()
            }
        }
        #expect(attachmentChecker.isAttached(root))

        // WHEN dismissal starts.
        await withCheckedContinuation { continuation in
            root.dismiss(animated: true) {
                continuation.resume()
            }

            // THEN UIKit's presentation and window relationships keep the outgoing root attached during the animation.
            #expect(root.isBeingDismissed)
            #expect(root.presentingViewController === presenter)
            #expect(root.viewIfLoaded?.window != nil)
            #expect(attachmentChecker.isAttached(root))
        }

        // THEN the root becomes detached only after UIKit completes the dismissal.
        #expect(!root.isBeingPresented)
        #expect(root.presentingViewController == nil)
        #expect(root.viewIfLoaded?.window == nil)
        #expect(!attachmentChecker.isAttached(root))
    }

    // MARK: - Coordination Manager

    @available(iOS 16, *)
    @Test("Nested Child Does Not Release Exact Selected Root", .timeLimit(.minutes(1)))
    func whenSelectedRootPresentsNestedChildThenReconciliationRetainsLease() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()

        // Give the selected root a real child presentation. The window exists only so UIKit accepts the nesting:
        // without it `exactRoot.presentedViewController` stays nil and a topmost walk would resolve straight back to
        // the exact root, leaving the two implementations indistinguishable.
        let window = makeKeyWindow(withRoot: exactRoot)
        defer { window.isHidden = true }
        let nestedChild = UIViewController()
        exactRoot.present(nestedChild, animated: false, completion: nil)

        // Assert the UIKit nesting the rest of the test depends on before drawing conclusions from it.
        #expect(exactRoot.presentedViewController === nestedChild)
        #expect(nestedChild.presentingViewController === exactRoot)

        // Only the exact root is attached as far as coordination is concerned: the child is never registered, so an
        // implementation that consulted the topmost controller would report the attempt finished and drop the lease.
        attachmentChecker.markAttached(exactRoot)

        #expect(!sut.reconcilePresentedModal())
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(attachmentChecker.didQuery(exactRoot))
        #expect(!attachmentChecker.didQuery(nestedChild))

        // The lease is released only once the retained root itself goes away, child presentation or not.
        attachmentChecker.attachedRoots.remove(ObjectIdentifier(exactRoot))

        #expect(sut.reconcilePresentedModal())
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Dismissing Root Retains Lease Until UIKit Detaches It", .timeLimit(.minutes(1)))
    func whenPresentedRootIsBeingDismissedThenLeaseBlocksAdmissionUntilDetachment() async throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(
            viewController: exactRoot,
            animated: false
        )
        let presentationHost = UIKitModalPromptPresenter()
        let window = makeKeyWindow(withRoot: presentationHost)
        defer { window.isHidden = true }
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()
        // Wait on UIKit's own presentation completion rather than assuming an unanimated presentation settles within
        // the same runloop turn. `isBeingDismissed` is only raised once the presentation transition has finished; a
        // dismissal requested while that transition is still in flight is coalesced into it, so the flag never rises
        // and UIKit detaches the root straight away — leaving nothing mid-animation for this test to observe.
        await withCheckedContinuation { continuation in
            presentationHost.onPresentationCompleted = { continuation.resume() }
            _ = sut.presentModalPromptIfNeeded(from: presentationHost, with: lease)
            schedulerMock.executeScheduledBlock()
        }
        #expect(exactRoot.presentingViewController === presentationHost)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))

        let waitingPromoIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "waiting-promo"
        )

        // WHEN dismissal starts but UIKit still presents and windows the exact root.
        await withCheckedContinuation { continuation in
            exactRoot.dismiss(animated: true) {
                continuation.resume()
            }

            // THEN the modal still owns the lease and blocks a waiting visible promo for the whole animation.
            #expect(exactRoot.isBeingDismissed)
            #expect(exactRoot.presentingViewController === presentationHost)
            #expect(exactRoot.viewIfLoaded?.window != nil)
            #expect(!sut.reconcilePresentedModal())
            #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
            guard case .blockedByModal = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: waitingPromoIdentity) else {
                Issue.record("Expected the dismissing modal to keep blocking visible promo admission")
                return
            }
        }

        // WHEN UIKit has completed dismissal and removed every attachment relationship.
        #expect(!exactRoot.isBeingPresented)
        #expect(exactRoot.presentingViewController == nil)
        #expect(exactRoot.viewIfLoaded?.window == nil)

        // THEN reconciliation releases the modal lease and the waiting promo can be admitted.
        #expect(sut.reconcilePresentedModal())
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        guard case .acquired(let visiblePromoLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: waitingPromoIdentity) else {
            Issue.record("Expected visible promo admission after the dismissed modal detached")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(waitingPromoIdentity))
        _ = visiblePromoLease
    }

    // MARK: - Standard Launch Ordering

    @available(iOS 16, *)
    @Test("Standard Launch Presents Keyboard OmniBar Before Eligible Modal", .timeLimit(.minutes(1)))
    func whenStandardLaunchSchedulesKeyboardAndEligibleModalThenModalPresentsFromOmniBar() async {
        let orderingScheduler = LaunchOrderingScheduler()
        let presentationHost = UIKitModalPromptPresenter()
        let window = makeKeyWindow(withRoot: presentationHost)
        defer { window.isHidden = true }

        let omniBar = OmniBarEditingStateViewController(
            switchBarHandler: LaunchOrderingSwitchBarHandler()
        )
        let modalRoot = UIViewController()
        let provider = LaunchOrderingModalPromptProvider(
            configuration: ModalPromptConfiguration(
                viewController: modalRoot,
                animated: false
            )
        )
        let launchSourceManager = MockLaunchSourceManager()
        let leaseArbiter = PromoQueueLeaseArbiter()
        let manager = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: MockPromptCooldownManager(),
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: orderingScheduler
        )
        let service = PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: manager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: leaseArbiter
        )
        var presentationEvents = [String]()
        let keyboardPresenter = KeyboardPresenter(
            isKeyboardOnAppLaunchEnabled: { true },
            scheduleKeyboardPresentation: { delay, action in
                _ = orderingScheduler.schedule(after: delay, execute: action)
            },
            enterSearch: {
                presentationEvents.append("keyboard")
                presentationHost.present(omniBar, animated: false, completion: nil)
            }
        )
        let launchActionHandler = LaunchActionHandler(
            urlHandler: MockURLHandler(),
            shortcutItemHandler: MockShortcutItemHandler(),
            userActivityHandler: MockUserActivityHandler(),
            keyboardPresenter: keyboardPresenter,
            launchSourceService: launchSourceManager,
            idleReturnEvaluator: MockIdleReturnEvaluator()
        )
        let interactionManager = UIInteractionManager(
            authenticationService: MockAuthenticationService(),
            autoClearService: MockAutoClearService(),
            launchActionHandler: launchActionHandler,
            onboardingPresenter: MockOnboardingPresenting()
        )

        let launchAction = LaunchAction.standardLaunch(lastBackgroundDate: nil, isFirstForeground: true)
        let readinessToken = service.captureForegroundReadinessToken()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            interactionManager.start(
                launchAction: launchAction,
                onWebViewReadyForInteractions: {},
                onAppReadyForInteractions: {
                    service.presentModalPromptIfNeeded(
                        from: presentationHost,
                        readinessToken: readinessToken
                    )
                    continuation.resume()
                }
            )
        }

        #expect(orderingScheduler.pendingDelayedBlockCount == 2)
        #expect(presentationHost.presentedViewController == nil)

        // Both production paths target the main queue. Equal deadlines preserve insertion order, so the keyboard
        // work enqueued by LaunchActionHandler must establish the real OmniBar relationship first.
        await withCheckedContinuation { continuation in
            presentationHost.onPresentationCompleted = { continuation.resume() }
            orderingScheduler.executeNextDelayedBlock()
        }

        #expect(presentationEvents == ["keyboard"])
        #expect(presentationHost.presentedViewController === omniBar)
        #expect(omniBar.presentedViewController == nil)
        guard presentationEvents == ["keyboard"],
              presentationHost.presentedViewController === omniBar else {
            Issue.record("Expected the keyboard work to install the OmniBar before modal presentation work ran")
            return
        }

        // The manager resolves its UIKit route only when its delayed work runs. This must therefore present through
        // the OmniBar that the preceding keyboard work installed, not through the original launch presenter.
        await withCheckedContinuation { continuation in
            provider.onDidPresentModal = {
                presentationEvents.append("modal")
                continuation.resume()
            }
            orderingScheduler.executeNextDelayedBlock()
        }

        #expect(presentationEvents == ["keyboard", "modal"])
        #expect(presentationHost.presentedViewController === omniBar)
        #expect(omniBar.presentedViewController === modalRoot)
        #expect(modalRoot.presentingViewController === omniBar)
    }

     private func acquireModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            throw RealUIKitTestError.expectedAcquiredLease
        }
        return lease
    }

    /// Stands up a visible window so UIKit accepts synchronous, unanimated presentations from `root`.
    ///
    /// Callers must hide the returned window again so it does not stay key for later tests.
    private func makeKeyWindow(withRoot root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.makeKeyAndVisible()
        return window
    }
}

@MainActor
private final class LaunchOrderingModalPromptProvider: ModalPromptProvider {
    private let configuration: ModalPromptConfiguration
    var onDidPresentModal: (() -> Void)?

    init(configuration: ModalPromptConfiguration) {
        self.configuration = configuration
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        configuration
    }

    func didPresentModal() {
        let onDidPresentModal = onDidPresentModal
        self.onDidPresentModal = nil
        onDidPresentModal?()
    }
}

/// Executes delayed work by deadline and then insertion order, matching the main queue ordering this test characterizes.
@MainActor
private final class LaunchOrderingScheduler: ModalPromptScheduling {
    private final class ScheduledBlock {
        let delay: TimeInterval
        let sequence: Int
        let execute: @MainActor () -> Void
        var isCancelled = false

        init(delay: TimeInterval, sequence: Int, execute: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.sequence = sequence
            self.execute = execute
        }
    }

    private var nextSequence = 0
    private var delayedBlocks = [ScheduledBlock]()
    private var nextMainTurnBlocks = [ScheduledBlock]()

    var pendingDelayedBlockCount: Int {
        delayedBlocks.filter { !$0.isCancelled }.count
    }

    @discardableResult
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        let scheduledBlock = makeScheduledBlock(delay: delay, execute: execute)
        delayedBlocks.append(scheduledBlock)
        return ModalPromptScheduledTask {
            scheduledBlock.isCancelled = true
        }
    }

    @discardableResult
    func scheduleOnNextMainTurn(execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        let scheduledBlock = makeScheduledBlock(delay: 0, execute: execute)
        nextMainTurnBlocks.append(scheduledBlock)
        return ModalPromptScheduledTask {
            scheduledBlock.isCancelled = true
        }
    }

    func executeNextDelayedBlock() {
        guard let nextBlockIndex = delayedBlocks.indices.min(by: {
            let lhs = delayedBlocks[$0]
            let rhs = delayedBlocks[$1]
            return lhs.delay == rhs.delay ? lhs.sequence < rhs.sequence : lhs.delay < rhs.delay
        }) else {
            return
        }

        let scheduledBlock = delayedBlocks.remove(at: nextBlockIndex)
        guard !scheduledBlock.isCancelled else {
            executeNextDelayedBlock()
            return
        }
        scheduledBlock.execute()
    }

    private func makeScheduledBlock(
        delay: TimeInterval,
        execute: @escaping @MainActor () -> Void
    ) -> ScheduledBlock {
        defer { nextSequence += 1 }
        return ScheduledBlock(delay: delay, sequence: nextSequence, execute: execute)
    }
}

private final class LaunchOrderingSwitchBarHandler: SwitchBarHandling {
    var currentText = ""
    var currentToggleState = TextEntryMode.search
    var isVoiceSearchEnabled = false
    let isAIVoiceChatEnabled = false
    var hasUserInteractedWithText = false
    var isCurrentTextValidURL = false
    var buttonState = SwitchBarButtonState.noButtons
    var isTopBarPosition = true
    var isToggleEnabled = false
    var isFireTab = false
    var isUsingExpandedBottomBarHeight = false
    var isUsingFadeOutAnimation = false
    var shouldDisableAutocorrectOnEmpty = false
    var hidesVoiceButton = false
    var hasSubmittedPrompt = false
    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { Empty().eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }
    var modeParameters: [String: String] { [:] }

    func updateCurrentText(_ text: String) {}
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) {}
    func clearText() {}
    func microphoneButtonTapped() {}
    func markUserInteraction() {}
    func clearButtonTapped() {}
    func stopGeneratingButtonTapped() {}
    func updateBarPosition(isTop: Bool) {}
}

private enum RealUIKitTestError: Error {
    case expectedAcquiredLease
}

/// A real UIKit presentation host, so a test can observe genuine presentation and dismissal transitions.
@MainActor
private final class UIKitModalPromptPresenter: UIViewController, ModalPromptPresenter {
    var modalPromptPresentationViewController: UIViewController? { self }

    /// Called once, after UIKit reports that the presentation transition has finished.
    ///
    /// A test that goes on to observe a dismissal must wait on this first: UIKit coalesces a dismissal requested
    /// while the presentation is still in flight, and the outgoing root then never enters a dismissing state.
    var onPresentationCompleted: (() -> Void)?

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        super.present(viewControllerToPresent, animated: flag) { [weak self] in
            completion?()
            guard let presentationCompleted = self?.onPresentationCompleted else { return }
            self?.onPresentationCompleted = nil
            presentationCompleted()
        }
    }
}
