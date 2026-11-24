//
//  LaunchSettings.swift
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

/// The settings a launch profile may use. Applies a profile all or nothing, in catalog order.
public struct LaunchSettings {

    private let settings: [LaunchSetting]
    private let settingsByKey: [String: LaunchSetting]

    public init(_ settings: [LaunchSetting]) {
        self.settings = settings
        self.settingsByKey = Dictionary(settings.map { ($0.key, $0) }) { first, _ in
            preconditionFailure("Launch setting \"\(first.key)\" is declared twice.")
        }
    }

    public func apply(_ profile: LaunchProfile) -> LaunchProfileOutcome {
        let (plan, problems) = makePlan(for: profile)
        guard problems.isEmpty else { return .rejected(problems) }
        return run(plan)
    }

    // MARK: - Planning

    private struct PlannedWrite {
        let key: String
        let write: () throws -> Void
    }

    private func makePlan(for profile: LaunchProfile) -> (plan: [PlannedWrite], problems: [LaunchProfileProblem]) {
        var values: [String: LaunchProfileValue] = [:]
        var problems: [LaunchProfileProblem] = []
        collect(profile.root, under: nil, into: &values, problems: &problems)
        problems += unmetRequirements(in: values)

        var plan: [PlannedWrite] = []
        for setting in settings {
            guard let value = values[setting.key] else { continue }
            do {
                plan.append(PlannedWrite(key: setting.key, write: try setting.prepare(value)))
            } catch {
                problems.append(invalidValue(error, for: setting))
            }
        }
        return (plan, problems.sorted { ($0.key ?? "", $0.message) < ($1.key ?? "", $1.message) })
    }

    /// Walks the JSON: a path naming a setting is a value; any other object is walked further.
    private func collect(_ object: [String: LaunchProfileValue],
                         under parent: String?,
                         into values: inout [String: LaunchProfileValue],
                         problems: inout [LaunchProfileProblem]) {
        for (name, value) in object {
            let path = parent.map { "\($0).\(name)" } ?? name
            if settingsByKey[path] != nil {
                if values.updateValue(value, forKey: path) != nil {
                    problems.append(LaunchProfileProblem(key: path, message: "\"\(path)\" is set twice."))
                }
            } else if case .object(let children) = value, !children.isEmpty {
                collect(children, under: path, into: &values, problems: &problems)
            } else {
                problems.append(unknownKey(path))
            }
        }
    }

    private func unmetRequirements(in values: [String: LaunchProfileValue]) -> [LaunchProfileProblem] {
        values.keys.flatMap { key in
            (settingsByKey[key]?.requirements ?? [:])
                .filter { values[$0.key] != $0.value }
                .map { requiredKey, requiredValue in
                    LaunchProfileProblem(key: key,
                                         message: "\"\(key)\" needs \"\(requiredKey)\": \(requiredValue.jsonText) in the same profile.")
                }
        }
    }

    // MARK: - Applying

    private func run(_ plan: [PlannedWrite]) -> LaunchProfileOutcome {
        var applied: [String] = []
        var problems: [LaunchProfileProblem] = []
        for step in plan {
            do {
                try step.write()
                applied.append(step.key)
            } catch {
                problems.append(LaunchProfileProblem(key: step.key, message: "\"\(step.key)\" failed: \(error)"))
            }
        }
        return problems.isEmpty ? .applied(keys: applied) : .partiallyApplied(keys: applied, problems: problems)
    }

    // MARK: - Problems

    private func invalidValue(_ error: Error, for setting: LaunchSetting) -> LaunchProfileProblem {
        let message = error is DecodingError
            ? "\"\(setting.key)\" expects \(setting.valueType)."
            : "\"\(setting.key)\" is invalid: \(error)"
        return LaunchProfileProblem(key: setting.key, message: message)
    }

    private func unknownKey(_ path: String) -> LaunchProfileProblem {
        LaunchProfileProblem(key: path, message: "Unknown key \"\(path)\".")
    }
}

private extension LaunchProfileValue {

    var jsonText: String {
        guard let data = try? JSONEncoder().encode(self), let text = String(bytes: data, encoding: .utf8) else { return "\(self)" }
        return text
    }
}
