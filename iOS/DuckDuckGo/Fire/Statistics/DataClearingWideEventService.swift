//
//  DataClearingWideEventService.swift
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

import Foundation
import Core
import BrowserServicesKit
import PixelKit

/// Service responsible for managing data clearing wide event lifecycle.
///
/// This service handles the complete lifecycle of data clearing wide events:
/// - Starting new events with iOS-specific parameters
/// - Tracking per-action results (success or failure)
/// - Completing events with overall duration calculation
///
/// The service maintains a single active event at a time and automatically
/// cleans up pending events when starting a new one.
final class DataClearingWideEventService {

    // MARK: - Properties

    private let wideEvent: WideEventManaging
    private var eventData: DataClearingWideEventData?

    // MARK: - Initialization

    /// Creates a new data clearing wide event service.
    /// - Parameter wideEvent: The wide event manager for handling event flows.
    init(wideEvent: WideEventManaging) {
        self.wideEvent = wideEvent
    }

    // MARK: - Starting Wide Event

    /// Starts a new data clearing wide event.
    ///
    /// This method creates and initializes a new wide event with the specified parameters
    /// from the Fire request. Any pending events are automatically completed before starting the new one.
    ///
    /// - Parameter request: The Fire request containing user selections and context.
    func start(request: FireRequest) {
        completeAllPending()

        let data = DataClearingWideEventData(
            includedOptions: request.toIncludedOptions(),
            trigger: request.toWideEventTrigger(),
            overallDuration: .startingNow(),
            scope: request.toWideEventScope(),
            source: request.toWideEventSource(),
            contextData: WideEventContextData(name: "funnel_default_ios")
        )

        self.eventData = data
        wideEvent.startFlow(data)
    }

    // MARK: - Action Tracking

    /// Starts tracking an action by initializing its duration interval.
    ///
    /// - Parameter action: The action that is about to execute.
    func start(_ action: DataClearingWideEventData.Action) {
        eventData?[keyPath: action.durationPath] = .startingNow()
    }

    /// Updates the wide event with an action result.
    ///
    /// Completes the action's duration interval and records success or failure status.
    ///
    /// - Parameters:
    ///   - action: The action that completed.
    ///   - result: The result of the action (success or failure).
    func update(_ action: DataClearingWideEventData.Action, result: Result<Void, Error>) {
        eventData?[keyPath: action.durationPath]?.complete()

        switch result {
        case .success:
            eventData?[keyPath: action.statusPath] = .success
        case .failure(let error):
            eventData?[keyPath: action.statusPath] = .failure
            eventData?[keyPath: action.errorPath] = WideEventErrorData(error: error)
        }
    }

    /// Updates the wide event with an action result including pre-measured interval.
    ///
    /// This method is used when the action duration is measured at the Core layer
    /// and returned along with the result.
    ///
    /// - Parameters:
    ///   - action: The action that completed.
    ///   - actionResult: The action result containing both result and measured interval.
    func update(_ action: DataClearingWideEventData.Action, actionResult: ActionResult) {
        eventData?[keyPath: action.durationPath] = actionResult.measuredInterval

        switch actionResult.result {
        case .success:
            eventData?[keyPath: action.statusPath] = .success
        case .failure(let error):
            eventData?[keyPath: action.statusPath] = .failure
            eventData?[keyPath: action.errorPath] = WideEventErrorData(error: error)
        }
    }

    // MARK: - Completing Wide Event

    /// Completes the current wide event with success status.
    ///
    /// This method finalizes the overall duration, marks the event as successful,
    /// and fires the wide pixel. The event data is then cleared.
    func complete() {
        guard let data = eventData else { return }
        data.overallDuration?.complete()
        wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
        eventData = nil
    }
}

// MARK: - Private Helpers

private extension DataClearingWideEventService {

    /// Completes all pending data clearing wide events.
    ///
    /// This is called before starting a new event to ensure only one
    /// active event exists at a time. Pending events are marked as unknown.
    func completeAllPending() {
        let pending = wideEvent.getAllFlowData(DataClearingWideEventData.self)
        for data in pending {
            wideEvent.completeFlow(
                data,
                status: .unknown(reason: DataClearingWideEventData.StatusReason.partialData.rawValue),
                onComplete: { _, _ in }
            )
        }
    }
}

// MARK: - Transformation Helpers

private extension FireRequest {

    /// Prepares comma-separated list of included options from Fire request.
    /// This provides granular detail about which specific flags are set.
    func toIncludedOptions() -> String {
        var includedOptions: [String] = []
        if options.contains(.tabs) {
            includedOptions.append("tabs")
        }
        if options.contains(.data) {
            includedOptions.append("data")
        }
        if options.contains(.aiChats) {
            includedOptions.append("aiChats")
        }
        return includedOptions.joined(separator: ",")
    }

    /// Transforms Fire request trigger to wide event trigger.
    func toWideEventTrigger() -> DataClearingWideEventData.Trigger {
        switch trigger {
        case .manualFire:
            return .manualFire
        case .autoClearOnLaunch:
            return .autoClearOnLaunch
        case .autoClearOnForeground:
            return .autoClearOnForeground
        }
    }

    /// Transforms Fire request scope to wide event scope.
    func toWideEventScope() -> DataClearingWideEventData.Scope {
        switch scope {
        case .tab:
            return .tab
        case .all:
            return .all
        }
    }

    /// Transforms Fire request source to wide event source.
    func toWideEventSource() -> DataClearingWideEventData.Source {
        switch source {
        case .browsing:
            return .browsing
        case .tabSwitcher:
            return .tabSwitcher
        case .settings:
            return .settings
        case .quickFire:
            return .quickFire
        case .deeplink:
            return .deeplink
        case .autoClear:
            return .autoClear
        }
    }
}

/// Custom error type for data clearing actions that don't propagate actual errors
/// but contain assertions, logs, or precondition failures.
///
/// Use this error type for Pattern B actions (Assert/Log Only) to surface error
/// conditions to wide event tracking without modifying the original assertion/log statements.
public struct DataClearingWideEventError: Error {
    /// Human-readable description of the error condition.
    /// Typically contains the text from assert(), assertFailure(), or Logger.error() calls.
    public let description: String

    public init(description: String) {
        self.description = description
    }
}
