//
//  PreviewSnapshots.swift
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

import SwiftUI

public struct PreviewSnapshotScope: OptionSet, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let previews = PreviewSnapshotScope(rawValue: 1 << 0)
    public static let snapshots = PreviewSnapshotScope(rawValue: 1 << 1)
    public static let all: PreviewSnapshotScope = [.previews, .snapshots]
}

public struct PreviewSnapshots<State> {
    public let configurations: [Configuration]
    public let configure: (State) -> AnyView

    public init<Content: View>(
        configurations: [Configuration],
        configure: @escaping (State) -> Content
    ) {
        self.configurations = configurations
        self.configure = { AnyView(configure($0)) }
    }

    public init<Content: View>(
        states: [State],
        configure: @escaping (State) -> Content
    ) where State: NamedPreviewState {
        self.init(states: states, name: \.name, configure: configure)
    }

    public init<Content: View>(
        states: [State],
        name namePath: KeyPath<State, String>,
        configure: @escaping (State) -> Content
    ) {
        self.init(
            configurations: states.map { Configuration(name: $0[keyPath: namePath], state: $0) },
            configure: configure
        )
    }

    public var previewConfigurations: [Configuration] {
        configurations.filter { $0.scope.contains(.previews) }
    }

    public var snapshotConfigurations: [Configuration] {
        configurations.filter { $0.scope.contains(.snapshots) }
    }

    public var previews: some View {
        ForEach(Array(previewConfigurations.enumerated()), id: \.offset) { _, configuration in
            preview(for: configuration)
        }
    }

    @ViewBuilder
    private func preview(for configuration: Configuration) -> some View {
        if configuration.name.isEmpty {
            configure(configuration.state)
        } else {
            configure(configuration.state)
                .previewDisplayName(configuration.name)
        }
    }
}

public extension PreviewSnapshots {
    struct Configuration {
        public let name: String
        public let state: State
        public let scope: PreviewSnapshotScope

        public init(
            name: String,
            state: State,
            scope: PreviewSnapshotScope = .all
        ) {
            self.name = name
            self.state = state
            self.scope = scope
        }
    }
}

public protocol NamedPreviewState {
    var name: String { get }
}
