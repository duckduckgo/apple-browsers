//
//  MemoryPressureMonitor.swift
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

public enum MemoryPressureLevel: String, Sendable {
    /// No event received since launch.
    case unknown
    case normal
    case warning
    case critical
}

public protocol MemoryPressureProviding: AnyObject {
    /// Returns `nil` when collecting memory pressure is disabled.
    var currentLevel: MemoryPressureLevel? { get }
}

/// The source only reports transitions, so it must be created at launch to know the current level.
public final class MemoryPressureMonitor: MemoryPressureProviding {

    private let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical],
                                                                 queue: DispatchQueue(label: "com.duckduckgo.page-signals.memory-pressure-monitor"))
    private let isEnabledProvider: () -> Bool
    private let lock = NSLock()
    private var level: MemoryPressureLevel = .unknown

    public init(isEnabledProvider: @escaping () -> Bool) {
        self.isEnabledProvider = isEnabledProvider

        source.setEventHandler { [weak self] in
            guard let self else { return }
            handle(source.data)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    public var currentLevel: MemoryPressureLevel? {
        guard isEnabledProvider() else {
            return nil
        }

        return lock.withLock { level }
    }

    func handle(_ event: DispatchSource.MemoryPressureEvent) {
        let newLevel: MemoryPressureLevel = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal

        lock.withLock { level = newLevel }
    }
}
