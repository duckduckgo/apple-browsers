//
//  WebsiteAutofillUserScript.swift
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

/// Handles calls from the website Autofill context to the overlay.
public protocol ContentOverlayUserScriptDelegate: AnyObject {
    /// Closes the overlay
    func websiteAutofillUserScriptCloseOverlay(_ websiteAutofillUserScript: WebsiteAutofillUserScript?)
    /// Opens the overlay
    func websiteAutofillUserScript(_ websiteAutofillUserScript: WebsiteAutofillUserScript,
                                   willDisplayOverlayAtClick: CGPoint?,
                                   serializedInputContext: String,
                                   inputPosition: CGRect)
}

public class WebsiteAutofillUserScript: AutofillUserScript {
    public var lastOpenHost: String?
    /// Holds a reference to the tab that is displaying the content overlay.
    public weak var currentOverlayTab: ContentOverlayUserScriptDelegate?
    /// Last user click position, used to position the overlay
    public var clickPoint: CGPoint?
    /// Last user selected details in the top autofill overlay stored in the child.
    var selectedDetailsData: SelectedDetailsData?

    private enum CredentialsResponse {
        static let none = "none"
        static let state = "state"
        static let stop = "stop"
        static let ok = "ok"
    }

    public override var messageNames: [String] {
        return WebsiteAutofillMessageName.allCases.map(\.rawValue) + super.messageNames
    }

    public enum WebsiteAutofillMessageName: String, CaseIterable {
        case closeAutofillParent
        case getSelectedCredentials
        case showAutofillParent
    }

    public override func messageHandlerFor(_ messageName: String) -> MessageHandler? {
        guard let websiteAutofillMessageName = WebsiteAutofillMessageName(rawValue: messageName) else {
            return super.messageHandlerFor(messageName)
        }
        switch websiteAutofillMessageName {
        case .getSelectedCredentials: return getSelectedCredentials
        case .showAutofillParent: return showAutofillParent
        case .closeAutofillParent: return closeAutofillParent
        }
    }

    func showAutofillParent(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let left = dict["inputLeft"] as? CGFloat,
              let top = dict["inputTop"] as? CGFloat,
              let height = dict["inputHeight"] as? CGFloat,
              let width = dict["inputWidth"] as? CGFloat,
              let wasFromClick = dict["wasFromClick"] as? Bool,
              let serializedInputContext = dict["serializedInputContext"] as? String,
              let currentOverlayTab = currentOverlayTab else {
                  replyHandler(nil)
                  return
              }
        if !wasFromClick {
            // Click isn't relevant to the calculation for focuses
            clickPoint = nil
            // Ignore focus events in frames as the position is wrong
            if !message.isMainFrame {
                replyHandler(nil)
                return
            }
        }
        // Sets the last message host, so we can check when it messages back
        lastOpenHost = hostProvider.hostForMessage(message)
        if passwordImportDelegate?.autofillUserScriptShouldDisplayOverlay(serializedInputContext, for: hostForMessage(message)) != true {
            replyHandler(nil)
            return
        }

        currentOverlayTab.websiteAutofillUserScript(self,
                                                    willDisplayOverlayAtClick: clickPoint,
                                                    serializedInputContext: serializedInputContext,
                                                    inputPosition: CGRect(x: left, y: top, width: width, height: height))
        replyHandler(nil)
    }

    func closeAutofillParent(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        close()
        replyHandler(nil)
    }

    internal func close() {
        guard let currentOverlayTab = currentOverlayTab else { return }
        currentOverlayTab.websiteAutofillUserScriptCloseOverlay(self)
        selectedDetailsData = nil
        lastOpenHost = nil
    }

    /// Called from the child autofill to return referenced credentials
    func getSelectedCredentials(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        var response = GetSelectedCredentialsResponse(type: CredentialsResponse.none)

        let emailSignedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        if previousEmailSignedIn == nil {
            previousEmailSignedIn = emailSignedIn
        }
        let hasEmailSignedInStateChanged = previousEmailSignedIn != emailSignedIn
        let inContextEmailSignupPromptDismissedPermanentlyAt: Double? = emailDelegate?.autofillUserScriptDidRequestInContextPromptValue(self)
        let hasIncontextSignupStateChanged = previousIncontextSignupPermanentlyDismissedAt != inContextEmailSignupPromptDismissedPermanentlyAt

        if hasEmailSignedInStateChanged || hasIncontextSignupStateChanged {
            previousIncontextSignupPermanentlyDismissedAt = inContextEmailSignupPromptDismissedPermanentlyAt
            previousEmailSignedIn = emailSignedIn
            response = GetSelectedCredentialsResponse(type: CredentialsResponse.state)

        } else if lastOpenHost == nil || message.messageHost != lastOpenHost {
            response = GetSelectedCredentialsResponse(type: CredentialsResponse.stop)

        } else if let selectedDetailsData = selectedDetailsData {
            self.selectedDetailsData = nil
            response = GetSelectedCredentialsResponse(type: CredentialsResponse.ok,
                                                      data: selectedDetailsData.data,
                                                      configType: selectedDetailsData.configType)
        }

        if let json = try? JSONEncoder().encode(response),
           let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
        }
    }
}

extension WebsiteAutofillUserScript: OverlayAutofillUserScriptDelegate {
    public var overlayAutofillUserScriptLastOpenHost: String? {
        return lastOpenHost
    }

    public func overlayAutofillUserScriptClose(_ overlayAutofillUserScript: OverlayAutofillUserScript) {
        close()
    }

    public func overlayAutofillUserScript(_ overlayAutofillUserScript: OverlayAutofillUserScript,
                                          messageSelectedCredential: [String: String],
                                          _ configType: String) {
        guard let currentOverlayTab = currentOverlayTab else { return }
        currentOverlayTab.websiteAutofillUserScriptCloseOverlay(self)
        selectedDetailsData = SelectedDetailsData(data: messageSelectedCredential, configType: configType)
    }
}
