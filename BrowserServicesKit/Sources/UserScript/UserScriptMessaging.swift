//
//  UserScriptMessaging.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import WebKit
import Combine
import Common
import os.log

/// A protocol to implement if you want to opt-in to centralised messaging.
///
/// For example, a feature that contains a Javascript implementation in C-S-S
/// can conduct 2-way communication between the JS and Native layer.
///
public protocol Subfeature {
    /// This represents a single handler. Features can register multiple handlers.
    ///
    /// The first part, `Any` represents the 'params' field of either RequestMessage or
    /// NotificationMessage and can be easily converted into a type of your choosing.
    ///
    /// The second part is the original WKScriptMessage
    ///
    /// The response can be any Encodable value - it will be serialized into
    /// the `result` field of [MessageResponse](https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.MessageResponse.html#result)
    typealias Handler = (_ params: Any, _ original: WKScriptMessage) async throws -> Encodable?

    /// This gives a feature the opportunity to select it's own handler on a
    /// call-by-call basis. The 'method' key is present on `RequestMessage` & `NotificationMessage`
    func handler(forMethodNamed methodName: String) -> Handler?

    /// This allows the feature to be selective about which domains/origins it accepts messages from
    var messageOriginPolicy: MessageOriginPolicy { get }

    /// The top-level name of the feature. For example, if Duck Player was delivered through C-S-S, the
    /// "featureName" would still be "duckPlayer" and the "context" would be related to the shared UserScript, in this
    /// case that's "contentScopeScripts"
    ///
    /// For example:
    /// context: "contentScopeScripts"
    /// featureName: "duckPlayer"
    /// method: "setUserValues"
    /// params: "..."
    /// id: "abc"
    ///
    var featureName: String { get }

    /// Subfeatures may sometime need access to the message broker - for example to push messages into the page
    var broker: UserScriptMessageBroker? { get set }
    func with(broker: UserScriptMessageBroker)
}

extension Subfeature {
    /// providing a blank implementation since not all features will need this
    public func with(broker: UserScriptMessageBroker) {
        // nothing
    }
}

public protocol UserScriptMessaging: UserScript {
    var broker: UserScriptMessageBroker { get }
}

extension UserScriptMessaging {
    public func registerSubfeature(delegate: Subfeature) {
        delegate.with(broker: broker)
        broker.registerSubfeature(delegate: delegate)
    }
}

/// The message broker just holds references to instances and distributes messages
/// to them. There would be exactly 1 `UserScriptMessageBroker` per UserScript
public final class UserScriptMessageBroker: NSObject {

    public let hostProvider: UserScriptHostProvider
    public let generatedSecret: String = UUID().uuidString

    /// A value used to differentiate entire categories of messages. For example
    /// ContentScopeScripts would have a single 'context', but then will have multiple
    /// sub-features.
    public let context: String
    public let requiresRunInPageContentWorld: Bool

    /// We determine which feature should receive a given message
    /// based on this
    var callbacks: [String: Subfeature] = [:]

    public init(context: String,
                hostProvider: UserScriptHostProvider = SecurityOriginHostProvider(),
                requiresRunInPageContentWorld: Bool = false
    ) {
        self.context = context
        self.hostProvider = hostProvider
        self.requiresRunInPageContentWorld = requiresRunInPageContentWorld
    }

    public func registerSubfeature(delegate: Subfeature) {
        callbacks[delegate.featureName] = delegate
    }

    public func messagingConfig() -> WebkitMessagingConfig {
        let config = WebkitMessagingConfig(
                webkitMessageHandlerNames: [context],
                secret: generatedSecret,
                hasModernWebkitAPI: true
        )
        return config
    }

    public func push(method: String, params: Encodable?, for delegate: Subfeature, into webView: WKWebView) {
        guard let js = SubscriptionEvent.toJS(
                context: context,
                featureName: delegate.featureName,
                subscriptionName: method,
                params: params ?? [:] as [String: String]
        )
        else {
            return
        }
        if #available(macOS 11.0, iOS 14.0, *) {
            DispatchQueue.main.async {
                if !self.requiresRunInPageContentWorld {
                    webView.evaluateJavaScript(js, in: nil, in: WKContentWorld.defaultClient)
                } else {
                    webView.evaluateJavaScript(js)
                }
            }
        }
    }

    public enum Action {
        case respond(handler: Subfeature.Handler, request: RequestMessage)
        case notify(handler: Subfeature.Handler, notification: NotificationMessage)
        case error(BrokerError)
    }

    /// Convert incoming messages, into an Action.
    ///
    /// Conditions for `error`:
    ///  - does not contain `featureName`, `context` or `method`
    ///  - delegate not found for `featureName`
    ///  - origin not supported, due to a feature's configuration
    ///  - delegate failed to provide a handler
    ///
    /// Conditions for `respond`
    ///  - no errors
    ///  - contains an `id`
    ///
    /// Conditions for `notify`
    ///  - no errors
    ///  - does NOT contain an `id`
    public func messageHandlerFor(_ message: WKScriptMessage) -> Action {

        /// first, check that the incoming message is roughly in the correct shape
        guard let dict = message.messageBody as? [String: Any],
              let featureName = dict["featureName"] as? String,
              let context = dict["context"] as? String,
              let method = dict["method"] as? String
        else {
            return .error(.invalidParams)
        }

        /// Now try to match the message to a registered delegate
        guard let delegate = callbacks[featureName] else {
            return .error(.notFoundFeature(featureName))
        }

        /// Check if the selected delegate accepts messages from this origin
        guard delegate.messageOriginPolicy.isAllowed(hostProvider.hostForMessage(message)) else {
            return .error(.policyRestriction)
        }

        /// Now ask the delegate to provide the handler
        guard let handler = delegate.handler(forMethodNamed: method) else {
            return .error(.notFoundHandler(feature: featureName, method: method))
        }

        /// just send empty params if absent
        var methodParams: Any = [String: Any]()
        if let params = dict["params"] {
            methodParams = params
        }

        /// if the incoming message had an 'id' field, it requires a response
        if let id = dict["id"] as? String {

            let incoming = RequestMessage(context: context, featureName: featureName, id: id, method: method, params: methodParams)

            /// other we can respond through the reply handler as normal
            return .respond(handler: handler, request: incoming)
        }

        /// If we get this far, we are confident the message was in the correct format
        /// but we don't think it requires a response. Therefor we treat it as a fire-and-forget notification
        let notification = NotificationMessage(context: context, featureName: featureName, method: method, params: methodParams)
        return .notify(handler: handler, notification: notification)
    }

    /// Perform the side-effect described in an action
    public func execute(action: Action, original: WKScriptMessage) async throws -> String {
        switch action {
            /// for `notify` we just need to execute the handler and continue
            /// we **do not** forward any errors to the client
            /// As far as the client is concerned, a `notification` is fire-and-forget
        case .notify(let handler, let notification):
            do {
                _=try await handler(notification.params, original)
            } catch {
                Logger.general.error("UserScriptMessaging: unhandled exception \(error.localizedDescription, privacy: .public)")
            }
            return "{}"

            /// Here the client will be expecting a response, so we always to produce one
            /// We catch errors from handlers so that we can forward the response to clients with the correct context
            ///
            /// Most of the logic here is around ensuring we send either `result` or `error` in the response
            /// Since that's how the Javascript side determines if the request was successful or not.
        case .respond(let handler, let request):
            do {
                let encodableResponse = try await handler(request.params, original)

                // handle an error
                guard let result = encodableResponse else {
                    let response = MessageErrorResponse.forRequest(request: request, error: .missingEncodableResult).toJSON()
                    return response
                }

                // send the result
                if let response = MessageResponse.toJSON(request: request, result: result) {
                    return response
                }

                let response = MessageErrorResponse.forRequest(request: request, error: .jsonEncodingFailed).toJSON()
                return response

            } catch {
                let response = MessageErrorResponse.forRequest(request: request, error: .otherError(error)).toJSON()
                return response
            }

            /// We re-throw errors here to let consumers forward them as needed.
            ///
            /// Errors here are different to those caught in `.respond` above, because they are not
            /// always tied to a response. They could be relating the incoming payload being incorrect etc.
        case .error(let error):
            let error = NSError(domain: "UserScriptMessaging", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
            throw error
        }
    }
}

public enum BrokerError: Error {
    case invalidParams
    case notFoundFeature(String)
    case notFoundHandler(feature: String, method: String)
    case policyRestriction
}

extension BrokerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidParams:
            return "The incoming message was not valid - one or more of 'featureName', 'method'  or 'context' was missing"
        case .notFoundFeature(let feature):
            return "feature named `\(feature)` was not found"
        case .notFoundHandler(let feature, let method):
            return "the incoming message is ignored because the feature `\(feature)` couldn't provide a handler for method `\(method)`"
        case .policyRestriction:
            return "invalid origin"
        }
    }
}

/// An explicit format for specifying how a hostname should be matched
public enum HostnameMatchingRule {
    case etldPlus1(hostname: String)
    case exact(hostname: String)

    public static func makeExactRule(for url: URL) -> HostnameMatchingRule? {
        guard let host = url.host else { return nil }

        if let port = url.port, port > 0 {
            return .exact(hostname: host + ":\(port)")
        } else {
            return .exact(hostname: host)
        }
    }
}

/// Force consumers to be explicit about the difference between accepting messages
/// from 'all domains' vs 'only a subset of domains'
public enum MessageOriginPolicy {
    case all
    case only(rules: [HostnameMatchingRule])

    public func isAllowed(_ origin: String) -> Bool {
        switch self {
        case .all: return true
        case .only(let allowed):
            return allowed.contains { allowed in
                switch allowed {
                    /// exact match
                case .exact(hostname: let hostname):
                    return hostname == origin
                    /// etldPlus1, like duckduckgo.com to match dev.duckduckgo.com + duckduckgo.com
                case .etldPlus1:
                    return false // todo - this isn't used yet!
                }
            }
        }
    }
}
