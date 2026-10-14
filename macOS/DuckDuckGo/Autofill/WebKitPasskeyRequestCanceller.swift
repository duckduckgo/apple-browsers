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

/// The parts of an authorization controller the canceller uses, so tests can use fakes.
protocol PasskeyAuthorizationController: AnyObject {
    var delegate: ASAuthorizationControllerDelegate? { get set }
    func cancel()
}

@available(macOS 13.0, *)
extension ASAuthorizationController: PasskeyAuthorizationController {}

/// Cancels WebKit's previous passkey request before WebKit starts the next one.
///
/// WebKit keeps one pending `ASAuthorizationController` per page and replaces it without cancelling it when the
/// page navigates and later starts a request, or starts a second request while one is pending (for example an
/// AutoFill request and a sign-in). The replaced request stays open in the system passkey agent, which then rejects
/// every later passkey request from the app until it restarts. WebKit's passkey code runs in the app process, so
/// its controllers pass through here before they perform.
final class WebKitPasskeyRequestCanceller {

    private let webKitDelegateClass: AnyClass
    private let isEnabled: () -> Bool
    /// Held strongly: once WebKit replaces it, nothing else keeps it reachable.
    private var lastWebKitController: PasskeyAuthorizationController?

    init(webKitDelegateClass: AnyClass, isEnabled: @escaping () -> Bool) {
        self.webKitDelegateClass = webKitDelegateClass
        self.isEnabled = isEnabled
    }

    /// Called before a controller performs its requests.
    func willPerform(_ controller: PasskeyAuthorizationController) {
        guard isEnabled(),
              let delegate = controller.delegate,
              (delegate as AnyObject).isKind(of: webKitDelegateClass) else { return }
        defer { lastWebKitController = controller }
        // WebKit performs the same controller again when it resumes an AutoFill request it paused.
        guard let previous = lastWebKitController, previous !== controller else { return }

        Logger.general.log("Cancelling the previous WebKit passkey request")
        // WebKit has already pointed its completion callback at the new request, so the previous request's
        // cancellation must not reach it.
        previous.delegate = nil
        previous.cancel()
    }
}

extension WebKitPasskeyRequestCanceller {

    private static var installed: WebKitPasskeyRequestCanceller?

    /// Runs `willPerform` before every `ASAuthorizationController` performs its requests. Does nothing if WebKit's
    /// delegate class or the controller methods aren't there.
    static func install(isEnabled: @escaping () -> Bool) {
        guard #available(macOS 13.0, *),
              installed == nil,
              let webKitDelegateClass = NSClassFromString("_WKASDelegate") else { return }

        let canceller = WebKitPasskeyRequestCanceller(webKitDelegateClass: webKitDelegateClass, isEnabled: isEnabled)
        installed = canceller
        hook(#selector(ASAuthorizationController.performRequests), canceller: canceller)
        hook(NSSelectorFromString("performAutoFillAssistedRequests"), canceller: canceller)
    }

    @available(macOS 13.0, *)
    private static func hook(_ selector: Selector, canceller: WebKitPasskeyRequestCanceller) {
        guard let method = class_getInstanceMethod(ASAuthorizationController.self, selector) else { return }

        typealias Perform = @convention(c) (ASAuthorizationController, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Perform.self)
        let replacement: @convention(block) (ASAuthorizationController) -> Void = { controller in
            canceller.willPerform(controller)
            original(controller, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}
