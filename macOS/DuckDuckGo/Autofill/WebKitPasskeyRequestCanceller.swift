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
    private var lastWebKitController: PasskeyAuthorizationController?
    /// How long a new request waits after cancelling one still open in another page, so it starts only after the agent
    /// has finished winding down the cancelled one. The app gets no signal when that happens, so a fixed delay is the
    /// only safe option found.
    private let delayAfterCancellingOpenRequest: TimeInterval
    /// A request WebKit asked to start that hasn't been sent to the agent yet, because it's waiting out
    /// ``delayAfterCancellingOpenRequest``. Kept so it can be started once the delay passes, or reported to WebKit as
    /// cancelled if WebKit cancels it or a newer request replaces it first.
    private var heldRequest: (controller: PasskeyAuthorizationController, perform: () -> Void)?

    init(webKitDelegateClass: AnyClass, delayAfterCancellingOpenRequest: TimeInterval = 1) {
        self.webKitDelegateClass = webKitDelegateClass
        self.delayAfterCancellingOpenRequest = delayAfterCancellingOpenRequest
    }

    /// Decides when a WebKit request may start, cancelling the previous one first. Called in place of the controller's
    /// `performRequests` and `performAutoFillAssistedRequests`; `perform` runs the original method, either right away or
    /// after ``delayAfterCancellingOpenRequest``. Requests that don't come from WebKit start untouched.
    func willPerform(_ controller: PasskeyAuthorizationController, perform: @escaping () -> Void) {
        guard let delegate = controller.delegate,
              (delegate as AnyObject).isKind(of: webKitDelegateClass) else {
            perform()
            return
        }

        var mustWait = false
        if let held = heldRequest, held.controller !== controller {
            // A newer request replaces the one still waiting, which never reached the agent. The earlier
            // cancellation's wind-down is still running, so the newer one waits too.
            heldRequest = nil
            held.controller.completeAsCancelled()
            mustWait = true
        } else if let previous = lastWebKitController, previous !== controller {
            // A controller starting again is the same request resuming, so it isn't cancelled. A previous request
            // that still has its delegate is open in another page, so the new one waits.
            mustWait = previous.delegate != nil
            Logger.general.log("Cancelling the previous WebKit passkey request")
            previous.cancel()
        }
        lastWebKitController = controller

        guard mustWait else {
            perform()
            return
        }
        heldRequest = (controller, perform)
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
    private static var installed: WebKitPasskeyRequestCanceller?

    /// Routes every start and cancel of an `ASAuthorizationController` through a canceller, for the rest of the app's
    /// run. Only WebKit's requests are affected; any other request passes straight through. Call once at launch, before
    /// any web view starts a passkey request.
    ///
    /// If WebKit's delegate class or one of those methods is missing, for example because a macOS update changed
    /// WebKit, nothing is installed, passkeys behave as they would without it, and a pixel reports why.
    ///
    /// - Parameter webKitDelegateClass: WebKit's private delegate class, which is how WebKit's requests are recognised.
    static func install(webKitDelegateClass: AnyClass? = NSClassFromString("_WKASDelegate"),
                        pixelFiring: PixelFiring? = PixelKit.shared) {
        guard #available(macOS 13.0, *), installed == nil else { return }

        let performRequests = #selector(ASAuthorizationController.performRequests)
        let performAutoFillAssistedRequests = NSSelectorFromString("performAutoFillAssistedRequests")
        let failure: PasskeyRequestCancellationPixel.InstallFailureReason?
        if webKitDelegateClass == nil {
            failure = .webKitDelegateClass
        } else if class_getInstanceMethod(ASAuthorizationController.self, performRequests) == nil {
            failure = .performRequests
        } else if class_getInstanceMethod(ASAuthorizationController.self, performAutoFillAssistedRequests) == nil {
            failure = .performAutoFillAssistedRequests
        } else {
            failure = nil
        }
        guard let webKitDelegateClass, failure == nil else {
            Logger.general.error("WebKit passkey request canceller not installed: \(failure?.rawValue ?? "", privacy: .public) missing")
            pixelFiring?.fire(PasskeyRequestCancellationPixel.installFailed(failure ?? .webKitDelegateClass), frequency: .dailyAndCount)
            return
        }

        let canceller = WebKitPasskeyRequestCanceller(webKitDelegateClass: webKitDelegateClass)
        installed = canceller
        hook(performRequests, canceller: canceller)
        hook(performAutoFillAssistedRequests, canceller: canceller)
        hookCancel(canceller: canceller)
    }

    /// Replaces the controller method `selector`, so the canceller decides when Apple's original runs.
    @available(macOS 13.0, *)
    private static func hook(_ selector: Selector, canceller: WebKitPasskeyRequestCanceller) {
        guard let method = class_getInstanceMethod(ASAuthorizationController.self, selector) else { return }

        typealias Perform = @convention(c) (ASAuthorizationController, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Perform.self)
        let replacement: @convention(block) (ASAuthorizationController) -> Void = { controller in
            canceller.willPerform(controller) { original(controller, selector) }
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }

    /// Replaces the controller's `cancel`, so a held request can be answered without being sent to the agent.
    @available(macOS 13.0, *)
    private static func hookCancel(canceller: WebKitPasskeyRequestCanceller) {
        let selector = #selector(ASAuthorizationController.cancel)
        guard let method = class_getInstanceMethod(ASAuthorizationController.self, selector) else { return }

        typealias Cancel = @convention(c) (ASAuthorizationController, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Cancel.self)
        let replacement: @convention(block) (ASAuthorizationController) -> Void = { controller in
            if canceller.willCancel(controller) {
                original(controller, selector)
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}

/// Pixels for `WebKitPasskeyRequestCanceller`.
enum PasskeyRequestCancellationPixel: PixelKit.Event {

    /// What `install` found missing.
    enum InstallFailureReason: String {
        case webKitDelegateClass = "webkit_delegate_class"
        case performRequests = "perform_requests"
        case performAutoFillAssistedRequests = "perform_autofill_assisted_requests"
    }

    /// The canceller couldn't install at launch, so WebKit's passkey requests aren't being cancelled.
    case installFailed(InstallFailureReason)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .installFailed:
            return "passkey_request_cancellation_install_failed_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .installFailed(let reason):
            return ["reason": reason.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
