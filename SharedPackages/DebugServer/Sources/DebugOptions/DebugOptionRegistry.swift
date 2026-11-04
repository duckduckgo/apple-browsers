//
//  DebugOptionRegistry.swift
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

public typealias DebugActionHandler = @MainActor ([String: DebugValue]) async throws -> DebugValue

/// Dispatches validated API actions to shared option providers on the main actor.
@MainActor
public final class DebugOptionRegistry {
    private struct Entry {
        let descriptor: DebugOptionDescriptor
        let availability: (String) -> DebugOptionError?
        let handlers: [String: DebugActionHandler]
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func register(_ descriptor: DebugOptionDescriptor,
                         availability: @escaping (String) -> DebugOptionError? = { _ in nil },
                         handlers: [String: DebugActionHandler]) throws {
        guard entries[descriptor.id] == nil else {
            throw DebugOptionError(code: .conflict, message: "Duplicate debug option: \(descriptor.id)")
        }
        guard Set(descriptor.actions.map(\.id)) == Set(handlers.keys),
              descriptor.actions.count == handlers.count else {
            throw DebugOptionError(code: .conflict, message: "Each action must have exactly one handler.")
        }
        entries[descriptor.id] = Entry(descriptor: descriptor, availability: availability, handlers: handlers)
    }

    public func discover() -> [DebugOptionDescriptor] {
        entries.values.map { entry in
            var descriptor = entry.descriptor
            descriptor.actions = descriptor.actions.map { action in
                var result = action
                result.unavailableReason = entry.availability(action.id)?.message
                return result
            }
            return descriptor
        }.sorted { $0.id < $1.id }
    }

    public func execute(_ invocation: DebugOptionInvocation) async throws -> DebugValue {
        try Task.checkCancellation()
        guard let entry = entries[invocation.id] else {
            throw DebugOptionError(code: .unknownOption, message: "Unknown debug option: \(invocation.id)")
        }
        guard let action = entry.descriptor.actions.first(where: { $0.id == invocation.action }),
              let handler = entry.handlers[invocation.action] else {
            throw DebugOptionError(code: .unsupportedAction, message: "Unsupported action: \(invocation.action)")
        }
        try action.parametersSchema.validate(invocation.parameters)
        if let error = entry.availability(invocation.action) { throw error }
        return try await handler(invocation.parameters)
    }
}
