//
//  WebContentHealthPixel.swift
//  DuckDuckGo
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

import AIChat
import Core
import Foundation
import PixelKit
import WebKit

enum WebContentHealthPixel: PixelKit.Event {

    enum Surface: String, Codable {
        case search
        case duckai
        case other

        init(url: URL?) {
            // A Duck.ai chat URL also carries a search query, so check it first.
            if url?.isDuckAIURL == true {
                self = .duckai
            } else if url?.isDuckDuckGoSearch == true {
                self = .search
            } else {
                self = .other
            }
        }
    }

    /// What the page and app looked like when WebKit reported the hang. Yes/no only, so no URL leaves the device.
    struct PageContext: Codable {
        let surface: Surface
        let isLoading: Bool
        let isDesktopMode: Bool
        let isProtected: Bool
        let hasWebExtension: Bool

        var parameters: [String: String] {
            ["surface": surface.rawValue,
             "loading": String(isLoading),
             "desktop_mode": String(isDesktopMode),
             "protections": String(isProtected),
             "web_extension": String(hasWebExtension)]
        }
    }

    /// How a preview snapshot ended.
    enum SnapshotResult: String {
        /// No timed snapshot was taken.
        case skipped
        /// The first attempt (`afterScreenUpdates = true`) answered in time.
        case success
        /// The first attempt timed out; the fallback (`afterScreenUpdates = false`) returned an image.
        case retryImage = "retry-image"
        /// The first attempt timed out; the fallback returned without an image.
        case retryNoImage = "retry-no-image"
        /// The first attempt timed out and so did the fallback.
        case retryTimeout = "retry-timeout"

        var isTimeout: Bool {
            switch self {
            case .skipped, .success: return false
            case .retryImage, .retryNoImage, .retryTimeout: return true
            }
        }
    }

    case terminationReloadResult(outcome: TerminationReloadMonitor.Outcome, recovery: TerminationReloadMonitor.Recovery)
    case unresponsive(context: PageContext, appState: String)
    case unresponsiveResult(outcome: WebContentFreezeMonitor.Outcome,
                            duration: WebContentFreezeMonitor.DurationBucket,
                            attempts: WebContentFreezeMonitor.AttemptsBucket,
                            appState: String,
                            leftTab: Bool,
                            context: PageContext)
    case previewSnapshotTimeout(result: SnapshotResult, unresponsive: Bool, appState: String)

    var name: String {
        switch self {
        case .terminationReloadResult: return "web-content_termination-reload-result"
        case .unresponsive: return "web-content_unresponsive-2"
        case .unresponsiveResult: return "web-content_unresponsive-result"
        case .previewSnapshotTimeout: return "web-content_preview-snapshot-timeout"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .terminationReloadResult(let outcome, let recovery):
            return ["outcome": outcome.rawValue, "recovery": recovery.rawValue]
        case .unresponsive(let context, let appState):
            return context.parameters.merging(["app_state": appState]) { $1 }
        case .unresponsiveResult(let outcome, let duration, let attempts, let appState, let leftTab, let context):
            return context.parameters.merging(["outcome": outcome.rawValue,
                                               "duration": duration.rawValue,
                                               "attempts": attempts.rawValue,
                                               "app_state": appState,
                                               "left_tab": String(leftTab)]) { $1 }
        case .previewSnapshotTimeout(let result, let unresponsive, let appState):
            return ["result": result.rawValue, "unresponsive": String(unresponsive), "app_state": appState]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
    var namePrefix: PixelKitNamePrefix { .none }

}

/// Reports how the reload after a web content process termination ended: the first navigation that finishes or
/// fails after `begin`, or another termination before either.
struct TerminationReloadMonitor {

    enum Recovery: String {
        /// Reloaded from the termination callback.
        case immediate
        /// Reloaded when the app became active, after a termination in the background.
        case deferred
    }

    enum Outcome: String {
        case finished
        case failed
        case terminated
    }

    private(set) var pendingRecovery: Recovery?
    private let pixelFiring: (any PixelKitFiring)?

    init(pixelFiring: (any PixelKitFiring)?) {
        self.pixelFiring = pixelFiring
    }

    mutating func begin(_ recovery: Recovery) {
        pendingRecovery = recovery
    }

    mutating func didFinish() {
        end(.finished)
    }

    mutating func didFail(with error: Error) {
        // A cancelled reload keeps the result pending, so if the user then navigates elsewhere, that navigation's
        // result is reported for the reload. Tracking the reload's WKNavigation would fix this.
        let error = error as NSError
        let isCancellation = (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == WKError.WebKitErrorDomain && error.code == WKError.Code.frameLoadInterruptedByPolicyChange.rawValue)
        guard !isCancellation else { return }
        end(.failed)
    }

    mutating func didTerminate() {
        end(.terminated)
    }

    private mutating func end(_ outcome: Outcome) {
        guard let recovery = pendingRecovery else { return }
        pendingRecovery = nil
        pixelFiring?.fire(WebContentHealthPixel.terminationReloadResult(outcome: outcome, recovery: recovery), frequency: .dailyAndCount)
    }

}
