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

/// The parts of an authorization controller the canceller uses, so tests can use fakes.
protocol PasskeyAuthorizationController: AnyObject {
    var delegate: ASAuthorizationControllerDelegate? { get set }
    func cancel()
    /// Reports the request as cancelled to its delegate without it ever reaching the agent.
    func completeAsCancelled()
}

@available(macOS 13.0, *)
extension ASAuthorizationController: PasskeyAuthorizationController {
    func completeAsCancelled() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.canceled.rawValue)
        delegate?.authorizationController?(controller: self, didCompleteWithError: error)
    }
}

/// Cancels WebKit's previous passkey request before WebKit starts the next one.
///
/// WebKit keeps one pending `ASAuthorizationController` per page and replaces it without cancelling it when the
/// page navigates and later starts a request, or starts a second request while one is pending (for example an
/// AutoFill request and a sign-in). The replaced request stays open in the system passkey agent, which then rejects
/// every later passkey request from the app until it restarts. WebKit's passkey code runs in the app process, so
/// its controllers pass through here before they perform, and the previous one is cancelled.
///
/// A replaced controller no longer has WebKit's delegate (WebKit released it), so its cancellation reaches nobody.
/// A request still open in another page keeps its delegate, so WebKit completes it as usual.
final class WebKitPasskeyRequestCanceller {

    private let webKitDelegateClass: AnyClass
    private let isEnabled: () -> Bool
    /// Held strongly: once WebKit replaces it, nothing else keeps it reachable.
    private var lastWebKitController: PasskeyAuthorizationController?
    /// How long a new request waits after cancelling a request still open in another page. The agent winds the
    /// cancelled request down (closing its sheet) for about 0.6 s, and when it finishes it also drops the app's
    /// other open requests, so a request started sooner would be dropped.
    private let delayAfterCancellingOpenRequest: TimeInterval
    /// A WebKit request waiting for that delay before it starts.
    private var heldRequest: (controller: PasskeyAuthorizationController, perform: () -> Void)?

    init(webKitDelegateClass: AnyClass, isEnabled: @escaping () -> Bool, delayAfterCancellingOpenRequest: TimeInterval = 1) {
        self.webKitDelegateClass = webKitDelegateClass
        self.isEnabled = isEnabled
        self.delayAfterCancellingOpenRequest = delayAfterCancellingOpenRequest
    }

    /// Called instead of a controller's `performRequests` or `performAutoFillAssistedRequests`; `perform` runs the
    /// original method.
    func willPerform(_ controller: PasskeyAuthorizationController, perform: @escaping () -> Void) {
        guard isEnabled() else {
            lastWebKitController = nil
            perform()
            return
        }
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
            // WebKit performs the same controller again when it resumes an AutoFill request it paused, so only a
            // different controller is cancelled. A replaced request no longer has WebKit's delegate; one still open
            // in another page does.
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

    /// Called instead of a controller's `cancel`. Returns whether the original `cancel` should run.
    func willCancel(_ controller: PasskeyAuthorizationController) -> Bool {
        guard let held = heldRequest, held.controller === controller else { return true }
        heldRequest = nil
        controller.completeAsCancelled()
        return false
    }
}

extension WebKitPasskeyRequestCanceller {

    private static var installed: WebKitPasskeyRequestCanceller?

    /// Runs `willPerform` before every `ASAuthorizationController` performs its requests. Installs nothing, and
    /// fires a pixel, if WebKit's delegate class or a controller method isn't there.
    static func install(isEnabled: @escaping () -> Bool,
                        webKitDelegateClass: AnyClass? = NSClassFromString("_WKASDelegate"),
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

        let canceller = WebKitPasskeyRequestCanceller(webKitDelegateClass: webKitDelegateClass, isEnabled: isEnabled)
        installed = canceller
        hook(performRequests, canceller: canceller)
        hook(performAutoFillAssistedRequests, canceller: canceller)
        hookCancel(canceller: canceller)
    }

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

enum PasskeyRequestCancellationPixel: PixelKit.Event {

    enum InstallFailureReason: String {
        case webKitDelegateClass = "webkit_delegate_class"
        case performRequests = "perform_requests"
        case performAutoFillAssistedRequests = "perform_autofill_assisted_requests"
    }

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
