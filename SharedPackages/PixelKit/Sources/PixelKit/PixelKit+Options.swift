//
//  PixelKit+Options.swift
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

import Foundation

extension PixelKit {

    /// Per-request settings: headers, parameters and delivery.
    ///
    /// Nothing here affects the pixel's name — see `PixelKit.Event.namePrefix` and
    /// `platformSuffixPolicy` for that. Every property is defaulted, so most calls need no options.
    public struct Options: Equatable, Sendable {

        /// HTTP headers for the request. Replaces the instance's `defaultHeaders`; they are not
        /// merged. Leave `nil` to send `defaultHeaders`.
        public var headers: [String: String]?

        /// Extra query parameters, merged over the event's own. These win on key collision.
        public var additionalParameters: [String: String]?

        /// Characters left unescaped when building the query string.
        public var allowedQueryReservedCharacters: CharacterSet?

        /// Whether to append the `appVersion` parameter.
        public var includeAppVersionParameter: Bool

        /// Persists a failed send and replays it later. Off by default.
        ///
        /// A replayed pixel carries `originalPixelTimestamp` and `retriedPixel`. Both must be
        /// privacy triaged for the pixel before opting in. See `RetryQueue/README.md`.
        public var retryOnFailure: Bool

        /// Appends the `atb` parameter, carrying the user's ATB cohort with its variant suffix.
        /// Off by default, and must be privacy triaged for the pixel before opting in.
        ///
        /// Requires a `PixelKitParameterProviding` injected at `setUp`; without one the parameter
        /// is omitted. With a provider that has no ATB yet it is sent empty.
        public var includeATB: Bool

        public init(headers: [String: String]? = nil,
                    additionalParameters: [String: String]? = nil,
                    allowedQueryReservedCharacters: CharacterSet? = nil,
                    includeAppVersionParameter: Bool = true,
                    retryOnFailure: Bool = false,
                    includeATB: Bool = false) {
            self.headers = headers
            self.additionalParameters = additionalParameters
            self.allowedQueryReservedCharacters = allowedQueryReservedCharacters
            self.includeAppVersionParameter = includeAppVersionParameter
            self.retryOnFailure = retryOnFailure
            self.includeATB = includeATB
        }

        // MARK: - Presets
        //
        // Presets cover the combinations in use. For anything else use `init`, or mutate a preset:
        //
        //     var options = PixelKit.Options.withATB
        //     options.additionalParameters = ["source": "menu"]

        /// App version included, nothing else.
        public static let `default` = Options()

        /// For pixels that must not carry the `appVersion` parameter, such as crash reports.
        public static let withoutAppVersion = Options(includeAppVersionParameter: false)

        /// See `retryOnFailure`.
        public static let withRetry = Options(retryOnFailure: true)

        /// See `includeATB`.
        public static let withATB = Options(includeATB: true)

        /// Attaches extra query parameters.
        public static func parameters(_ parameters: [String: String]) -> Options {
            Options(additionalParameters: parameters)
        }

    }

    /// Whether a `fire` call actually sent a request.
    public enum FireResult: Equatable, Sendable {

        /// A request was sent.
        case sent

        /// No request was sent: the event's `Frequency` rules suppressed it, e.g. a `.daily` pixel
        /// already fired today. A normal outcome, not a failure.
        case suppressed
    }
}
