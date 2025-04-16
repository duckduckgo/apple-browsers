//
//  UserScriptMessagingSchema.swift
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

/// Fire-and-forget notifications from the user script
///
/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.NotificationMessage.html
public struct NotificationMessage {
    public let context: String
    public let featureName: String
    public let method: String
    public let params: Any
}

/// A RequestMessage is just a NotificationMessage but with an 'id' field
/// The presence of the 'id' field indicates that a response is expected
///
/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.RequestMessage.html
public struct RequestMessage {
    public let context: String
    public let featureName: String
    public let id: String
    public let method: String
    public let params: Any
}

/// Sent in response to a `RequestMessage`
///
/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.MessageResponse.html
public struct MessageResponse {
    public let context: String
    public let featureName: String
    public let id: String
    public let result: Encodable

    public static func toJSON(request: RequestMessage, result: Encodable) -> String? {

        // construct a 'MessageResponse' -> this is done to verify the types against the schema
        let res = MessageResponse(
            context: request.context,
            featureName: request.featureName,
            id: request.id,
            result: result
        )

        // I added this because I couldn't figure out the generic/recursive Encodable
        let dictionary: [String: Encodable] = [
            "context": res.context,
            "featureName": res.featureName,
            "id": res.id,
            "result": res.result
        ]

        return GenericJSONOutput.toJSON(dict: dictionary)
    }
}

/// Like a MessageResponse, except it has a 'MessageError' instead of a result
///
/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.MessageResponse.html
public struct MessageErrorResponse: Encodable {
    public let context: String
    public let featureName: String
    public let id: String
    public let error: MessageError

    public static func forRequest(request: RequestMessage, error: ResponseError) -> Self {
        MessageErrorResponse(context: request.context,
                             featureName: request.featureName,
                             id: request.id,
                             error: MessageError(message: error.localizedDescription))
    }

    public func toJSON() -> String {
        // swiftlint:disable:next force_try
        let jsonData = try! JSONEncoder().encode(self)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return jsonString
    }
}

public enum ResponseError: Error {
    case missingEncodableResult
    case jsonEncodingFailed
    case otherError(Error)
}

extension ResponseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingEncodableResult:
            return "could not access encodable result"
        case .jsonEncodingFailed:
            return "could not convert result to json"
        case .otherError(let error):
            return error.localizedDescription
        }
    }
}

/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.MessageError.html
public struct MessageError: Encodable {
    public let message: String
}

/// Use this format to push data into UserScript
///
/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging_Schema.SubscriptionEvent.html
public struct SubscriptionEvent {
    public let context: String
    public let featureName: String
    public let subscriptionName: String
    public let params: Encodable

    public func toJSON() -> String? {

        // I added this because I couldn't figure out the generic/recursive Encodable
        let dictionary: [String: Encodable] = [
            "context": self.context,
            "featureName": self.featureName,
            "subscriptionName": self.subscriptionName,
            "params": self.params
        ]

        return GenericJSONOutput.toJSON(dict: dictionary)
    }

    public static func toJS(context: String, featureName: String, subscriptionName: String, params: Encodable) -> String? {

        let res = SubscriptionEvent(context: context, featureName: featureName, subscriptionName: subscriptionName, params: params)
        guard let json = res.toJSON() else {
            assertionFailure("Could not convert a SubscriptionEvent to JSON")
            return nil
        }

        return """
           (() => {
              if (!('\(res.subscriptionName)' in window)) {
                 console.warn("missing '\(res.subscriptionName)'", \(json))
              } else {
                  window.\(res.subscriptionName)?.(\(json));
              }
           })();
           """
    }
}

/// https://duckduckgo.github.io/content-scope-scripts/classes/Messaging.WebkitMessagingConfig.html
public struct WebkitMessagingConfig: Encodable {
    let webkitMessageHandlerNames: [String]
    let secret: String
    var hasModernWebkitAPI: Bool
}

// helper types for nested JSON output (please remove if there's a better way
struct GenericJSONOutput: Encodable {
    let dict: [String: Encodable]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in dict {
            let codingKey = AnyCodingKey(stringValue: key)!
            try container.encode(value, forKey: codingKey)
        }
    }

    static func toJSON(dict: [String: Encodable]) -> String? {
        let myData = GenericJSONOutput(dict: dict)
        let encoder = JSONEncoder()

        guard let jsonData = try? encoder.encode(myData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return jsonString
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) { nil }
}
