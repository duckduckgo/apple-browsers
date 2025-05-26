//
//  OverlayAutofillUserScript.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import CoreGraphics
import Foundation
import UserScript

/// Is used by the top Autofill to reference into the child autofill
public protocol OverlayAutofillUserScriptDelegate: AnyObject {
    /// Represents the last tab host, is used to verify messages origin from and selecting of credentials
    var overlayAutofillUserScriptLastOpenHost: String? { get }
    /// Handles filling the credentials back from the top autofill into the child
    func overlayAutofillUserScript(_ overlayAutofillUserScript: OverlayAutofillUserScript,
                                   messageSelectedCredential: [String: String],
                                   _ configType: String)
    /// Closes the overlay
    func overlayAutofillUserScriptClose(_ overlayAutofillUserScript: OverlayAutofillUserScript)
}

/// Handles calls from the top Autofill context to the overlay
public protocol OverlayAutofillUserScriptPresentationDelegate: AnyObject {
    /// Provides a size that the overlay should be resized to
    func overlayAutofillUserScript(_ overlayAutofillUserScript: OverlayAutofillUserScript, requestResizeToSize: CGSize)
}

public class OverlayAutofillUserScript: AutofillUserScript {

    public weak var contentOverlay: OverlayAutofillUserScriptPresentationDelegate?
    /// Used as a message channel from parent WebView to the relevant in page AutofillUserScript.
    public weak var websiteAutofillInstance: OverlayAutofillUserScriptDelegate?

    internal enum OverlayUserScriptMessageName: String, CaseIterable {
        case setSize
        case selectedDetail
        case closeAutofillParent
    }

    public override var messageNames: [String] {
        return OverlayUserScriptMessageName.allCases.map(\.rawValue) + super.messageNames
    }

    public override func messageHandlerFor(_ messageName: String) -> MessageHandler? {
        guard let overlayUserScriptMessage = OverlayUserScriptMessageName(rawValue: messageName) else {
            return super.messageHandlerFor(messageName)
        }

        switch overlayUserScriptMessage {
        case .setSize: return setSize
        case .selectedDetail: return selectedDetail
        case .closeAutofillParent: return closeAutofillParent
        }
    }

    override func hostForMessage(_ message: UserScriptMessage) -> String {
        return websiteAutofillInstance?.overlayAutofillUserScriptLastOpenHost ?? ""
    }

    func closeAutofillParent(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard websiteAutofillInstance != nil else { return }
        closeAutofillParent()
        replyHandler(nil)
    }

    public func closeAutofillParent() {
        guard let websiteAutofillInstance = websiteAutofillInstance else { return }
        self.contentOverlay?.overlayAutofillUserScript(self, requestResizeToSize: CGSize(width: 0, height: 0))
        websiteAutofillInstance.overlayAutofillUserScriptClose(self)
    }

    /// Used to create a top autofill context script for injecting into a ContentOverlay
    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider, overlay: OverlayAutofillUserScriptPresentationDelegate) {
        self.init(scriptSourceProvider: scriptSourceProvider, encrypter: AESGCMUserScriptEncrypter(), hostProvider: SecurityOriginHostProvider())
        self.isTopAutofillContext = true
        self.contentOverlay = overlay
    }

    func setSize(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
                  return replyHandler(nil)
              }
        self.contentOverlay?.overlayAutofillUserScript(self, requestResizeToSize: CGSize(width: width, height: height))
        replyHandler(nil)
    }

    /// Called from top autofill messages and stores the details the user clicked on into the child autofill
    func selectedDetail(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let chosenCredential = dict["data"] as? [String: String],
              let configType = dict["configType"] as? String,
              let autofillInterfaceToChild = websiteAutofillInstance else { return }
        autofillInterfaceToChild.overlayAutofillUserScript(self, messageSelectedCredential: chosenCredential, configType)
    }

}
