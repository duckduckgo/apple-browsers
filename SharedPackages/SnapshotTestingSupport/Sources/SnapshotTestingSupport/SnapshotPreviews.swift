//
//  SnapshotPreviews.swift
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

public struct SnapshotPreviewConfiguration<State> {
    public let name: String
    public let state: State
    public let isEnabled: Bool

    public init(
        name: String,
        state: State,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.state = state
        self.isEnabled = isEnabled
    }
}

public struct SnapshotPreviews<State> {
    public let configurations: [SnapshotPreviewConfiguration<State>]
    public let configure: (State) -> AnyView

    public init<Content: View>(
        configurations: [SnapshotPreviewConfiguration<State>],
        configure: @escaping (State) -> Content
    ) {
        self.configurations = configurations
        self.configure = { AnyView(configure($0)) }
    }
}

public protocol SnapshotPreviewProvider {
    associatedtype State

    static var snapshotPreviews: SnapshotPreviews<State> { get }
}
