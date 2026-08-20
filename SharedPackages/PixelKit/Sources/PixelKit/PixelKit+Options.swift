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

    /// How a pixel request is shaped, as opposed to what the pixel *is*.
    ///
    /// `event` and `frequency` stay as parameters on `fire` because they describe the telemetry
    /// itself. Everything here describes the outgoing request, and is defaulted, so the common
    /// call reads `fire(event)` or `fire(event, frequency: .daily)` with no options in sight.
    public struct Options: Equatable, Sendable {

        /// HTTP headers for the request.
        ///
        /// Note this *replaces* the instance's `defaultHeaders` rather than merging with them: see
        /// `fire(pixelNamed:)`, which does `headers ?? defaultHeaders`. Leave it `nil` (the default)
        /// to send `defaultHeaders`. Long-standing PixelKit behaviour, preserved here deliberately;
        /// whether it should merge instead is a separate question from this API reshape.
        public var headers: [String: String]?

        /// Extra query parameters merged over the event's own parameters. On key collision the
        /// value supplied here wins.
        public var additionalParameters: [String: String]?

        /// Overrides the platform prefix applied to the pixel name.
        public var namePrefix: String?

        /// Characters left unescaped when building the query string.
        public var allowedQueryReservedCharacters: CharacterSet?

        /// Whether to append the `appVersion` parameter.
        public var includeAppVersionParameter: Bool

        /// Whether the platform name prefix is enforced.
        ///
        /// Note the polarity: this replaces the previous `doNotEnforcePrefix`, so
        /// `doNotEnforcePrefix: true` becomes `enforcePrefix: false`.
        public var enforcePrefix: Bool

        /// Whether a failed send is persisted and replayed later. Off by default.
        ///
        /// Opting in changes what reaches the server, so it is a per-pixel decision rather than a
        /// PixelKit-wide one: a replayed pixel carries two extra parameters, `originalPixelTimestamp`
        /// (when the send first failed) and `retriedPixel`. `originalPixelTimestamp` in particular
        /// reintroduces the time-based correlation that PETAL exists to remove, so a pixel must have
        /// been privacy triaged for both parameters before it sets this.
        ///
        /// See `RetryQueue/README.md` for the mechanics.
        public var retryOnFailure: Bool

        public init(headers: [String: String]? = nil,
                    additionalParameters: [String: String]? = nil,
                    namePrefix: String? = nil,
                    allowedQueryReservedCharacters: CharacterSet? = nil,
                    includeAppVersionParameter: Bool = true,
                    enforcePrefix: Bool = true,
                    retryOnFailure: Bool = false) {
            self.headers = headers
            self.additionalParameters = additionalParameters
            self.namePrefix = namePrefix
            self.allowedQueryReservedCharacters = allowedQueryReservedCharacters
            self.includeAppVersionParameter = includeAppVersionParameter
            self.enforcePrefix = enforcePrefix
            self.retryOnFailure = retryOnFailure
        }

        // MARK: - Curated presets
        //
        // Each of these corresponds to a combination that is actually used in the codebase.
        // Combinations that nobody uses deliberately get no preset: build them with `init`, or
        // start from a preset and mutate, since this is a value type.
        //
        //     var options = PixelKit.Options.unenforcedPrefix
        //     options.additionalParameters = ["source": "menu"]

        /// Everything default: prefix enforced, app version included, nothing extra.
        public static let `default` = Options()

        /// For pixels whose names are already fully qualified and must not gain a platform prefix.
        public static let unenforcedPrefix = Options(enforcePrefix: false)

        /// For pixels that must not carry the `appVersion` parameter, such as crash reports.
        public static let withoutAppVersion = Options(includeAppVersionParameter: false)

        /// For pixels whose delivery matters enough to survive a failed send, and that have been
        /// privacy triaged for the retry parameters. See `retryOnFailure`.
        public static let withRetry = Options(retryOnFailure: true)

        /// Attaches extra query parameters.
        public static func parameters(_ parameters: [String: String]) -> Options {
            Options(additionalParameters: parameters)
        }

        /// Overrides the platform name prefix, typically with a per-platform value.
        public static func namePrefix(_ prefix: String) -> Options {
            Options(namePrefix: prefix)
        }

        /// Extra parameters plus a name prefix override.
        public static func parameters(_ parameters: [String: String], namePrefix: String) -> Options {
            Options(additionalParameters: parameters, namePrefix: namePrefix)
        }
    }

    /// Whether a `fire` call actually sent a request.
    public enum FireResult: Equatable, Sendable {

        /// A request was sent.
        case sent

        /// No request was sent because the event's `Frequency` rules suppressed it, for example a
        /// `.daily` pixel already fired today. This is a normal outcome, not a failure.
        case suppressed
    }
}
