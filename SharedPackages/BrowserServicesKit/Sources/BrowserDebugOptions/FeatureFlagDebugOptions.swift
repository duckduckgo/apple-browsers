//
//  FeatureFlagDebugOptions.swift
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

import Combine
import DebugOptions
import Foundation
import PrivacyConfig

/// Shared by the platform's feature flag menu and the debug API.
@MainActor
public final class FeatureFlagDebugOptions<Flag: FeatureFlagDescribing> {
    public let featureFlagger: FeatureFlagger
    private let flags: [Flag]
    private let requiresRelaunch: (Flag) -> Bool
    private let changeSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    public var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    public init(featureFlagger: FeatureFlagger, flags: [Flag], requiresRelaunch: @escaping (Flag) -> Bool = { _ in false }) {
        self.featureFlagger = featureFlagger
        self.flags = flags.filter { $0.supportsLocalOverriding }
        self.requiresRelaunch = requiresRelaunch
        featureFlagger.updatesPublisher.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.changeSubject.send()
        }.store(in: &cancellables)
        featureFlagger.internalUserDecider.isInternalUserPublisher.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.changeSubject.send()
        }.store(in: &cancellables)
    }

    public func setEnabled(_ enabled: Bool, for flag: some FeatureFlagDescribing) throws {
        try requireMutable(flag)
        guard flag.cohortType == nil else {
            throw DebugOptionError(code: .invalidParameters, message: "Use the cohort option for an experiment.")
        }
        featureFlagger.localOverrides?.setOverride(enabled, for: flag)
        changeSubject.send()
    }

    public func setCohort(_ cohort: String, for flag: some FeatureFlagDescribing) throws {
        try requireMutable(flag)
        guard flag.cohortType?.cohorts.contains(where: { $0.rawValue == cohort }) == true else {
            throw DebugOptionError(code: .invalidParameters, message: "Unknown experiment cohort: \(cohort)")
        }
        featureFlagger.localOverrides?.setExperimentCohortOverride(for: flag, cohort: cohort)
        changeSubject.send()
    }

    public func reset(_ flag: some FeatureFlagDescribing) throws {
        try requireMutable(flag)
        featureFlagger.localOverrides?.clearOverride(for: flag)
        changeSubject.send()
    }

    public func resetAll() throws {
        if let reason = mutationUnavailableReason {
            throw DebugOptionError(code: .unavailable, message: reason)
        }
        featureFlagger.localOverrides?.clearAllOverrides(for: Flag.self)
        changeSubject.send()
    }

    public func activation(for flag: Flag) -> String {
        requiresRelaunch(flag) ? "nextLaunch" : "nextFeatureEvaluation"
    }

    public func state(for flag: Flag) -> DebugValue {
        let override: DebugValue
        let base: DebugValue
        let resolved: DebugValue
        if flag.cohortType == nil {
            override = featureFlagger.localOverrides?.override(for: flag).map(DebugValue.bool) ?? .null
            base = .bool(featureFlagger.isFeatureOn(for: flag, allowOverride: false))
            resolved = .bool(featureFlagger.isFeatureOn(for: flag))
        } else {
            override = featureFlagger.localOverrides?.experimentOverride(for: flag).map(DebugValue.string) ?? .null
            base = featureFlagger.assignedCohort(for: flag, allowOverride: false).map { .string($0.rawValue) } ?? .null
            resolved = featureFlagger.assignedCohort(for: flag).map { .string($0.rawValue) } ?? .null
        }
        return .object([
            "overrideValue": override, "baseValue": base, "resolvedValue": resolved,
            "overridesEnabled": .bool(featureFlagger.internalUserDecider.isInternalUser),
            "activation": .string(activation(for: flag)),
        ])
    }

    public func register(in registry: DebugOptionRegistry) throws {
        for flag in flags {
            let id = "featureFlags.\(flag.rawValue)" + (flag.cohortType == nil ? "" : ".cohort")
            let schema = DebugValueSchema(type: flag.cohortType == nil ? .boolean : .string,
                                          enumValues: flag.cohortType?.cohorts.map { $0.rawValue })
            let descriptor = DebugOptionDescriptor(id: id, title: flag.rawValue, group: "Feature Flags", activation: activation(for: flag), actions: [
                .init(id: "get", description: "Read the override, base value, and resolved value without assigning a cohort."),
                .init(id: "set", description: "Save an explicit local override.",
                      parametersSchema: .init(properties: ["value": schema], required: ["value"])),
                .init(id: "reset", description: "Remove this override and use the normal feature flag value."),
            ])
            try registry.register(descriptor, availability: { [self] action in
                action == "get" ? nil : mutationUnavailableReason.map { DebugOptionError(code: .unavailable, message: $0) }
            }, handlers: [
                "get": { [self] _ in state(for: flag) },
                "set": { [self] parameters in
                    switch parameters["value"] {
                    case .bool(let enabled): try setEnabled(enabled, for: flag)
                    case .string(let cohort): try setCohort(cohort, for: flag)
                    default: throw DebugOptionError(code: .invalidParameters, message: "A value is required.")
                    }
                    return state(for: flag)
                },
                "reset": { [self] _ in
                    try reset(flag)
                    return state(for: flag)
                },
            ])
        }
    }

    private var mutationUnavailableReason: String? {
        guard featureFlagger.internalUserDecider.isInternalUser else { return "Enable general.internalUser first." }
        guard featureFlagger.localOverrides != nil else { return "Local feature flag overrides are unavailable." }
        return nil
    }

    private func requireMutable(_ flag: some FeatureFlagDescribing) throws {
        guard flags.contains(where: { $0.rawValue == flag.rawValue }), flag.supportsLocalOverriding else {
            throw DebugOptionError(code: .unavailable, message: "This flag does not support local overriding.")
        }
        if let reason = mutationUnavailableReason {
            throw DebugOptionError(code: .unavailable, message: reason)
        }
    }
}
