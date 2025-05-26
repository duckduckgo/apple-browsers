//
//  PixelExperimentKit.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import PixelKit
import BrowserServicesKit
import Foundation

public typealias ConversionWindow = ClosedRange<Int>
public typealias NumberOfCalls = Int

struct ExperimentEvent: PixelKitEvent {
    var name: String
    var parameters: [String: String]?
}

extension PixelKit {

    struct Constants {
        static let enrollmentEventPrefix = "experiment_enroll"
        static let metricsEventPrefix = "experiment_metrics"
        static let metricKey = "metric"
        static let conversionWindowDaysKey = "conversionWindowDays"
        static let valueKey = "value"
        static let enrollmentDateKey = "enrollmentDate"
        static let searchMetricValue = "search"
        static let appUseMetricValue = "app_use"
    }

    // Static property to hold shared dependencies
    struct ExperimentConfig {
        static var featureFlagger: FeatureFlagger?
        static var eventTracker: ExperimentEventTracking = ExperimentEventTracker()
        static var fireFunction: (PixelKitEvent, PixelKit.Frequency, Bool) -> Void = { event, frequency, includeAppVersion in
            fire(event, frequency: frequency, includeAppVersionParameter: includeAppVersion)
        }
    }

    // Setup method to initialize dependencies
    public static func configureExperimentKit(
        featureFlagger: FeatureFlagger,
        eventTracker: ExperimentEventTracking = ExperimentEventTracker(),
        fire: @escaping (PixelKitEvent, PixelKit.Frequency, Bool) -> Void = { event, frequency, includeAppVersion in
            fire(event, frequency: frequency, includeAppVersionParameter: includeAppVersion)
        }
    ) {
        ExperimentConfig.featureFlagger = featureFlagger
        ExperimentConfig.eventTracker = eventTracker
        ExperimentConfig.fireFunction = fire
    }

    /// Fires a pixel indicating the user's enrollment in an experiment.
    /// - Parameters:
    ///   - subfeatureID: Identifier for the subfeature associated with the experiment.
    ///   - experiment: Data about the experiment like cohort and enrollment date
    public static func fireExperimentEnrollmentPixel(subfeatureID: SubfeatureID, experiment: ExperimentData) {
        let eventName = "\(Constants.enrollmentEventPrefix)_\(subfeatureID)_\(experiment.cohortID)"
        let event = ExperimentEvent(name: eventName, parameters: [Constants.enrollmentDateKey: experiment.enrollmentDate.toYYYYMMDDInET()])
        ExperimentConfig.fireFunction(event, .uniqueByNameAndParameters, false)
    }

    /// Fires a pixel for a specific action in an experiment, based on conversion window and value.
    /// - Parameters:
    ///   - subfeatureID: Identifier for the subfeature associated with the experiment.
    ///   - metric: The name of the metric being tracked (e.g., "searches").
    ///   - conversionWindowDays: The range of days after enrollment during which the action is valid.
    ///   - value: A specific value associated to the action. It could be the target number of actions required to fire the pixel.
    ///
    /// This function:
    /// 1. Validates if the experiment is active.
    /// 2. Ensures the user is within the specified conversion window.
    /// 3. Sends the pixel if not sent before (unique by name and parameter)
    public static func fireExperimentPixel(for subfeatureID: SubfeatureID,
                                           metric: String,
                                           conversionWindowDays: ConversionWindow,
                                           value: String) {
        // Check is active experiment for user
        guard let featureFlagger = ExperimentConfig.featureFlagger else {
            assertionFailure("PixelKit is not configured for experiments")
            return
        }
        guard let experimentData = featureFlagger.allActiveExperiments[subfeatureID] else { return }

        // Check if within conversion window
        guard isUserInConversionWindow(conversionWindowDays, enrollmentDate: experimentData.enrollmentDate) else { return }

        // Define event
        let event = event(for: subfeatureID, experimentData: experimentData, conversionWindowDays: conversionWindowDays, metric: metric, value: value)
        ExperimentConfig.fireFunction(event, .uniqueByNameAndParameters, false)
    }

    /// Fires a pixel for a specific action in an experiment, based on conversion window and value thresholds.
    /// - Parameters:
    ///   - subfeatureID: Identifier for the subfeature associated with the experiment.
    ///   - metric: The name of the metric being tracked (e.g., "searches").
    ///   - conversionWindowDays: The range of days after enrollment during which the action is valid.
    ///   - numberOfCalls: target number of actions required to fire the pixel.
    ///
    /// This function:
    /// 1. Validates if the experiment is active.
    /// 2. Ensures the user is within the specified conversion window.
    /// 3. Tracks actions performed and sends the pixel once the target value is reached (if applicable).
    public static func fireExperimentPixelIfThresholdReached(for subfeatureID: SubfeatureID,
                                                             metric: String,
                                                             conversionWindowDays: ConversionWindow,
                                                             threshold: NumberOfCalls) {
        // Check is active experiment for user
        guard let featureFlagger = ExperimentConfig.featureFlagger else {
            assertionFailure("PixelKit is not configured for experiments")
            return
        }
        guard let experimentData = featureFlagger.allActiveExperiments[subfeatureID] else { return }

        fireExperimentPixelForActiveExperiment(subfeatureID,
                                               experimentData: experimentData,
                                               metric: metric,
                                               conversionWindowDays: conversionWindowDays,
                                               numberOfCalls: threshold)
    }

    /// Fires search-related experiment pixels for all active experiments.
    ///
    /// This function iterates through all active experiments and triggers
    /// pixel firing based on predefined search-related value and conversion window mappings.
    /// - The value and conversion windows define when and how many search actions
    ///   must occur before the pixel is fired.
    public static func fireSearchExperimentPixels() {
        let valueConversionDictionary: [NumberOfActions: [ConversionWindow]] = [
            1: [0...0, 1...1, 2...2, 3...3, 4...4, 5...5, 6...6, 7...7, 5...7],
            4: [5...7, 8...15],
            6: [5...7, 8...15],
            11: [5...7, 8...15],
            21: [5...7, 8...15],
            30: [5...7, 8...15]
        ]
        guard let featureFlagger = ExperimentConfig.featureFlagger else {
            assertionFailure("PixelKit is not configured for experiments")
            return
        }
        featureFlagger.allActiveExperiments.forEach { experiment in
            fireExperimentPixels(for:
                experiment.key,
                experimentData: experiment.value,
                metric: Constants.searchMetricValue,
                valueConversionDictionary: valueConversionDictionary
            )
        }
    }

    /// Fires app retention-related experiment pixels for all active experiments.
    ///
    /// This function iterates through all active experiments and triggers
    /// pixel firing based on predefined app retention value and conversion window mappings.
    /// - The value and conversion windows define when and how many app usage actions
    ///   must occur before the pixel is fired.
    public static func fireAppRetentionExperimentPixels() {
        let valueConversionDictionary: [NumberOfActions: [ConversionWindow]] = [
            1: [1...1, 2...2, 3...3, 4...4, 5...5, 6...6, 7...7, 5...7],
            4: [5...7, 8...15],
            6: [5...7, 8...15],
            11: [5...7, 8...15],
            21: [5...7, 8...15],
            30: [5...7, 8...15]
        ]
        guard let featureFlagger = ExperimentConfig.featureFlagger else {
            assertionFailure("PixelKit is not configured for experiments")
            return
        }
        featureFlagger.allActiveExperiments.forEach { experiment in
            fireExperimentPixels(
                for: experiment.key,
                experimentData: experiment.value,
                metric: Constants.appUseMetricValue,
                valueConversionDictionary: valueConversionDictionary
            )
        }
    }

    private static func fireExperimentPixels(
        for experiment: SubfeatureID,
        experimentData: ExperimentData,
        metric: String,
        valueConversionDictionary: [NumberOfActions: [ConversionWindow]]
    ) {
        valueConversionDictionary.forEach { value, ranges in
            ranges.forEach { range in
                fireExperimentPixelForActiveExperiment(
                    experiment,
                    experimentData: experimentData,
                    metric: metric,
                    conversionWindowDays: range,
                    numberOfCalls: value
                )
            }
        }
    }

    private static func fireExperimentPixelForActiveExperiment(_ subfeatureID: SubfeatureID,
                                                               experimentData: ExperimentData,
                                                               metric: String,
                                                               conversionWindowDays: ConversionWindow,
                                                               numberOfCalls: Int) {
        // Set parameters, event name, store key
        let event = event(for: subfeatureID, experimentData: experimentData, conversionWindowDays: conversionWindowDays, metric: metric, value: String(numberOfCalls))
        let parameters = parameters(metric: metric, conversionWindowDays: conversionWindowDays, value: String(numberOfCalls), experimentData: experimentData)
        let eventStoreKey = "\(event.name)_\(parameters.toString())"

        // Determine if the user is within the conversion window
        let isInWindow = isUserInConversionWindow(conversionWindowDays, enrollmentDate: experimentData.enrollmentDate)

        // Increment or remove based on conversion window status
        let shouldSendPixel = ExperimentConfig.eventTracker.incrementAndCheckThreshold(
            forKey: eventStoreKey,
            threshold: numberOfCalls,
            isInWindow: isInWindow
        )

        // Send the pixel only if conditions are met
        if shouldSendPixel {
            ExperimentConfig.fireFunction(event, .uniqueByNameAndParameters, false)
        }
    }

    private static func isUserInConversionWindow(
        _ conversionWindowRange: ConversionWindow,
        enrollmentDate: Date
    ) -> Bool {
        let calendar = Calendar.current
        guard let startOfWindow = enrollmentDate.addDays(conversionWindowRange.lowerBound),
              let endOfWindow = enrollmentDate.addDays(conversionWindowRange.upperBound) else {
            return false
        }

        let currentDate = calendar.startOfDay(for: Date())
        return currentDate >= calendar.startOfDay(for: startOfWindow) &&
        currentDate <= calendar.startOfDay(for: endOfWindow)
    }

    private static func event(for subfeatureID: SubfeatureID, experimentData: ExperimentData, conversionWindowDays: ConversionWindow, metric: String, value: String) -> ExperimentEvent{
        let eventName = "\(Constants.metricsEventPrefix)_\(subfeatureID)_\(experimentData.cohortID)"
        let parameters = parameters(metric: metric, conversionWindowDays: conversionWindowDays, value: value, experimentData: experimentData)
        return ExperimentEvent(name: eventName, parameters: parameters)
    }

    private static func parameters(metric: String, conversionWindowDays: ConversionWindow, value: String, experimentData: ExperimentData) -> [String: String] {
        let conversionWindowValue = (conversionWindowDays.lowerBound != conversionWindowDays.upperBound) ?
        "\(conversionWindowDays.lowerBound)-\(conversionWindowDays.upperBound)" :
        "\(conversionWindowDays.lowerBound)"
        return [
            Constants.metricKey: metric,
            Constants.conversionWindowDaysKey: conversionWindowValue,
            Constants.valueKey: value,
            Constants.enrollmentDateKey: experimentData.enrollmentDate.toYYYYMMDDInET()
        ]
    }
}

extension Date {
    public func toYYYYMMDDInET() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: self)
    }

    func addDays(_ days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: self)
    }
}
