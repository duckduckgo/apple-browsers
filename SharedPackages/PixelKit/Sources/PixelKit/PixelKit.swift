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
import DDGError
import os.log
import Common
import FoundationExtensions
import Persistence

public final class PixelKit {
    /// `true` if a request is fired, `false` otherwise
    public typealias CompletionBlock = (Bool, (any Error)?) -> Void

    /// The frequency with which a pixel is sent to our endpoint.
    public enum Frequency: Equatable {
        /// The default frequency for pixels. This fires pixels with the event names as-is.
        case standard

        /// Sent only once ever (based on pixel name only.) The timestamp for this pixel is stored.
        /// Note: This is the only pixel that MUST end with `_u`, Name for pixels of this type must end with if it doesn't an assertion is fired.
        case uniqueByName

        /// Sent only once ever (based on pixel name AND parameters). The timestamp for this pixel is stored.
        case uniqueByNameAndParameters

        /// Sent once per day. The last timestamp for this pixel is stored and compared to the current date. Pixels of this type will have `_daily` appended to their name.
        case daily

        /// Sent once per calendar month (UTC). The last timestamp for this pixel is stored and compared to the current date. Pixels of this type will have `_monthly` appended to their name.
        /// Note that these monthly pixels do not behave the same as ATB-based monthly measures like our official MAU stats, and thus direct comparisons between monthly pixel derived values
        /// and ATB-derived monthly stats should _not_ be made. Tech Design for monthly pixels is available here:
        /// https://app.asana.com/1/137249556945/project/481882893211075/task/1214950124367781?focus=true
        case monthly

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

        /// [Legacy] As `.legacyDailyNoSuffix`, but throttled once per day *per distinct error* rather than
        /// once per day per name. Reproduces legacy `DailyPixel.fire(pixel:error:)`, which appended the
        /// event's error parameter values to its throttling key so that a second, different failure of the
        /// same pixel still reported that day. Without an error attached this behaves exactly like
        /// `.legacyDailyNoSuffix`.
        ///
        /// Only for error pixels migrated off `DailyPixel.fire(pixel:error:)`. New pixels should use
        /// `.daily`, which keys on the name alone.
        case legacyDailyByError

        /// [Legacy] Sent once per day. The last timestamp for this pixel is stored and compared to the current date. Pixels of this type will have `_d` appended to their name.
        case legacyDaily

        /// [Legacy] Sent once per day with a `_d` suffix, in addition to every time it is called with a `_c` suffix.
        /// This means a pixel will get sent twice the first time it is called per-day, and subsequent calls that day will only send the `_c` variant.
        /// This is useful in situations where pixels receive spikes in volume, as the daily pixel can be used to determine how many users are actually affected.
        case legacyDailyAndCount

        /// Sent with sampling - only N% of calls result in actual pixel firing
        case sample(percentage: Int)

        /// Sent at most once per `seconds`-long window per pixel name: suppressed if the pixel was fired
        /// less than `seconds` ago. The window is anchored to the last actual fire (a suppressed call does
        /// not extend it). `seconds: 0` is an empty window and never suppresses. This is the PixelKit
        /// equivalent of the legacy `Pixel.fire(debounce:)` parameter.
        case debounce(seconds: TimeInterval)

        fileprivate var description: String {
            switch self {
            case .standard:
                "Standard"
            case .uniqueByName:
                "Unique"
            case .daily:
                "Daily"
            case .monthly:
                "Monthly"
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
            case .legacyDailyByError:
                "Legacy Daily By Error"
            case .sample(let percentage):
                "Sample (\(percentage)%)"
            case .debounce(let seconds):
                "Debounce (\(seconds)s)"
            }
        }

        /// Caution: These values are used by `pixelHasBeenFiredDailyToday...` methods.  Changing these values may cause data store lookup
        /// failures and lead to re-firing pixels that otherwise should not be fired.
        fileprivate var mapKey: String {
            switch self {
            case .standard: return "standard"
            case .uniqueByName: return "uniqueByName"
            case .uniqueByNameAndParameters: return "uniqueByNameAndParameters"
            case .daily: return "daily"
            case .monthly: return "monthly"
            case .dailyAndCount: return "dailyAndCount"
            case .dailyAndStandard: return "dailyAndStandard"
            case .legacyInitial: return "legacyInitial"
            case .legacyDailyNoSuffix: return "legacyDailyNoSuffix"
            // Shares `daily`'s map: it is a daily throttle, only with the error folded into the pixel-name
            // half of the key rather than the frequency half.
            case .legacyDailyByError: return "daily"
            case .legacyDaily: return "legacyDaily"
            case .legacyDailyAndCount: return "legacyDailyAndCount"
            case .sample(let percentage): return "sample(\(percentage))"
            case .debounce: return "debounce"
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

    /// The host this PixelKit instance runs in. Set at `setUp`, and on iOS it also decides the
    /// `_ios_phone` / `_ios_tablet` marker appended to every pixel name.
    ///
    /// Pick `.iPadOS` only for `UIUserInterfaceIdiom.pad`; every other idiom, including
    /// `.unspecified`, is `.iOS`. That matches the legacy `Pixel`, so the two systems agree on the
    /// marker.
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

    public static let duckDuckGoMorePrivacyInfo = URL(string: "https://help.duckduckgo.com/duckduckgo-help-pages/privacy/atb/")!
    private let defaults: ThrowingKeyValueStoring

    private let logger = Logger(subsystem: "PixelKit", category: "PixelKit")

    private static let defaultPixelCalendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let weeksToCoalesceCohort = 6

    /// Stable, filename-safe identity for this instance's retry-queue store and throttle key, so each
    /// process (browser, VPN agent, packet tunnel, …) gets its own queue even when they share a `defaults`
    /// suite (e.g. `UserDefaults.netP`). Decoupled from the telemetry `source`: `setUp` callers pass an
    /// explicit `session`; it falls back to `source` only for direct `init` construction (e.g. tests).
    private static func retryQueueIdentitySuffix(session: String?, source: String?) -> String {
        (session ?? source ?? "default").replacingOccurrences(of: "/", with: "-")
    }
    private let dateGenerator: () -> Date
    public private(set) static var shared: PixelKit?
    private let appVersion: String
    private let defaultHeaders: [String: String]
    private let fireRequest: FireRequest
    private let retryQueue: PixelRetryQueue?
    private var dryRun: Bool
    private let source: String?
    private let channel: String?
    private let pixelCalendar: Calendar
    private let parameterProvider: PixelKitParameterProviding?

    /// Sets up PixelKit for the entire app.
    ///
    /// - Parameters:
    /// - `dryRun`: if `true`, simulate requests and "send" them at an accelerated rate (once every 2 minutes instead of once a day)
    /// - `source`: if set, adds a `pixelSource` parameter to the pixel call; this can be used to specify which target is sending the pixel
    /// - `session`: a stable, non-telemetry identifier for this PixelKit instance, used to key its retry queue's storage and throttle so distinct instances never share or overwrite one queue
    /// - `channel`: if set, adds a `channel` parameter to pixel calls (e.g. "canary" for internal users, "dev" for alpha/review builds); omit for production builds
    /// - `parameterProvider`: supplies values PixelKit cannot derive itself, currently the ATB cohort read by pixels that set `Options.includeATB`; omit when the host has no need for them
    /// - `fireRequest`: this is not triggered when `dryRun` is `true`
    public static func setUp(dryRun: Bool,
                             appVersion: String,
                             source: String? = nil,
                             session: String,
                             channel: String? = nil,
                             defaultHeaders: [String: String],
                             pixelCalendar: Calendar? = nil,
                             dateGenerator: @escaping () -> Date = Date.init,
                             defaults: ThrowingKeyValueStoring,
                             parameterProvider: PixelKitParameterProviding? = nil,
                             fireRequest: @escaping FireRequest) {
        shared = PixelKit(dryRun: dryRun,
                          appVersion: appVersion,
                          source: source,
                          session: session,
                          channel: channel,
                          defaultHeaders: defaultHeaders,
                          pixelCalendar: pixelCalendar,
                          dateGenerator: dateGenerator,
                          defaults: defaults,
                          parameterProvider: parameterProvider,
                          fireRequest: fireRequest)
    }

    public static func tearDown() {
        shared = nil
    }

    // MARK: - Initialisation

    public convenience init(dryRun: Bool,
                            appVersion: String,
                            source: String? = nil,
                            session: String? = nil,
                            channel: String? = nil,
                            defaultHeaders: [String: String],
                            pixelCalendar: Calendar? = nil,
                            dateGenerator: @escaping () -> Date = Date.init,
                            defaults: ThrowingKeyValueStoring,
                            parameterProvider: PixelKitParameterProviding? = nil,
                            fireRequest: @escaping FireRequest) {
        self.init(dryRun: dryRun,
                  appVersion: appVersion,
                  source: source,
                  session: session,
                  channel: channel,
                  defaultHeaders: defaultHeaders,
                  pixelCalendar: pixelCalendar,
                  dateGenerator: dateGenerator,
                  defaults: defaults,
                  parameterProvider: parameterProvider,
                  retryQueueStore: nil,
                  fireRequest: fireRequest)
    }

    /// Designated initialiser. `retryQueueStore` overrides the retry queue's backing store, so tests can
    /// exercise the queue without touching the real Application Support file; production passes `nil`.
    init(dryRun: Bool,
         appVersion: String,
         source: String?,
         session: String?,
         channel: String?,
         defaultHeaders: [String: String],
         pixelCalendar: Calendar?,
         dateGenerator: @escaping () -> Date,
         defaults: ThrowingKeyValueStoring,
         parameterProvider: PixelKitParameterProviding? = nil,
         retryQueueStore: PixelRetryQueueStoring?,
         fireRequest: @escaping FireRequest) {

        self.dryRun = dryRun
        self.appVersion = appVersion
        self.source = source
        self.channel = channel
        self.defaultHeaders = defaultHeaders
        self.pixelCalendar = pixelCalendar ?? Self.defaultPixelCalendar
        self.dateGenerator = dateGenerator
        self.defaults = defaults
        self.fireRequest = fireRequest
        self.parameterProvider = parameterProvider

        if dryRun {
            self.retryQueue = nil
        } else {
            // Wrap the network fire-request with a retry queue so that a pixel which opted in via
            // `Options.retryOnFailure` and failed is persisted and re-sent after the next successful fire
            // (28-day expiry) — which, for a launching app, happens as soon as it fires its first pixel.
            // Pixels that did not opt in, which is all of them by default, pass straight through. Reuses
            // the same `defaults` for throttling state. This is internal to PixelKit and hidden from its
            // consumers; creating the queue performs no I/O.
            let identity = Self.retryQueueIdentitySuffix(session: session, source: source)
            self.retryQueue = PixelRetryQueue(
                fireRequest: fireRequest,
                store: retryQueueStore ?? PixelRetryQueueFileStore(fileName: "pixelkit-retry-queue-\(identity).json"),
                lastProcessingDateStorage: defaults,
                lastProcessingDateKey: "com.duckduckgo.pixelkit.retry-queue.last-processing-timestamp.\(identity)",
                calendar: self.pixelCalendar,
                dateGenerator: dateGenerator
            )
        }

        logger.debug("👾 PixelKit initialised: dryRun: \(self.dryRun, privacy: .public) appVersion: \(self.appVersion, privacy: .public) source: \(self.source ?? "-", privacy: .public) channel: \(self.channel ?? "-", privacy: .public) defaultHeaders: \(self.defaultHeaders, privacy: .public) pixelCalendar: \(self.pixelCalendar, privacy: .public)")
    }

    // MARK: - Public Fire

    /// The `PixelFiring` witness, and the single place the real firing logic lives.
    ///
    /// Callers should not use this directly. The public entry points are `fire(_:frequency:options:)`
    /// for fire-and-forget and `fireAsync(_:frequency:options:)` when the outcome matters; both are
    /// supplied by the `PixelFiring` extension and funnel into here.
    public func fire(event: PixelKit.Event,
                     frequency: Frequency,
                     options: Options,
                     onComplete: @escaping CompletionBlock) {

        let resolvedName = self.resolvedName(for: event)
        // Throttling and de-duplication key off the name without the trailing marker, so a pixel
        // whose policy is `.standard` is counted once per device rather than once per form factor.
        let pixelName = resolvedName.base

        if !dryRun {
            if frequency == .daily, pixelHasBeenFiredDailyToday(pixelName) {
                onComplete(false, nil)
                return
            } else if frequency == .monthly, pixelHasBeenFiredMonthlyThisMonth(pixelName) {
                onComplete(false, nil)
                return
            } else if frequency == .uniqueByName, pixelHasBeenFiredEver(pixelName) {
                onComplete(false, nil)
                return
            }
        }

        let newParams: [String: String]?
        switch (event.parameters, options.additionalParameters) {
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

        fire(pixelNamed: pixelName,
             platformSuffix: resolvedName.trailingPlatformSuffix,
             frequency: frequency,
             withHeaders: options.headers,
             userAgent: options.userAgent,
             allowsDotInName: event.allowsDotInName,
             withAdditionalParameters: newParams,
             withError: event.error,
             allowedQueryReservedCharacters: options.allowedQueryReservedCharacters,
             includeAppVersionParameter: options.includeAppVersionParameter,
             includeATB: options.includeATB,
             standardParameters: event.standardParameters ?? [],
             retryOnFailure: options.retryOnFailure,
             onComplete: onComplete)
    }

    /// Legacy wide-parameter entry point.
    ///
    /// Superseded by `fire(_:frequency:options:)` and `fireAsync(_:frequency:options:)`. Retained
    /// only so call sites can migrate incrementally, and removed once they have. Not marked
    /// deprecated on purpose: Swift resolves a concrete method ahead of a protocol extension
    /// method, so every unmigrated `fire(event, frequency:)` call still lands here and would
    /// otherwise emit a deprecation warning.
    public func fire(_ event: PixelKit.Event,
                     frequency: Frequency = .standard,
                     withHeaders headers: [String: String]? = nil,
                     withAdditionalParameters params: [String: String]? = nil,
                     allowedQueryReservedCharacters: CharacterSet? = nil,
                     includeAppVersionParameter: Bool = true,
                     onComplete: @escaping CompletionBlock = { _, _ in }) {

        fire(event: event,
             frequency: frequency,
             options: Options(headers: headers,
                              additionalParameters: params,
                              allowedQueryReservedCharacters: allowedQueryReservedCharacters,
                              includeAppVersionParameter: includeAppVersionParameter),
             onComplete: onComplete)
    }

    /// Fires a pixel on the shared instance and returns immediately.
    ///
    /// No-ops when PixelKit has not been set up, matching the previous behaviour.
    public static func fire(_ event: PixelKit.Event,
                            frequency: Frequency = .standard,
                            options: Options = .default) {
        Self.shared?.fire(event, frequency: frequency, options: options)
    }

    /// Fires a pixel on the shared instance and waits for the request to complete.
    ///
    /// - Throws: `PixelKitError.notConfigured` if PixelKit has not been set up. The synchronous
    ///   variant silently no-ops in that case, but a caller that awaited a result cannot honestly
    ///   be told the pixel was either sent or suppressed.
    @discardableResult
    public static func fireAsync(_ event: PixelKit.Event,
                                 frequency: Frequency = .standard,
                                 options: Options = .default) async throws -> FireResult {
        guard let shared = Self.shared else {
            throw PixelKitError.notConfigured
        }
        return try await shared.fireAsync(event, frequency: frequency, options: options)
    }

    /// Legacy wide-parameter static entry point. See the instance method above for why this is not
    /// marked deprecated.
    public static func fire(_ event: PixelKit.Event,
                            frequency: Frequency = .standard,
                            withHeaders headers: [String: String] = [:],
                            withAdditionalParameters parameters: [String: String]? = nil,
                            allowedQueryReservedCharacters: CharacterSet? = nil,
                            includeAppVersionParameter: Bool = true,
                            onComplete: @escaping CompletionBlock = { _, _ in }) {

        Self.shared?.fire(event,
                          frequency: frequency,
                          withHeaders: headers,
                          withAdditionalParameters: parameters,
                          allowedQueryReservedCharacters: allowedQueryReservedCharacters,
                          includeAppVersionParameter: includeAppVersionParameter,
                          onComplete: onComplete)
    }

    // MARK: - Private Fire

    private func fire(pixelNamed pixelName: String,
                      platformSuffix: String,
                      frequency: Frequency,
                      withHeaders headers: [String: String]?,
                      userAgent: String?,
                      allowsDotInName: Bool,
                      withAdditionalParameters params: [String: String]?,
                      withError error: NSError?,
                      allowedQueryReservedCharacters: CharacterSet?,
                      includeAppVersionParameter: Bool,
                      includeATB: Bool,
                      standardParameters: [PixelKitStandardParameter],
                      retryOnFailure: Bool,
                      onComplete: @escaping CompletionBlock) {

        var newParams = params ?? [:]
        if includeAppVersionParameter { newParams[Parameters.appVersion] = appVersion }
        if standardParameters.contains(.pixelSource), let source { newParams[Parameters.pixelSource] = source }
        if let channel { newParams[Parameters.channel] = channel }
        if includeATB {
            if let parameterProvider {
                // Empty rather than absent when there is no ATB yet: legacy `Pixel` sent
                // `statisticsStore.atbWithVariant ?? ""`, so parity means an empty value, not a
                // missing parameter.
                newParams[Parameters.atb] = parameterProvider.atb ?? ""
            } else {
                logger.fault("👾 \(pixelName, privacy: .public) asked for atb but no PixelKitParameterProviding was injected; omitting it")
            }
        }
        if let error { newParams.appendErrorPixelParams(error: error) }

        #if DEBUG
            newParams[Parameters.test] = Values.test
        #endif

        var headers = headers ?? defaultHeaders
        headers[Header.moreInfo] = "See " + Self.duckDuckGoMorePrivacyInfo.absoluteString
        // The host's `FireRequest` closure reads this in preference to its own pixel user agent.
        // See `Options.userAgent`.
        if let userAgent { headers[Header.userAgent] = userAgent }
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
        if !allowsDotInName {
            reportErrorIf(pixel: pixelName, contains: ".")
        }

        switch frequency {
        case .standard:
            handleStandardFrequency(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .uniqueByName:
            handleUnique(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .uniqueByNameAndParameters:
            handleUniqueByNameAndParameters(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .daily:
            handleDaily(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .monthly:
            handleMonthly(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .dailyAndCount:
            handleDailyAndCount(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .dailyAndStandard:
            handleDailyAndStandard(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .legacyInitial:
            handleLegacyInitial(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .legacyDaily:
            handleLegacyDaily(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .legacyDailyAndCount:
            handleLegacyDailyAndCount(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .legacyDailyNoSuffix:
            handleLegacyDailyNoSuffix(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, onComplete)
        case .legacyDailyByError:
            handleLegacyDailyByError(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, error, onComplete)
        case .sample(let percentage):
            handleSample(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, percentage, onComplete)
        case .debounce(let seconds):
            handleDebounce(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, retryOnFailure, seconds, onComplete)
        }
    }

    // MARK: -

    private func handleStandardFrequency(_ pixelName: String,
                                         _ platformSuffix: String,
                                         _ headers: [String: String],
                                         _ params: [String: String],
                                         _ allowedQueryReservedCharacters: CharacterSet?,
                                         _ retryOnFailure: Bool,
                                         _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        fireRequestWrapper(pixelName, platformSuffix, headers, params, allowedQueryReservedCharacters, true, .standard, retryOnFailure, onComplete)
    }

    private func handleLegacyInitial(_ pixelName: String,
                                     _ platformSuffix: String,
                                     _ headers: [String: String],
                                     _ newParams: [String: String],
                                     _ allowedQueryReservedCharacters: CharacterSet?,
                                     _ retryOnFailure: Bool,
                                     _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        if !pixelHasBeenFiredEver(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .uniqueByName)
                fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .legacyInitial, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName, frequency: .legacyInitial, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .legacyInitial, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleUnique(_ pixelName: String,
                              _ platformSuffix: String,
                              _ headers: [String: String],
                              _ newParams: [String: String],
                              _ allowedQueryReservedCharacters: CharacterSet?,
                              _ retryOnFailure: Bool,
                              _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_d")
        guard pixelName.hasSuffix("_u") else {
            assertionFailure("Unique pixel: must end with _u")
            onComplete(false, nil)
            return
        }
        if !pixelHasBeenFiredEver(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .uniqueByName)
                fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .uniqueByName, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName, frequency: .uniqueByName, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .uniqueByName, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleUniqueByNameAndParameters(_ pixelName: String,
                                                 _ platformSuffix: String,
                                                 _ headers: [String: String],
                                                 _ newParams: [String: String],
                                                 _ allowedQueryReservedCharacters: CharacterSet?,
                                                 _ retryOnFailure: Bool,
                                                 _ onComplete: @escaping CompletionBlock) {
        let pixelNameAndParams = pixelName + newParams.toString()
        if !pixelHasBeenFiredEver(pixelNameAndParams) {
            do {
                try updatePixelLastFireDate(pixelName: pixelNameAndParams, frequency: .uniqueByName)
                fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .uniqueByNameAndParameters, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName, frequency: .uniqueByNameAndParameters, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .uniqueByNameAndParameters, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleDaily(_ pixelName: String,
                             _ platformSuffix: String,
                             _ headers: [String: String],
                             _ newParams: [String: String],
                             _ allowedQueryReservedCharacters: CharacterSet?,
                             _ retryOnFailure: Bool,
                             _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily") // Because is added automatically
        if !pixelHasBeenFiredDailyToday(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .daily)
                fireRequestWrapper(pixelName + "_daily", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .daily, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName + "_daily", frequency: .daily, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName + "_daily", frequency: .daily, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleDebounce(_ pixelName: String,
                                _ platformSuffix: String,
                                _ headers: [String: String],
                                _ newParams: [String: String],
                                _ allowedQueryReservedCharacters: CharacterSet?,
                                _ retryOnFailure: Bool,
                                _ seconds: TimeInterval,
                                _ onComplete: @escaping CompletionBlock) {
        let frequency = Frequency.debounce(seconds: seconds)
        if !pixelHasBeenFiredWithinDebounceInterval(pixelName, seconds: seconds) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: frequency)
                fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, frequency, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName, frequency: frequency, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName, frequency: frequency, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleMonthly(_ pixelName: String,
                               _ platformSuffix: String,
                               _ headers: [String: String],
                               _ newParams: [String: String],
                               _ allowedQueryReservedCharacters: CharacterSet?,
                               _ retryOnFailure: Bool,
                               _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_monthly") // Because is added automatically
        if !pixelHasBeenFiredMonthlyThisMonth(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .monthly)
                fireRequestWrapper(pixelName + "_monthly", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .monthly, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName + "_monthly", frequency: .monthly, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName + "_monthly", frequency: .monthly, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleLegacyDailyNoSuffix(_ pixelName: String,
                                           _ platformSuffix: String,
                                           _ headers: [String: String],
                                           _ newParams: [String: String],
                                           _ allowedQueryReservedCharacters: CharacterSet?,
                                           _ retryOnFailure: Bool,
                                           _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        if !pixelHasBeenFiredDailyToday(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .daily)
                fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyNoSuffix, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName, frequency: .legacyDailyNoSuffix, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .legacyDailyNoSuffix, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleLegacyDailyByError(_ pixelName: String,
                                          _ platformSuffix: String,
                                          _ headers: [String: String],
                                          _ newParams: [String: String],
                                          _ allowedQueryReservedCharacters: CharacterSet?,
                                          _ retryOnFailure: Bool,
                                          _ error: NSError?,
                                          _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        // Only the throttling key carries the error; the pixel is sent under its own name, as with
        // `.legacyDailyNoSuffix`.
        let throttleKey = pixelName + Self.dailyThrottleKeyErrorSuffix(for: error)
        if !pixelHasBeenFiredDailyToday(throttleKey) {
            do {
                try updatePixelLastFireDate(pixelName: throttleKey, frequency: .daily)
                fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyByError, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName, frequency: .legacyDailyByError, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName, frequency: .legacyDailyByError, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    /// The error half of a `.legacyDailyByError` throttling key, or `""` when there is no error.
    ///
    /// Byte-for-byte the format legacy `DailyPixel.fire(pixel:error:)` used - `":"` followed by the error
    /// parameter *values*, ordered by their parameter names and joined with `";"`, truncated to 50
    /// characters - so the keys `LegacyPixelStateMigration` copied out of the legacy daily store still
    /// match. (PixelKit's error parameters add the two SQLite codes legacy didn't have, so a key for an
    /// error carrying those differs from the legacy one; the cost is at most one extra fire on the day an
    /// install migrates.)
    private static func dailyThrottleKeyErrorSuffix(for error: NSError?) -> String {
        guard let error else { return "" }

        var errorParams: [String: String] = [:]
        errorParams.appendErrorPixelParams(error: error)

        let values = errorParams.keys.sorted().compactMap { errorParams[$0] }.joined(separator: ";")
        return ":" + String(values.prefix(50))
    }

    /// Handles sampling frequency pixels - only N% of calls result in actual pixel firing
    /// - Parameters:
    ///   - pixelName: The name of the pixel to potentially fire
    ///   - headers: HTTP headers for the request
    ///   - newParams: Additional parameters for the pixel
    ///   - allowedQueryReservedCharacters: Characters allowed in query parameters
    ///   - percentage: Sampling percentage from 1 to 100 (inclusive)
    ///   - onComplete: Completion handler called with whether the pixel was fired
    private func handleSample(_ pixelName: String,
                              _ platformSuffix: String,
                              _ headers: [String: String],
                              _ newParams: [String: String],
                              _ allowedQueryReservedCharacters: CharacterSet?,
                              _ retryOnFailure: Bool,
                              _ percentage: Int,
                              _ onComplete: @escaping CompletionBlock) {
        assert(percentage >= 1 && percentage <= 100, "Sampling percentage must be between 1 and 100, got \(percentage)")

        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily")
        reportErrorIf(pixel: pixelName, endsWith: "_monthly")

        let suffix = "_sample\(percentage)"

        let sampler = ClosureSampler(percentage: percentage)
        sampler.sample({
            let sampledPixelName = pixelName + suffix
            fireRequestWrapper(sampledPixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .sample(percentage: percentage), retryOnFailure, onComplete)
        }, onDiscarded: {
            self.printDebugInfo(pixelName: pixelName + suffix, frequency: .sample(percentage: percentage), parameters: newParams, skipped: true)
            onComplete(false, nil)
        })
    }

    private func handleLegacyDaily(_ pixelName: String,
                                   _ platformSuffix: String,
                                   _ headers: [String: String],
                                   _ newParams: [String: String],
                                   _ allowedQueryReservedCharacters: CharacterSet?,
                                   _ retryOnFailure: Bool,
                                   _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d") // Because is added automatically
        if !pixelHasBeenFiredDailyToday(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .daily)
                fireRequestWrapper(pixelName + "_d", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .legacyDaily, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName + "_d", frequency: .legacyDaily, parameters: newParams, skipped: true)
                onComplete(false, nil)
            }
        } else {
            printDebugInfo(pixelName: pixelName + "_d", frequency: .legacyDaily, parameters: newParams, skipped: true)
            onComplete(false, nil)
        }
    }

    private func handleLegacyDailyAndCount(_ pixelName: String,
                                           _ platformSuffix: String,
                                           _ headers: [String: String],
                                           _ newParams: [String: String],
                                           _ allowedQueryReservedCharacters: CharacterSet?,
                                           _ retryOnFailure: Bool,
                                           _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_d") // Because is added automatically
        reportErrorIf(pixel: pixelName, endsWith: "_c") // Because is added automatically
        if !pixelHasBeenFiredDailyToday(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .daily)
                fireRequestWrapper(pixelName + "_d", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyAndCount, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName + "_d", frequency: .legacyDailyAndCount, parameters: newParams, skipped: true)
            }
        } else {
            printDebugInfo(pixelName: pixelName + "_d", frequency: .legacyDailyAndCount, parameters: newParams, skipped: true)
        }

        fireRequestWrapper(pixelName + "_c", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .legacyDailyAndCount, retryOnFailure, onComplete)
    }

    private func handleDailyAndCount(_ pixelName: String,
                                     _ platformSuffix: String,
                                     _ headers: [String: String],
                                     _ newParams: [String: String],
                                     _ allowedQueryReservedCharacters: CharacterSet?,
                                     _ retryOnFailure: Bool,
                                     _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily") // Because is added automatically
        reportErrorIf(pixel: pixelName, endsWith: "_count") // Because is added automatically
        if !pixelHasBeenFiredDailyToday(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .daily)
                fireRequestWrapper(pixelName + "_daily", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName + "_daily", frequency: .dailyAndCount, parameters: newParams, skipped: true)
            }
        } else {
            printDebugInfo(pixelName: pixelName + "_daily", frequency: .dailyAndCount, parameters: newParams, skipped: true)
        }

        fireRequestWrapper(pixelName + "_count", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, retryOnFailure, onComplete)
    }

    private func handleDailyAndStandard(_ pixelName: String,
                                        _ platformSuffix: String,
                                        _ headers: [String: String],
                                        _ newParams: [String: String],
                                        _ allowedQueryReservedCharacters: CharacterSet?,
                                        _ retryOnFailure: Bool,
                                        _ onComplete: @escaping CompletionBlock) {
        reportErrorIf(pixel: pixelName, endsWith: "_u")
        reportErrorIf(pixel: pixelName, endsWith: "_daily") // Because is added automatically
        if !pixelHasBeenFiredDailyToday(pixelName) {
            do {
                try updatePixelLastFireDate(pixelName: pixelName, frequency: .daily)
                fireRequestWrapper(pixelName + "_daily", platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, retryOnFailure, onComplete)
            } catch {
                fireStorageWriteErrorPixel(suppressedPixelName: pixelName, error: error)
                printDebugInfo(pixelName: pixelName + "_daily", frequency: .dailyAndCount, parameters: newParams, skipped: true)
            }
        } else {
            printDebugInfo(pixelName: pixelName + "_daily", frequency: .dailyAndCount, parameters: newParams, skipped: true)
        }

        fireRequestWrapper(pixelName, platformSuffix, headers, newParams, allowedQueryReservedCharacters, true, .dailyAndCount, retryOnFailure, onComplete)
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
        // Wide-event pixels (`m_mac_wide_*` / `m_ios_wide_*`) also log their parameters via the
        // POST endpoint payload in `DefaultWideEventSender`; skip the params here to avoid the noise.
        guard !pixelName.contains("_wide_") else {
            logger.debug("👾[\(frequency.description, privacy: .public)-\(skipped ? "Skipped" : "Fired", privacy: .public)] \(pixelName, privacy: .public)")
            return
        }

        let params = parameters
            .filter { key, _ in key != "test" }
            .sorted { $0.key < $1.key }

        // Sort the params before logging them in debug mode to make it easier to compare multiple subsequent calls
        let sortedParamsString = params.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        logger.debug("👾[\(frequency.description, privacy: .public)-\(skipped ? "Skipped" : "Fired", privacy: .public)] \(pixelName, privacy: .public) [\(sortedParamsString, privacy: .public)]")
    }

    /// The single place a pixel name reaches the network, and therefore the only place the platform
    /// marker is appended.
    ///
    /// `pixelName` already carries the frequency suffix its handler added, so appending
    /// `platformSuffix` here is what produces `<name>_<frequency>_ios_<formFactor>`. Handlers pass
    /// the marker through untouched and never see it in a position where they could misorder it.
    private func fireRequestWrapper(
        _ pixelName: String,
        _ platformSuffix: String,
        _ headers: [String: String],
        _ parameters: [String: String],
        _ allowedQueryReservedCharacters: CharacterSet?,
        _ callBackOnMainThread: Bool,
        _ frequency: Frequency,
        _ retryOnFailure: Bool,
        _ onComplete: @escaping CompletionBlock) {
            let requestName = pixelName + platformSuffix
#if DEBUG
            Self.writeValidationPixel(pixelName: requestName, parameters: parameters)
#endif
            printDebugInfo(pixelName: requestName, frequency: frequency, parameters: parameters, skipped: false)
            guard !dryRun else {
                // simulate server response time for Dry Run mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onComplete(true, nil)
                }
                return
            }
            guard let retryQueue else {
                fireRequest(requestName, headers, parameters, allowedQueryReservedCharacters, callBackOnMainThread, onComplete)
                return
            }
            retryQueue.fire(pixelName: requestName,
                            headers: headers,
                            parameters: parameters,
                            allowedQueryReservedCharacters: allowedQueryReservedCharacters,
                            callBackOnMainThread: callBackOnMainThread,
                            retryOnFailure: retryOnFailure,
                            onComplete: onComplete)
        }

    /// A pixel name split at the point the frequency suffix gets inserted.
    private struct ResolvedPixelName: Equatable {
        /// Prefix + event name, plus any platform marker a legacy policy places *before* the
        /// frequency suffix.
        ///
        /// Also the throttling and last-fire-date key, so for any pixel that already shipped this
        /// must stay byte-identical to what it was before its policy was pinned. Otherwise a daily
        /// pixel would forget it had fired and send one extra time on upgrade.
        let base: String
        /// The platform marker `fireRequestWrapper` appends *after* the frequency suffix. Empty for
        /// both legacy policies, and on macOS for all of them.
        let trailingPlatformSuffix: String
    }

    /// Builds the prefixed name and decides where this event's platform marker goes.
    ///
    /// Takes only the event: a pixel's name is a property of the pixel, not of the call site that
    /// fires it. `Options` carries transport and payload, nothing that changes the name.
    private func resolvedName(for event: PixelKit.Event) -> ResolvedPixelName {

        // An explicit prefix means the event has stated its complete name, so none of the platform
        // correction below applies. `.none` is the empty-string case of this.
        if let prefix = event.namePrefix.literal {
            return splitting(prefix + event.name, per: event.platformSuffixPolicy)
        }

        let pixelName = event.name
        if pixelName.hasPrefix("experiment") {
            // Experiment names carry their own marker, applied here rather than through the policy.
            // Routing them through `splitting` as well would append a second one.
            return ResolvedPixelName(base: addExperimentPlatformSuffix(to: pixelName), trailingPlatformSuffix: "")
        }

#if os(iOS)
        return splitting(pixelName, per: event.platformSuffixPolicy)
#else
        // Many macOS pixel names need "correcting" after the fact
        // However, we should try and move away from this approach
        // (and towards the more deliberate approach above with the prefix and experiment suffix)
        // This approach won't work for iOS as the names have a very varied set of prefixes
        let correctedName: String
        if pixelName.hasPrefix("m_mac_") {
            // Can be a debug event or not, if already prefixed the name remains unchanged
            correctedName = pixelName
        } else if let debugEvent = event as? DebugEvent {
            // Is a Debug event not already prefixed
            correctedName = "m_mac_debug_\(debugEvent.name)"
        } else {
            correctedName = "m_mac_\(pixelName)"
        }
        // `platformSuffix` is empty on macOS, so the policy cannot change this name.
        return splitting(correctedName, per: event.platformSuffixPolicy)
#endif
    }

    /// Places `platformSuffix` relative to the frequency suffix according to `policy`.
    private func splitting(_ name: String, per policy: PixelKitPlatformSuffixPolicy) -> ResolvedPixelName {
        switch policy {
        case .standard:
            return ResolvedPixelName(base: name, trailingPlatformSuffix: platformSuffix)
        case .legacyBeforeFrequencySuffix:
            return ResolvedPixelName(base: name + platformSuffix, trailingPlatformSuffix: "")
        case .legacyOmitted:
            return ResolvedPixelName(base: name, trailingPlatformSuffix: "")
        }
    }

    /// The throttling key for `event`: the resolved name without the trailing marker.
    private func prefixedAndSuffixedName(for event: PixelKit.Event) -> String {
        resolvedName(for: event).base
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

    public static func pixelLastFireDate(event: PixelKit.Event, frequency: Frequency) throws -> Date? {
        try Self.shared?.pixelLastFireDate(event: event, frequency: frequency)
    }

    public func pixelLastFireDate(event: PixelKit.Event, frequency: Frequency) throws -> Date? {
        try pixelLastFireDate(pixelName: prefixedAndSuffixedName(for: event), frequency: frequency)
    }

    private func pixelLastFireDate(pixelName: String, frequency: Frequency) throws -> Date? {
        let map = try defaults.object(forKey: userDefaultsKeyName(forPixelName: pixelName)) as? [String: Date]
        return map?[frequency.mapKey]
    }

    /// Reads the stored per-frequency last-fire-date map for `key`, lazily migrating prior
    /// raw-`Date` storage (used before per-frequency maps) into `[daily: date]` so the legacy
    /// daily last-fire date is preserved. The upgraded format is persisted when a migration occurs.
    private func migratedLastFireDateMap(forKey key: String) throws -> [String: Date] {
        let raw = try defaults.object(forKey: key)
        guard let legacyDate = raw as? Date else {
            return (raw as? [String: Date]) ?? [:]
        }
        let map = [Frequency.daily.mapKey: legacyDate]
        try defaults.set(map, forKey: key)
        return map
    }

    private func updatePixelLastFireDate(pixelName: String, frequency: Frequency) throws {
        let key = userDefaultsKeyName(forPixelName: pixelName)
        var map = try migratedLastFireDateMap(forKey: key)
        map[frequency.mapKey] = dateGenerator()
        try defaults.set(map, forKey: key)
    }

    private func fireStorageWriteErrorPixel(suppressedPixelName: String, error: Error) {
        let pixelName: String
        switch source {
        case Source.iOS.rawValue:
            pixelName = "m_pixel_fire_suppressed_storage_error_ios_phone"
        case Source.iPadOS.rawValue:
            pixelName = "m_pixel_fire_suppressed_storage_error_ios_tablet"
        default:
            pixelName = "m_mac_pixel_fire_suppressed_storage_error"
        }

        var params: [String: String] = ["suppressedPixel": suppressedPixelName]
        params[Parameters.appVersion] = appVersion
        params.appendErrorPixelParams(error: error as NSError)

        fireRequestWrapper(
            pixelName,
            "", // The names above already carry their platform marker.
            defaultHeaders,
            params,
            nil,
            true,
            .standard,
            false,
            { _, _ in }
        )
    }

    /// Evaluates `within` against the stored last-fire date for `frequency`'s `mapKey`.
    /// Returns `false` when there's no stored date for that frequency, and fails closed
    /// (returns `true`, suppressing the pixel) on a storage read error.
    private func pixelHasBeenFired(_ name: String, frequency: Frequency, within: (Date) -> Bool) -> Bool {
        do {
            let map = try migratedLastFireDateMap(forKey: userDefaultsKeyName(forPixelName: name))
            guard let lastFireDate = map[frequency.mapKey] else { return false }
            return within(lastFireDate)
        } catch {
            return true
        }
    }

    /// Returns `true` if the pixel was last fired less than `seconds` ago (so it should be suppressed).
    /// The stored fire date is shared across debounce intervals (mapKey `"debounce"`), and the window is
    /// evaluated against the passed `seconds`. Fails closed (suppresses) on a storage read error.
    private func pixelHasBeenFiredWithinDebounceInterval(_ name: String, seconds: TimeInterval) -> Bool {
        pixelHasBeenFired(name, frequency: .debounce(seconds: seconds)) { lastFireDate in
            lastFireDate > dateGenerator().addingTimeInterval(-seconds)
        }
    }

    private func pixelHasBeenFiredDailyToday(_ name: String) -> Bool {
        guard !dryRun else {
            if let lastFireDate = try? pixelLastFireDate(pixelName: name, frequency: .daily),
               let twoMinsAgo = pixelCalendar.date(byAdding: .minute, value: -2, to: dateGenerator()) {
                return lastFireDate >= twoMinsAgo
            }

            return false
        }

        return pixelHasBeenFired(name, frequency: .daily) { lastFireDate in
            pixelCalendar.isDate(dateGenerator(), inSameDayAs: lastFireDate)
        }
    }

    private func pixelHasBeenFiredMonthlyThisMonth(_ name: String) -> Bool {
        guard !dryRun else {
            if let lastFireDate = try? pixelLastFireDate(pixelName: name, frequency: .monthly),
               let twoMinsAgo = pixelCalendar.date(byAdding: .minute, value: -2, to: dateGenerator()) {
                return lastFireDate >= twoMinsAgo
            }

            return false
        }

        do {
            if let lastFireDate = try pixelLastFireDate(pixelName: name, frequency: .monthly) {
                return pixelCalendar.isDate(dateGenerator(), equalTo: lastFireDate, toGranularity: .month)
            }
            return false
        } catch {
            return true
        }
    }

    private func pixelHasBeenFiredEver(_ name: String) -> Bool {
        do {
            return try defaults.object(forKey: userDefaultsKeyName(forPixelName: name)) != nil
        } catch {
            return true
        }
    }

    public func clearFrequencyHistoryFor(pixel: PixelKit.Event) {
        guard let name = Self.shared?.userDefaultsKeyName(forPixelName: pixel.name) else {
            return
        }
        try? self.defaults.removeObject(forKey: name)
    }

    public func clearFrequencyHistoryForAllPixels() {
        guard let defaults = self.defaults as? DictionaryRepresentable else {
            return
        }
        for (key, _) in defaults.dictionaryRepresentation() {
            if key.hasPrefix(Self.storageKeyPrefixLegacy) || key.hasPrefix(Self.storageKeyPrefix) {
                try? self.defaults.removeObject(forKey: key)
                self.logger.debug("🚮 Removing from storage \(key, privacy: .public)")
            }
        }
    }

    static let storageKeyPrefixLegacy = "com.duckduckgo.network-protection.pixel."
    static let storageKeyPrefix = "com.duckduckgo.network-protection.pixel."

    private func userDefaultsKeyName(forPixelName pixelName: String) -> String {
        return "\(Self.storageKeyPrefix)\(pixelName)\( dryRun ? ".dry-run" : "" )"
    }
}

internal extension Dictionary where Key == String, Value == String {

    mutating func appendErrorPixelParams(error: NSError) {
        var params = [String: String]()
        params[PixelKit.Parameters.errorCode] = "\(error.code)"
        params[PixelKit.Parameters.errorDomain] = error.domain
        // WARNING: Avoid adding error.description to prevent leaking personal information.

        let underlyingErrorParameters = self.underlyingErrorParameters(for: error)
        params.merge(underlyingErrorParameters) { first, _ in
            return first
        }

        if let sqlErrorCode = error.userInfo["SQLiteResultCode"] as? NSNumber {
            params[PixelKit.Parameters.underlyingErrorSQLiteCode] = "\(sqlErrorCode.intValue)"
        }

        if let sqlExtendedErrorCode = error.userInfo["SQLiteExtendedResultCode"] as? NSNumber {
            params[PixelKit.Parameters.underlyingErrorSQLiteExtendedCode] = "\(sqlExtendedErrorCode.intValue)"
        }

        // Merge the collected parameters into self
        self.merge(params) { _, new in new }
    }

    /// Recursive call to add underlying error information for non DDGErrors
    private func underlyingErrorParameters(for nsError: NSError, level: Int = 0) -> [String: String] {
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            let levelString = (level == 0 ? "" : String(level + 1))
            let errorCodeParameterName = PixelKit.Parameters.underlyingErrorCode + levelString
            let errorDomainParameterName = PixelKit.Parameters.underlyingErrorDomain + levelString

            let currentUnderlyingErrorParameters = [
                errorCodeParameterName: "\(underlyingError.code)",
                errorDomainParameterName: underlyingError.domain
                // WARNING: Avoid adding error.description to prevent leaking personal information.
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

// MARK: - Local Pixel Validation

#if DEBUG
extension PixelKit {

    private static let validationLogQueue = DispatchQueue(label: "Debug Pixel Validation")
    private static var validationLogCleared = false

    private static var validationLogURL: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("pixelkit-validation-log.txt")
    }

    private static func pixelURI(name: String, parameters: [String: String]) -> String {
        guard !parameters.isEmpty else {
            return name
        }

        let sortedParams = parameters.sorted { $0.key < $1.key }
        let queryString = sortedParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(name)?\(queryString)"
    }

    private static func writeValidationPixel(pixelName: String, parameters: [String: String]) {
        let pixelURI = pixelURI(name: pixelName, parameters: parameters)
        writeToValidationLog("Pixel fired: \(pixelURI)")
    }

    private static func writeToValidationLog(_ message: String) {
        validationLogQueue.async {
            let fileURL = validationLogURL

            if !validationLogCleared {
                try? FileManager.default.removeItem(at: fileURL)
                validationLogCleared = true
            }

            let entry = message + "\n"
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }
}
#endif

internal extension PixelKit {

    /// [USE ONLY FOR TESTS] Sets the shared PixelKit.shared singleton
    /// - Parameter pixelkit: A custom instance of PixelKit
    static func setSharedForTesting(pixelKit: PixelKit) {
        Self.shared = pixelKit
    }
}
