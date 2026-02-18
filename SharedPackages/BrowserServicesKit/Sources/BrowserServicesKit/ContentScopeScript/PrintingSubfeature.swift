//
//  PrintingSubfeature.swift
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

import Foundation
#if os(macOS)
import Navigation
#endif
import UserScript
import WebKit

/// Protocol for handling print requests from content-scope-scripts.
///
/// Implement this protocol to receive print notifications when `window.print()`
/// is called in web content. The delegate is responsible for presenting the
/// appropriate print UI for the platform.
public protocol PrintingSubfeatureDelegate: AnyObject {
    /// Called when the web content requests printing via `window.print()`.
    ///
    /// - Parameters:
    ///   - frameHandle: On macOS, this is the `FrameHandle` identifying the frame that
    ///                  requested printing. On iOS, this is always `nil`. Cast to
    ///                  `FrameHandle?` on macOS to use with frame-specific print operations.
    ///   - webView: The web view containing the content to print. May be `nil` if
    ///              the web view is no longer available.
    @MainActor
    func printingSubfeatureDidRequestPrint(for frameHandle: Any?, in webView: WKWebView?)
}

/// Subfeature that handles print notifications from content-scope-scripts.
///
/// This subfeature replaces the legacy `PrintingUserScript` by integrating with
/// the content-scope-scripts messaging system. When the JavaScript `Print` feature
/// calls `window.print()`, it sends a notification that this subfeature handles.
///
/// ## Usage
///
/// 1. Create an instance of `PrintingSubfeature`
/// 2. Set its `delegate` to receive print requests
/// 3. Register it with the `ContentScopeUserScript`:
///
/// ```swift
/// let printingSubfeature = PrintingSubfeature()
/// printingSubfeature.delegate = self
/// contentScopeUserScript.registerSubfeature(delegate: printingSubfeature)
/// ```
///
/// 4. Add `PrintingSubfeature.featureNameValue` to `allowedNonisolatedFeatures`
///    when creating the `ContentScopeUserScript`.
public final class PrintingSubfeature: NSObject, Subfeature {

    /// The feature name used for message routing. Must match the JavaScript feature name.
    public static let featureNameValue = "print"

    /// Printing should work on any website, so we allow all origins.
    public let messageOriginPolicy: MessageOriginPolicy = .all

    /// The feature name for subfeature registration.
    public let featureName: String = PrintingSubfeature.featureNameValue

    /// Reference to the message broker (set when registered with a UserScript).
    public weak var broker: UserScriptMessageBroker?

    /// The delegate that handles print requests.
    public weak var delegate: PrintingSubfeatureDelegate?

    public override init() {
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    /// Message names that this subfeature handles.
    enum MessageNames: String, CaseIterable {
        case print
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .print:
            return { [weak self] in try await self?.handlePrint(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func handlePrint(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        #if os(macOS)
        let frameHandle: Any? = original.frameInfo.handle
        #else
        let frameHandle: Any? = nil
        #endif
        delegate?.printingSubfeatureDidRequestPrint(
            for: frameHandle,
            in: original.webView
        )
        return nil
    }
}
