//
//  PixelKit.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import os.log
import Common

public final class PixelKit {
    /// `true` if a request is fired, `false` otherwise
    public typealias CompletionBlock = (Bool, (any Error)?) -> Void

    /// The frequency with which a pixel is sent to our endpoint.
    public enum Frequency {
        /// The default frequency for pixels. This fires pixels with the event names as-is.
        case standard

        /// Sent only once ever (based on pixel name only.) The timestamp for this pixel is stored.
        /// Note: This is the only pixel that MUST end with `_u`, Name for pixels of this type must end with if it doesn't an assertion is fired.
        case uniqueByName

        /// Sent only once ever (based on pixel name AND parameters). The timestamp for this pixel is stored.
        case uniqueByNameAndParameters

        /// Sent once per day. The last timestamp for this pixel is stored and compared to the current date. Pixels of this type will have `_daily` appended to their name.
        case daily

        /// Sent once per day with a `_daily` suffix, in addition to every time it is called with a `_count` suffix.
        /// This means a pixel will get sent twice the first time it is called per-day, and subsequent calls that day will only send the `_count` variant.
        /// This is useful in situations where pixels receive spikes in volume, as the daily pixel can be used to determine how many users are actually affected.
        case dailyAndCount

        /// Sent once per day with a `_daily` suffix, in addition to every time it is called with the default name (no suffix).
        /// This means a pixel will get sent twice the first time it is called per-day, and subsequent calls that day will only send the pixel with a standard name.
        /// This is useful in situations where pixels receive spikes in volume, as the daily pixel can be used to determine how many users are actually affected.
        case dailyAndStandard

        /// [Legacy] Used in Pixel.fire(...) as .unique but without the `_u` requirement in the name
        case legacyInitial

        /// [Legacy] Used in Pixel.fire(...) as .daily but without the `_d` automatically added to the name
        case legacyDailyNoSuffix

        /// [Legacy] Sent once per day. The last timestamp for this pixel is stored and compared to the current date. Pixels of this type will have `_d` appended to their name.
        case legacyDaily

        /// [Legacy] Sent once per day with a `_d` suffix, in addition to every time it is called with a `_c` suffix.
        /// This means a pixel will get sent twice the first time it is called per-day, and subsequent calls that day will only send the `_c` variant.
        /// This is useful in situations where pixels receive spikes in volume, as the daily pixel can be used to determine how many users are actually affected.
        case legacyDailyAndCount

        fileprivate var description: String {
            switch self {
            case .standard:
                "Standard"
            case .uniqueByName:
                "Unique"
            case .daily:
                "Daily"
            case .dailyAndCount:
                "Daily and Count"
            case .dailyAndStandard:
                "Daily and Standard"
            case .uniqueByNameAndParameters:
                "Unique By Name And Parameters"
            case .legacyInitial:
                "Legacy Initial"
            case .legacyDaily:
                "Legacy Daily"
            case .legacyDailyAndCount:
                "Legacy Daily and Count"
            case .legacyDailyNoSuffix:
                "Legacy Daily No Suffix"
            }
        }
    }

    public enum Header {
        public static let acceptEncoding = "Accept-Encoding"
        public static let acceptLanguage = "Accept-Language"
        public static let userAgent = "User-Agent"
        public static let ifNoneMatch = "If-None-Match"
        public static let moreInfo = "X-DuckDuckGo-MoreInfo"
        public static let client = "X-DuckDuckGo-Client"
    }

    public enum Source: String {
        case macStore = "browser-appstore"
        case macDMG = "browser-dmg"
        case iOS = "phone"
        case iPadOS = "tablet"
    }

    /// A closure typealias to request sending pixels through the network.
    public typealias FireRequest = (
        _ pixelName: String,
        _ headers: [String: String],
        _ parameters: [String: String],
        _ allowedQueryReservedCharacters: CharacterSet?,
        _ callBackOnMainThread: Bool,
        _ onComplete: @escaping CompletionBlock) -> Void

    public typealias Event = PixelKitEvent
    public static let duckDuckGoMorePrivacyInfo = URL(string: "https://help.duckduckgo.com/duckduckgo-help-pages/privacy/atb/")!
    private let defaults: UserDefaults

    private let logger = Logger(subsystem: "PixelKit", category: "PixelKit")

    private static let defaultDailyPixelCalendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let weeksToCoalesceCohort = 6
    private let dateGenerator: () -> Date
    public private(set) static var shared: PixelKit?
    private let appVersion: String
    private let defaultHeaders: [String: String]
    private let fireRequest: FireRequest
    private var dryRun: Bool
    private let source: String?
    private let pixelCalendar: Calendar

    /// Sets up PixelKit for the entire app.
    ///
    /// - Parameters:
    /// - `dryRun`: if `true`, simulate requests and "send" them at an accelerated rate (once every 2 minutes instead of once a day)
    /// - `source`: if set, adds a `pixelSource` parameter to the pixel call; this can be used to specify which target is sending the pixel
    /// - `fireRequest`: this is not triggered when `dryRun` is `true`
    public static func setUp(dryRun: Bool = false,
                             appVersion: String,
                             source: String? = nil,
                             defaultHeaders: [String: String],
                             dailyPixelCalendar: Calendar? = nil,
                             dateGenerator: @escaping () -> Date = Date.init,
                             defaults: UserDefaults,
                             fireRequest: @escaping FireRequest) {
        shared = PixelKit(dryRun: dryRun,
                          appVersion: appVersion,
                          source: source,
                          defaultHeaders: defaultHeaders,
                          dailyPixelCalendar: dailyPixelCalendar,
                          dateGenerator: dateGenerator,
                          defaults: defaults,
                          fireRequest: fireRequest)
    }

    public static func tearDown() {
        shared = nil
    }

    // MARK: - Initialisation

    public init(dryRun: Bool,
                appVersion: String,
                source: String? = nil,
                defaultHeaders: [String: String],
                dailyPixelCalendar: Calendar? = nil,
                dateGenerator: @escaping () -> Date = Date.init,
                defaults: UserDefaults,
                fireRequest: @escaping FireRequest) {

        self.dryRun = dryRun
        self.appVersion = appVersion
        self.source = source
        self.defaultHeaders = defaultHeaders
        self.pixelCalendar = dailyPixelCalendar ?? Self.defaultDailyPixelCalendar
        self.dateGenerator = dateGenerator
        self.defaults = defaults
        self.fireRequest = fireRequest
        logger.debug("👾 PixelKit initialised: dryRun: \(self.dryRun, privacy: .public) appVersion: \(self.appVersion, privacy: .public) source: \(self.source ?? "-", privacy: .public) defaultHeaders: \(self.defaultHeaders, privacy: .public) pixelCalendar: \(self.pixelCalendar, privacy: .public)")
    }

    // MARK: - Public Fire

    public func fire(_ event: Event,
                     frequency: Frequency = .standard,
                     withHeaders headers: [String: String]? = nil,
                     withAdditionalParameters params: [String: String]? = nil,
                     withDDGError error: (any DDGError)? = nil,
                     withNamePrefix namePrefix: String? = nil,
                     allowedQueryReservedCharacters: CharacterSet? = nil,
                     includeAppVersionParameter: Bool = true,
                     includePixelSourceParameter: Bool = true,
                     onComplete: @escaping CompletionBlock = { _, _ in }) {

        let pixelName = prefixedAndSuffixedName(for: event, namePrefix: namePrefix)

        if !dryRun {
            if frequency == .daily, pixelHasBeenFiredToday(pixelName) {
                onComplete(false, nil)
                return
            } else if frequency == .uniqueByName, pixelHasBeenFiredEver(pixelName) {
                onComplete(false, nil)
                return
            }
        }

        let newParams: [String: String]?
        switch (event.parameters, params) {
        case (.some(let parameters), .none):
            newParams = parameters
        case (.none, .some(let parameters)):
            newParams = parameters
        case (.some(let params1), .some(let params2)):
            newParams = params1.merging(params2) { $1 }
        case (.none, .none):
            newParams = nil
        }

        if !dryRun, let newParams {
            let pixelNameAndParams = pixelName + newParams.toString()
            if frequency == .uniqueByNameAndParameters, pixelHasBeenFiredEver(pixelNameAndParams) {
                onComplete(false, nil)
                return
            }
        }

        let newError: (any DDGError)?

        /*
         We have 2 options here:
         - The event is a PixelKitEvent: We handle the error passed in this call
         - The event is a PixelKitEventV2: We only consider the error in the returned by the PixelKitEventV2 `var error` and assert if an error is also passed to this function
         */

        if let event = event as? PixelKitEventV2,
           let eventError = event.error {

            // For v2 events we only consider the error specified in the event
            // and purposely ignore the parameter in this call.
            // This is to encourage moving the error over to the protocol error
            // instead of still relying on the parameter of this call.

            guard error == nil else {
                let throwingError = PixelKitError.doubleError
                assertionFailure(throwingError.description)
                logger.error("\(throwingError.description, privacy: .public)")
                onComplete(false, throwingError)
                return
            }

            if let ddgError = eventError as? any DDGError {
                newError = ddgError
            } else {
                newError = DDGErrorPixelKitWrapper.wrapper(eventError)
            }
        } else {
            newError = error
        }

        fire(pixelNamed: pixelName,
             frequency: frequency,
             withHeaders: headers,
             withAdditionalParameters: newParams,
             withDDGError: newError,
             allowedQueryReservedCharacters: allowedQueryReservedCharacters,
             includeAppVersionParameter: includeAppVersionParameter,
             includePixelSourceParameter: includePixelSourceParameter,
             onComplete: onComplete)
    }

    @available(*, deprecated, message: "Use of generic `withError: Error` in PixelKit is deprecated. Use `withDDGError: DDGError` instead.")
    public func fire(_ event: Event,
                     frequency: Frequency = .standard,
                     withHeaders headers: [String: String]? = nil,
                     withAdditionalParameters params: [String: String]? = nil,
                     withError error: Error? = nil,
                     withNamePrefix namePrefix: String? = nil,
                     allowedQueryReservedCharacters: CharacterSet? = nil,
                     includeAppVersionParameter: Bool = true,
                     includePixelSourceParameter: Bool = true,
                     onComplete: @escaping CompletionBlock = { _, _ in }) {
        let wrappedError = error != nil ? DDGErrorPixelKitWrapper.wrapper(error) : nil
        fire(event, frequency: frequency,
             withHeaders: headers,
             withAdditionalParameters: params,
             withDDGError: wrappedError,
             withNamePrefix: namePrefix,
             allowedQueryReservedCharacters: allowedQueryReservedCharacters,
             includeAppVersionParameter: includeAppVersionParameter,
             includePixelSourceParameter: includePixelSourceParameter,
             onComplete: onComplete)
    }

    public static func fire(_ event: Event,
                            frequency: Frequency = .standard,
                            withHeaders headers: [String: String] = [:],
                            withAdditionalParameters parameters: [String: String]? = nil,
                            withDDGError error: (any DDGError)? = nil,
                            withNamePrefix namePrefix: String? = nil,
                            allowedQueryReservedCharacters: CharacterSet? = nil,
                            includeAppVersionParameter: Bool = true,
                            includePixelSourceParameter: Bool = true,
                            onComplete: @escaping CompletionBlock = { _, _ in }) {

        Self.shared?.fire(event,
                          frequency: frequency,
                          withHeaders: headers,
                          withAdditionalParameters: parameters,
                          withDDGError: error,
                          withNamePrefix: namePrefix,
                          allowedQueryReservedCharacters: allowedQueryReservedCharacters,
                          includeAppVersionParameter: includeAppVersionParameter,
                          includePixelSourceParameter: includePixelSourceParameter,
                          onComplete: onComplete)
    }

    enum DDGErrorPixelKitWrapper: DDGError {
        case wrapper(Error?)

        var underlyingError: (any Error)? {
            switch self {
            case .wrapper(let error):
                return error
            }
        }

        var description: String {
            switch self {
            case .wrapper(let error):
                return "Wrapper of error:\(String(describing: error))"
            }
        }

        var errorDomain: String { "com.duckduckgo.PixelKit.DDGErrorPixelKitWrapper" }

        var errorCode: Int {
            switch self {
            case .wrapper:
                return 0
            }
        }

        static func == (lhs: PixelKit.DDGErrorPixelKitWrapper, rhs: PixelKit.DDGErrorPixelKitWrapper) -> Bool {
            switch (lhs, rhs) {
            case (.wrapper(let lhs), .wrapper(let rhs)):
                return String(describing: lhs) == String(describing: rhs)
            }
        }
    }

    @available(*, deprecated, message: "Use of generic `withError: Error` in PixelKit is deprecated. Use `withDDGError: DDGError` instead.")
    public static func fire(_ event: Event,
                            frequency: Frequency = .standard,
                            withHeaders headers: [String: String] = [:],
                            withAdditionalParameters parameters: [String: String]? = nil,
                            withError error: Error? = nil,
                            withNamePrefix namePrefix: String? = nil,
                            allowedQueryReservedCharacters: CharacterSet? = nil,
                            includeAppVersionParameter: Bool = true,
                            includePixelSourceParameter: Bool = true,
                            onComplete: @escaping CompletionBlock = { _, _ in }) {

        let wrappedError = error != nil ? DDGErrorPixelKitWrapper.wrapper(error) : nil
        Self.shared?.fire(event,
                          frequency: frequency,
                          withHeaders: headers,
                          withAdditionalParameters: parameters,
                          withDDGError: wrappedError,
                          withNamePrefix: namePrefix,
                          allowedQueryReservedCharacters: allowedQueryReservedCharacters,
                          includeAppVersionParameter: includeAppVersionParameter,
                          includePixelSourceParameter: includePixelSourceParameter,
                          onComplete: onComplete)
    }

    // MARK: - Private Fire

    private func fire(pixelNamed pixelName: String,
                      frequency: Frequency,
                      withHeaders headers: [String: String]?,
                      withAdditionalParameters params: [String: String]?,
                      withDDGError error: (any DDGError)?,
                      allowedQueryReservedCharacters: CharacterSet?,
                      includeAppVersionParameter: Bool,
                      includePixelSourceParameter: Bool,
                      onComplete: @escaping CompletionBlock) {

        var newParams = params ?? [:]
        if includeAppVersionParameter { newParams[Parameters.appVersion] = appVersion }
        if includePixelSourceParameter, let source { newParams[Parameters.pixelSource] = source }
        if let error { newParams.appendErrorPixelParams(error: error) }

        #if DEBUG
            newParams[Parameters.test] = Values.test
        #endif

        var headers = headers ?? defaultHeaders
        headers[Header.moreInfo] = "See " + Self.duckDuckGoMorePrivacyInfo.absoluteString
        // Needs to be updated/generalised when fully adopted by iOS
        if let source {
            switch source {
            case Source.iOS.rawValue:
                headers[Header.client] = "iOS"
            case Source.iPadOS.rawValue:
                headers[Header.client] = "iPadOS"
            case Source.macDMG.rawValue, Source.macStore.rawValue:
                headers[Header.client] = "macOS"
            default:
                headers[Header.client] = "macOS"
            }
        }

        // The event name can't contain `.`
        reportErrorIf(pixel: pixelName, contains: ".")

        switch frequency {
        case .standard:
            handleStandardFrequency(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .uniqueByName:
            handleUnique(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .uniqueByNameAndParameters:
            handleUniqueByNameAndParameters(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .daily:
            handleDaily(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .dailyAndCount:
            handleDailyAndCount(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .dailyAndStandard:
            handleDailyAndStandard(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .legacyInitial:
            handleLegacyInitial(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .legacyDaily:
            handleLegacyDaily(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .legacyDailyAndCount:
            handleLegacyDailyAndCount(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        case .legacyDailyNoSuffix:
            handleLegacyDailyNoSuffix(pixelName, headers, newParams, allowedQueryReservedCharacters, onComplete)
        }
    }

    // MARK: -

    private func handleStandardFrequency(_ pixelName: String,
                                         _ headers: [String: String],
                                         _ params: [String: String],
                                         _ allowedQueryReservedCharacters: CharacterSet?,
                                         _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        fireRequestWrapper(pixelName, headers, params, allowedQueryReservedCharacters, true, .standard, onComplete)
    }

    private func handleLegacyInitial(_ pixelName: String,
                                     _ headers: [String: String],
                                     _ newParams: [String: String],
                                     _ allowedQueryReservedCharacters: CharacterSet?,
                                     _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        if !pixelHasBeenFiredEver(pixelName) {
            fireRequestWrapper(pixelName, headers, newParams, allowedQueryReservedCharacters, true, .legacyInitial, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .legacyInitial, parameters: newParams, skipped: true)
        }
    }

    private func handleUnique(_ pixelName: String,
                              _ headers: [String: String],
                              _ newParams: [String: String],
                              _ allowedQueryReservedCharacters: CharacterSet?,
                              _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        guard pixelName.hasSuffix("_u") else {
            assertionFailure("Unique pixel: must end with _u")
            onComplete(false, nil)
            return
        }
        if !pixelHasBeenFiredEver(pixelName) {
            fireRequestWrapper(pixelName, headers, newParams, allowedQueryReservedCharacters, true, .uniqueByName, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .uniqueByName, parameters: newParams, skipped: true)
        }
    }

    private func handleUniqueByNameAndParameters(_ pixelName: String,
                                                 _ headers: [String: String],
                                                 _ newParams: [String: String],
                                                 _ allowedQueryReservedCharacters: CharacterSet?,
                                                 _ onComplete: @escaping CompletionBlock) {
        let pixelNameAndParams = pixelName + newParams.toString()
        if !pixelHasBeenFiredEver(pixelNameAndParams) {
            fireRequestWrapper(pixelName, headers, newParams, allowedQueryReservedCharacters, true, .uniqueByNameAndParameters, onComplete)
            updatePixelLastFireDate(pixelName: pixelNameAndParams)
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .uniqueByNameAndParameters, parameters: newParams, skipped: true)
        }
    }

    private func handleDaily(_ pixelName: String,
                             _ headers: [String: String],
                             _ newParams: [String: String],
                             _ allowedQueryReservedCharacters: CharacterSet?,
                             _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily") // Because is added automatically
        if !pixelHasBeenFiredToday(pixelName) {
            fireRequestWrapper(pixelName + "_daily", headers, newParams, allowedQueryReservedCharacters, true, .daily, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName + "_daily", frequency: .daily, parameters: newParams, skipped: true)
        }
    }

    private func handleLegacyDailyNoSuffix(_ pixelName: String,
                                           _ headers: [String: String],
                                           _ newParams: [String: String],
                                           _ allowedQueryReservedCharacters: CharacterSet?,
                                           _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        if !pixelHasBeenFiredToday(pixelName) {
            fireRequestWrapper(pixelName, headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyNoSuffix, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .legacyDailyNoSuffix, parameters: newParams, skipped: true)
        }
    }

    private func handleLegacyDaily(_ pixelName: String,
                                   _ headers: [String: String],
                                   _ newParams: [String: String],
                                   _ allowedQueryReservedCharacters: CharacterSet?,
                                   _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d") // Because is added automatically
        if !pixelHasBeenFiredToday(pixelName) {
            fireRequestWrapper(pixelName + "_d", headers, newParams, allowedQueryReservedCharacters, true, .legacyDaily, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName + "_d", frequency: .legacyDaily, parameters: newParams, skipped: true)
        }
    }

    private func handleLegacyDailyAndCount(_ pixelName: String,
                                           _ headers: [String: String],
                                           _ newParams: [String: String],
                                           _ allowedQueryReservedCharacters: CharacterSet?,
                                           _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d") // Because is added automatically
        reportErrorIf(pixel: pixelName, endsWith: "_c") // Because is added automatically
        if !pixelHasBeenFiredToday(pixelName) {
            fireRequestWrapper(pixelName + "_d", headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyAndCount, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName + "_d", frequency: .legacyDailyAndCount, parameters: newParams, skipped: true)
        }

        fireRequestWrapper(pixelName + "_c", headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyAndCount, onComplete)
    }

    private func handleDailyAndCount(_ pixelName: String,
                                     _ headers: [String: String],
                                     _ newParams: [String: String],
                                     _ allowedQueryReservedCharacters: CharacterSet?,
                                     _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily") // Because is added automatically
        reportErrorIf(pixel: pixelName, endsWith: "_count") // Because is added automatically
        if !pixelHasBeenFiredToday(pixelName) {
            fireRequestWrapper(pixelName + "_daily", headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName + "_daily", frequency: .dailyAndCount, parameters: newParams, skipped: true)
        }

        fireRequestWrapper(pixelName + "_count", headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, onComplete)
    }

    private func handleDailyAndStandard(_ pixelName: String,
                                        _ headers: [String: String],
                                        _ newParams: [String: String],
                                        _ allowedQueryReservedCharacters: CharacterSet?,
                                        _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily") // Because is added automatically
        if !pixelHasBeenFiredToday(pixelName) {
            fireRequestWrapper(pixelName + "_daily", headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, onComplete)
            updatePixelLastFireDate(pixelName: pixelName)
        } else {
            printDebugInfo(pixelName: pixelName + "_daily", frequency: .dailyAndCount, parameters: newParams, skipped: true)
        }

        fireRequestWrapper(pixelName, headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, onComplete)
    }

    /// If the pixel name ends with the forbiddenString then an error is logged or an assertion failure is fired in debug
    func reportErrorIf(pixel: String, endsWith forbiddenString: String) {
        if pixel.hasSuffix(forbiddenString) {
            logger.error("Pixel \(pixel, privacy: .public) must not end with \(forbiddenString, privacy: .public)")
            assertionFailure("Pixel \(pixel) must not end with \(forbiddenString)")
        }
    }

    /// If the pixel name contains the forbiddenString then an error is logged or an assertion failure is fired in debug
    func reportErrorIf(pixel: String, contains forbiddenString: String) {
        if pixel.contains(forbiddenString) {
            logger.error("Pixel \(pixel, privacy: .public) must not contain \(forbiddenString, privacy: .public)")
            assertionFailure("Pixel \(pixel) must not contain \(forbiddenString)")
        }
    }

    private func printDebugInfo(pixelName: String, frequency: Frequency, parameters: [String: String], skipped: Bool = false) {
        let params = parameters
            .filter { key, _ in key != "test" }
            .sorted { $0.key < $1.key }

        // Sort the params before logging them in debug mode to make it easier to compare multiple subsequent calls
        let sortedParamsString = params.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        logger.debug("👾[\(frequency.description, privacy: .public)-\(skipped ? "Skipped" : "Fired", privacy: .public)] \(pixelName, privacy: .public) [\(sortedParamsString, privacy: .public)]")
    }

    private func fireRequestWrapper(
        _ pixelName: String,
        _ headers: [String: String],
        _ parameters: [String: String],
        _ allowedQueryReservedCharacters: CharacterSet?,
        _ callBackOnMainThread: Bool,
        _ frequency: Frequency,
        _ onComplete: @escaping CompletionBlock) {
            printDebugInfo(pixelName: pixelName, frequency: frequency, parameters: parameters, skipped: false)
            guard !dryRun else {
                // simulate server response time for Dry Run mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onComplete(true, nil)
                }
                return
            }
            fireRequest(pixelName, headers, parameters, allowedQueryReservedCharacters, callBackOnMainThread, onComplete)
        }

    private func prefixedAndSuffixedName(for event: Event, namePrefix: String?) -> String {

        if let pixelWithCustomPrefix = event as? PixelKitEventWithCustomPrefix {
            return pixelWithCustomPrefix.namePrefix + event.name + platformSuffix
        }

        let pixelName = (namePrefix ?? "") + event.name
        if pixelName.hasPrefix("experiment") {
            return addExperimentPlatformSuffix(to: pixelName)
        }

#if os(iOS)
        return pixelName
#else
        // Many macOS pixel names need "correcting" after the fact
        // However, we should try and move away from this approach
        // (and towards the more deliberate approach above with the prefix and experiment suffix)
        // This approach won't work for iOS as the names have a very varied set of prefixes
        if pixelName.hasPrefix("m_mac_") {
            // Can be a debug event or not, if already prefixed the name remains unchanged
            return pixelName
        } else if let debugEvent = event as? DebugEvent {
            // Is a Debug event not already prefixed
            return "m_mac_debug_\(debugEvent.name)"
        } else if let nonStandardEvent = event as? NonStandardEvent {
            // Special kind of pixel event that don't follow the standard naming conventions
            return nonStandardEvent.name
        } else {
            return "m_mac_\(pixelName)"
        }
#endif
    }

    var platformSuffix: String {
        switch source {
        case Source.iOS.rawValue:
            return "_ios_phone"
        case Source.iPadOS.rawValue:
            return "_ios_tablet"
        default:
            return ""
        }
    }

    public func addExperimentPlatformSuffix(to name: String) -> String {
        if let source {
            switch source {
            case Source.iOS.rawValue:
                return "\(name)_ios_phone"
            case Source.iPadOS.rawValue:
                return "\(name)_ios_tablet"
            case Source.macStore.rawValue, Source.macDMG.rawValue:
                return "\(name)_mac"
            default:
                return name
            }
        }
        return name
    }

    private func cohort(from cohortLocalDate: Date?, dateGenerator: () -> Date = Date.init) -> String? {
        guard let cohortLocalDate,
              let baseDate = pixelCalendar.date(from: .init(year: 2023, month: 1, day: 1)),
              let weeksSinceCohortAssigned = pixelCalendar.dateComponents([.weekOfYear], from: cohortLocalDate, to: dateGenerator()).weekOfYear,
              let assignedCohort = pixelCalendar.dateComponents([.weekOfYear], from: baseDate, to: cohortLocalDate).weekOfYear else {
            return nil
        }

        if weeksSinceCohortAssigned > Self.weeksToCoalesceCohort {
            return ""
        } else {
            return "week-" + String(assignedCohort + 1)
        }
    }

    public static func cohort(from cohortLocalDate: Date?, dateGenerator: () -> Date = Date.init) -> String {
        Self.shared?.cohort(from: cohortLocalDate, dateGenerator: dateGenerator) ?? ""
    }

    public static func pixelLastFireDate(event: Event, namePrefix: String? = nil) -> Date? {
        Self.shared?.pixelLastFireDate(event: event, namePrefix: namePrefix)
    }

    public func pixelLastFireDate(pixelName: String) -> Date? {
        var date = defaults.object(forKey: userDefaultsKeyName(forPixelName: pixelName)) as? Date
        if date == nil {
            date = defaults.object(forKey: legacyUserDefaultsKeyName(forPixelName: pixelName)) as? Date
        }
        return date
    }

    public func pixelLastFireDate(event: Event, namePrefix: String? = nil) -> Date? {
        pixelLastFireDate(pixelName: prefixedAndSuffixedName(for: event, namePrefix: namePrefix))
    }

    private func updatePixelLastFireDate(pixelName: String) {
        defaults.set(dateGenerator(), forKey: userDefaultsKeyName(forPixelName: pixelName))
    }

    private func pixelHasBeenFiredToday(_ name: String) -> Bool {
        guard !dryRun else {
            if let lastFireDate = pixelLastFireDate(pixelName: name),
               let twoMinsAgo = pixelCalendar.date(byAdding: .minute, value: -2, to: dateGenerator()) {
                return lastFireDate >= twoMinsAgo
            }

            return false
        }

        if let lastFireDate = pixelLastFireDate(pixelName: name) {
            return pixelCalendar.isDate(dateGenerator(), inSameDayAs: lastFireDate)
        }

        return false
    }

    private func pixelHasBeenFiredEver(_ name: String) -> Bool {
        pixelLastFireDate(pixelName: name) != nil
    }

    public func clearFrequencyHistoryFor(pixel: PixelKitEventV2) {
        guard let name = Self.shared?.userDefaultsKeyName(forPixelName: pixel.name) else {
            return
        }
        self.defaults.removeObject(forKey: name)
    }

    public func clearFrequencyHistoryForAllPixels() {
        for (key, _) in self.defaults.dictionaryRepresentation() {
            if key.hasPrefix(Self.storageKeyPrefixLegacy) || key.hasPrefix(Self.storageKeyPrefix) {
                self.defaults.removeObject(forKey: key)
                self.logger.debug("🚮 Removing from storage \(key, privacy: .public)")
            }
        }
    }

    static let storageKeyPrefixLegacy = "com.duckduckgo.network-protection.pixel."
    static let storageKeyPrefix = "com.duckduckgo.network-protection.pixel."

    /// Initially PixelKit was configured only for serving netP so these very specific keys were used, now PixelKit serves the entire app so we need to move away from them.
    /// NOTE: I would remove this 6 months after release
    private func legacyUserDefaultsKeyName(forPixelName pixelName: String) -> String {
        dryRun
        ? "\(Self.storageKeyPrefixLegacy)\(pixelName).dry-run"
        : "\(Self.storageKeyPrefixLegacy)\(pixelName)"
    }

    private func userDefaultsKeyName(forPixelName pixelName: String) -> String {
        return "\(Self.storageKeyPrefix)\(pixelName)\( dryRun ? ".dry-run" : "" )"
    }
}

internal extension Dictionary where Key == String, Value == String {

    mutating func appendErrorPixelParams(error: any Error) {

        let errorToProcess: Error
        if let ddgError = error as? PixelKit.DDGErrorPixelKitWrapper,
           let underlyingError = ddgError.underlyingError{
            // The first error in the chain is just a wrapper because the error passed was not a DDGError. We discard it
            errorToProcess = underlyingError
        } else {
            errorToProcess = error
        }

        var params = [String: String]()

        // DDGError
        if let ddgError = errorToProcess as? any DDGError {
            params[PixelKit.Parameters.errorCode] = String(ddgError.errorCode)
            params[PixelKit.Parameters.errorDomain] = ddgError.errorDomain

            // Add underlying errors (skip first element which is the main error itself)
            let underlyingErrors = Array(ddgError.errorsChain.dropFirst())
            var level = 0
            for underlyingError in underlyingErrors {
                let errorCodeParameterName = PixelKit.Parameters.underlyingErrorCode + (level == 0 ? "" : String(level + 1))
                let errorDomainParameterName = PixelKit.Parameters.underlyingErrorDomain + (level == 0 ? "" : String(level + 1))
                if let ddgError = underlyingError as? any DDGError {
                    params[errorCodeParameterName] = String(ddgError.errorCode)
                    params[errorDomainParameterName] = ddgError.errorDomain
                } else {
                    let nsError = underlyingError as NSError
                    params[errorCodeParameterName] = String(nsError.code)
                    params[errorDomainParameterName] = nsError.domain
                }
                level+=1
            }
        } else {
            // Standard Error
            if let errorWithUserInfo = errorToProcess as? ErrorWithPixelParameters {
                params = errorWithUserInfo.errorParameters
            }

            let nsError = errorToProcess as NSError

            params[PixelKit.Parameters.errorCode] = "\(nsError.code)"
            params[PixelKit.Parameters.errorDomain] = nsError.domain

            let underlyingErrorParameters = self.underlyingErrorParameters(for: nsError)
            params.merge(underlyingErrorParameters) { first, _ in
                return first
            }

            if let sqlErrorCode = nsError.userInfo["SQLiteResultCode"] as? NSNumber {
                params[PixelKit.Parameters.underlyingErrorSQLiteCode] = "\(sqlErrorCode.intValue)"
            }

            if let sqlExtendedErrorCode = nsError.userInfo["SQLiteExtendedResultCode"] as? NSNumber {
                params[PixelKit.Parameters.underlyingErrorSQLiteExtendedCode] = "\(sqlExtendedErrorCode.intValue)"
            }
        }

        // Merge the collected parameters into self
        self.merge(params) { _, new in new }
    }

    /// Recursive call to add underlying error information for non DDGErrors
    private func underlyingErrorParameters(for nsError: NSError, level: Int = 0) -> [String: String] {
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            let errorCodeParameterName = PixelKit.Parameters.underlyingErrorCode + (level == 0 ? "" : String(level + 1))
            let errorDomainParameterName = PixelKit.Parameters.underlyingErrorDomain + (level == 0 ? "" : String(level + 1))

            let currentUnderlyingErrorParameters = [
                errorCodeParameterName: "\(underlyingError.code)",
                errorDomainParameterName: underlyingError.domain
            ]

            // Check if the underlying error has an underlying error of its own
            let additionalParameters = underlyingErrorParameters(for: underlyingError, level: level + 1)

            return currentUnderlyingErrorParameters.merging(additionalParameters) { first, _ in
                return first // Doesn't really matter as there should be no conflict of parameters
            }
        }

        return [:]
    }
}

internal extension PixelKit {

    /// [USE ONLY FOR TESTS] Sets the shared PixelKit.shared singleton
    /// - Parameter pixelkit: A custom instance of PixelKit
    static func setSharedForTesting(pixelKit: PixelKit) {
        Self.shared = pixelKit
    }
}
