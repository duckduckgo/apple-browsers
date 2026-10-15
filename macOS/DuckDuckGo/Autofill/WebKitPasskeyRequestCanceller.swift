//
//  WebKitPasskeyRequestCanceller.swift
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

import AppKit
import AuthenticationServices
import Foundation
import os.log
import PixelKit

/// The parts of `ASAuthorizationController` that `WebKitPasskeyRequestCanceller` uses, as a protocol so tests can use
/// fakes.
protocol PasskeyAuthorizationController: AnyObject {
    var delegate: ASAuthorizationControllerDelegate? { get set }
    func cancel()
    /// Tells the delegate the request was cancelled, the same way AuthenticationServices would. Used for a request that
    /// was held back and never started, so there's nothing to cancel in the agent.
    func completeAsCancelled()
}

@available(macOS 13.0, *)
extension ASAuthorizationController: PasskeyAuthorizationController {
    func completeAsCancelled() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.canceled.rawValue)
        delegate?.authorizationController?(controller: self, didCompleteWithError: error)
    }
}

/// Keeps passkeys working by making sure WebKit never leaves a passkey request open behind it.
///
/// The system passkey agent allows the app one open passkey request at a time. When a page starts a new request,
/// WebKit can replace the previous one without cancelling it, and once replaced nothing can cancel it: the agent
/// then refuses every later passkey request from the app until it restarts.
///
/// Once installed, this cancels WebKit's previous request whenever WebKit starts a new one. When the previous
/// request was still open in another page, the new one starts after a short delay, because the agent drops the
/// app's open requests when it finishes winding down a cancelled one.
final class WebKitPasskeyRequestCanceller {

    private let webKitDelegateClass: AnyClass
    /// The latest WebKit request, cancelled when the next one starts. Held strongly because WebKit lets go of it as
    /// soon as it replaces it.
    private(set) var lastWebKitController: PasskeyAuthorizationController?
    /// How long a new request waits after cancelling one still open in another page, so it starts only after the agent
    /// has finished winding down the cancelled one. The app gets no signal when that happens, so a fixed delay is the
    /// only safe option found.
    private let delayAfterCancellingOpenRequest: TimeInterval
    /// A request WebKit asked to start that hasn't been sent to the agent yet, because it's waiting out
    /// ``delayAfterCancellingOpenRequest``. Kept so it can be started once the delay passes, or reported to WebKit as
    /// cancelled if WebKit cancels it or a newer request replaces it first.
    private var heldRequest: HeldRequest?

    private struct HeldRequest {
        let controller: PasskeyAuthorizationController
        /// Runs the original method that starts the request.
        let perform: () -> Void
    }

    init(webKitDelegateClass: AnyClass, delayAfterCancellingOpenRequest: TimeInterval = 1) {
        self.webKitDelegateClass = webKitDelegateClass
        self.delayAfterCancellingOpenRequest = delayAfterCancellingOpenRequest
    }

    /// Decides when a WebKit request may start, cancelling the previous one first. Called in place of the controller's
    /// `performRequests` and `performAutoFillAssistedRequests`; `perform` runs the original method, either right away or
    /// after ``delayAfterCancellingOpenRequest``. Requests that don't come from WebKit start untouched.
    func willPerform(_ controller: PasskeyAuthorizationController, perform: @escaping () -> Void) {
        guard isWebKitRequest(controller) else { return perform() }

        let mustWait = endHeldRequest() || cancelPreviousRequest(before: controller)
        lastWebKitController = controller

        if mustWait {
            hold(controller, perform: perform)
        } else {
            perform()
        }
    }

    private func isWebKitRequest(_ controller: PasskeyAuthorizationController) -> Bool {
        guard let delegate = controller.delegate else { return false }
        return (delegate as AnyObject).isKind(of: webKitDelegateClass)
    }

    /// Ends the request still held from an earlier cancellation; it never reached the agent, so WebKit is told it was
    /// cancelled. Returns whether one was held: that cancellation is still winding down, so the new request waits too.
    private func endHeldRequest() -> Bool {
        guard let held = heldRequest else { return false }
        heldRequest = nil
        held.controller.completeAsCancelled()
        return true
    }

    /// Cancels the previous request. Returns whether the new request has to wait: a previous request that still has
    /// WebKit's delegate is open in another page or paused, and its wind-down would drop the new one. One without it was
    /// replaced or has finished.
    private func cancelPreviousRequest(before controller: PasskeyAuthorizationController) -> Bool {
        // A controller starting again is the same request resuming, so there's nothing to cancel.
        guard let previous = lastWebKitController, previous !== controller else { return false }
        let isStillOpen = previous.delegate != nil
        Logger.general.log("Cancelling the previous WebKit passkey request")
        previous.cancel()
        return isStillOpen
    }

    /// Starts the request once ``delayAfterCancellingOpenRequest`` has passed, unless WebKit cancels it or a newer
    /// request replaces it first.
    private func hold(_ controller: PasskeyAuthorizationController, perform: @escaping () -> Void) {
        heldRequest = HeldRequest(controller: controller, perform: perform)
        DispatchQueue.main.asyncAfter(deadline: .now() + delayAfterCancellingOpenRequest) { [weak self, weak controller] in
            guard let self, let held = heldRequest, held.controller === controller else { return }
            heldRequest = nil
            held.perform()
        }
    }

    /// Called in place of the controller's `cancel`. Returns whether the original `cancel` should run, which it should
    /// for every request except one we're holding back (see ``heldRequest``).
    ///
    /// WebKit believes a held request has already started, but we haven't sent it to the agent yet, so there's nothing
    /// for the original `cancel` to stop. Instead, the held request is dropped so it never starts, and WebKit is told it
    /// was cancelled, because WebKit waits for that answer before it carries on.
    func willCancel(_ controller: PasskeyAuthorizationController) -> Bool {
        guard let held = heldRequest, held.controller === controller else { return true }
        heldRequest = nil
        controller.completeAsCancelled()
        return false
    }
}

extension WebKitPasskeyRequestCanceller {

    /// The canceller in use, kept so it's installed only once.
    fileprivate static var installed: WebKitPasskeyRequestCanceller?

    /// Routes every start and cancel of an `ASAuthorizationController` through a canceller, for the rest of the app's
    /// run. Only WebKit's requests are affected; any other request passes straight through. Call once at launch, before
    /// any web view starts a passkey request.
    ///
    /// If WebKit's delegate class is missing, for example because a macOS update changed WebKit, nothing is installed,
    /// passkeys behave as they would without it, and a pixel reports it.
    static func install(pixelFiring: PixelFiring? = PixelKit.shared) {
        guard #available(macOS 13.0, *), installed == nil else { return }

        // The swizzled methods are public `ASAuthorizationController` API, so only WebKit's private delegate class can
        // disappear without notice.
        guard let webKitDelegateClass = NSClassFromString(webKitDelegateClassName) else {
            Logger.general.error("WebKit passkey request canceller not installed: \(webKitDelegateClassName, privacy: .public) is missing")
            pixelFiring?.fire(PasskeyRequestCancellationPixel.webKitDelegateClassMissing, frequency: .dailyAndCount)
            return
        }

        installed = WebKitPasskeyRequestCanceller(webKitDelegateClass: webKitDelegateClass)
        _ = ASAuthorizationController.swizzlePasskeyRequestMethodsOnce
        outcomeReporter = PasskeyRequestOutcomeReporter(pixelFiring: pixelFiring)
        _ = NSObject.swizzleWebKitDelegateCompletionMethodsOnce
        willTerminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                       object: nil,
                                                                       queue: .main) { _ in
            cancelOpenRequestBeforeQuitting()
        }
    }

    private static var willTerminateObserver: NSObjectProtocol?

    /// Cancels WebKit's request if it's still open in the agent. The agent keeps a request the app never cancelled even
    /// after the app quits, and then refuses every passkey request from the app's next launch.
    @available(macOS 13.0, *)
    private static func cancelOpenRequestBeforeQuitting() {
        guard let controller = installed?.lastWebKitController as? ASAuthorizationController,
              let start = controller.passkeyRequestStart, !start.wasCancelled else { return }

        Logger.general.log("Cancelling the open WebKit passkey request before quitting")
        controller.cancel()
    }

    /// WebKit's private `ASAuthorizationController` delegate, which is how WebKit's passkey requests are recognised.
    fileprivate static let webKitDelegateClassName = "_WKASDelegate"
}

@available(macOS 13.0, *)
extension ASAuthorizationController {

    fileprivate static let swizzlePasskeyRequestMethodsOnce: Void = {
        swizzle(#selector(performRequests), with: #selector(swizzled_performRequests))
        swizzle(NSSelectorFromString("performAutoFillAssistedRequests"), with: #selector(swizzled_performAutoFillAssistedRequests))
        swizzle(#selector(cancel), with: #selector(swizzled_cancel))
    }()

    private static func swizzle(_ originalSelector: Selector, with swizzledSelector: Selector) {
        guard let originalMethod = class_getInstanceMethod(ASAuthorizationController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(ASAuthorizationController.self, swizzledSelector) else {
            assertionFailure("Failed to swizzle \(originalSelector)")
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    /// Lets the canceller decide when the request starts.
    @objc dynamic fileprivate func swizzled_performRequests() {
        guard let canceller = WebKitPasskeyRequestCanceller.installed else { return swizzled_performRequests() }
        canceller.willPerform(self) {
            self.passkeyRequestStart = PasskeyRequestStart(style: .modal)
            self.swizzled_performRequests() // calls the original method
        }
    }

    /// Lets the canceller decide when the AutoFill request starts.
    @objc dynamic fileprivate func swizzled_performAutoFillAssistedRequests() {
        guard let canceller = WebKitPasskeyRequestCanceller.installed else { return swizzled_performAutoFillAssistedRequests() }
        canceller.willPerform(self) {
            self.passkeyRequestStart = PasskeyRequestStart(style: .autofill)
            self.swizzled_performAutoFillAssistedRequests() // calls the original method
        }
    }

    /// Lets the canceller answer a held request without it being sent to the agent.
    @objc dynamic fileprivate func swizzled_cancel() {
        passkeyRequestStart?.wasCancelled = true
        guard WebKitPasskeyRequestCanceller.installed?.willCancel(self) ?? true else { return }
        swizzled_cancel() // calls the original method
    }

    private static let passkeyRequestStartKey = UnsafeRawPointer(bitPattern: "passkeyRequestStartKey".hashValue)!

    /// When and how the request was sent to the agent, so its outcome can be reported with it. `nil` for a request that
    /// never reached the agent.
    fileprivate var passkeyRequestStart: PasskeyRequestStart? {
        get {
            objc_getAssociatedObject(self, Self.passkeyRequestStartKey) as? PasskeyRequestStart
        }
        set {
            objc_setAssociatedObject(self, Self.passkeyRequestStartKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

/// When and how a WebKit passkey request was sent to the agent.
private final class PasskeyRequestStart: NSObject {
    let style: PasskeyRequestOutcome.Style
    let date = Date()
    /// Whether WebKit or the canceller cancelled the request, so its failure isn't something the user did or saw.
    var wasCancelled = false

    init(style: PasskeyRequestOutcome.Style) {
        self.style = style
    }
}

extension WebKitPasskeyRequestCanceller {

    /// Reports how WebKit's passkey requests end, kept so it's created only once.
    fileprivate static var outcomeReporter: PasskeyRequestOutcomeReporter?

    /// Reports the outcome of a request the user saw end. Requests that never reached the agent, and failures of
    /// requests WebKit or the canceller cancelled, aren't reported.
    @available(macOS 13.0, *)
    fileprivate static func reportOutcome(of controller: ASAuthorizationController, error: NSError?) {
        guard let start = controller.passkeyRequestStart else { return }
        controller.passkeyRequestStart = nil
        if error != nil && start.wasCancelled { return }

        let request = controller.authorizationRequests.first
        let type: PasskeyRequestOutcome.RequestType
        switch request {
        case is ASAuthorizationPublicKeyCredentialAssertionRequest: type = .get
        case is ASAuthorizationPublicKeyCredentialRegistrationRequest: type = .create
        default: type = .other
        }

        outcomeReporter?.report(PasskeyRequestOutcome(style: start.style,
                                                      type: type,
                                                      result: .init(error: error),
                                                      duration: .init(Date().timeIntervalSince(start.date))))
    }
}

/// Swizzled methods for WebKit's private passkey delegate, which Swift can't extend. They're declared on `NSObject` and
/// copied onto WebKit's delegate class before being exchanged, so `NSObject` itself is left unchanged.
@available(macOS 13.0, *)
extension NSObject {

    fileprivate static let swizzleWebKitDelegateCompletionMethodsOnce: Void = {
        guard let delegateClass = NSClassFromString(WebKitPasskeyRequestCanceller.webKitDelegateClassName) else { return }
        swizzle(#selector(ASAuthorizationControllerDelegate.authorizationController(controller:didCompleteWithAuthorization:)),
                with: #selector(swizzled_authorizationController(_:didCompleteWithAuthorization:)),
                in: delegateClass)
        swizzle(#selector(ASAuthorizationControllerDelegate.authorizationController(controller:didCompleteWithError:)),
                with: #selector(swizzled_authorizationController(_:didCompleteWithError:)),
                in: delegateClass)
    }()

    private static func swizzle(_ originalSelector: Selector, with swizzledSelector: Selector, in delegateClass: AnyClass) {
        guard let originalMethod = class_getInstanceMethod(delegateClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSObject.self, swizzledSelector),
              class_addMethod(delegateClass, swizzledSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)),
              let addedMethod = class_getInstanceMethod(delegateClass, swizzledSelector) else {
            assertionFailure("Failed to swizzle \(originalSelector)")
            return
        }
        method_exchangeImplementations(originalMethod, addedMethod)
    }

    /// Reports the request's success before WebKit handles it.
    @objc dynamic fileprivate func swizzled_authorizationController(_ controller: ASAuthorizationController,
                                                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        WebKitPasskeyRequestCanceller.reportOutcome(of: controller, error: nil)
        swizzled_authorizationController(controller, didCompleteWithAuthorization: authorization) // calls the original method
    }

    /// Reports the request's failure before WebKit handles it.
    @objc dynamic fileprivate func swizzled_authorizationController(_ controller: ASAuthorizationController,
                                                                  didCompleteWithError error: Error) {
        WebKitPasskeyRequestCanceller.reportOutcome(of: controller, error: error as NSError)
        swizzled_authorizationController(controller, didCompleteWithError: error) // calls the original method
    }
}

/// Pixels for `WebKitPasskeyRequestCanceller`.
enum PasskeyRequestCancellationPixel: PixelKit.Event {

    /// WebKit's passkey delegate class is missing, so the canceller isn't installed and WebKit's passkey requests aren't
    /// being cancelled.
    case webKitDelegateClassMissing

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .webKitDelegateClassMissing:
            return "passkey_request_cancellation_install_failed_macos"
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
