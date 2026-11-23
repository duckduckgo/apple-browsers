//
//  BrowserToolsInstrumentation.swift
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

/// What let a call run or stopped it. Raw values are the `permission_path` pixel values.
public enum BrowserToolPermissionPath: String, Equatable, Sendable {
    /// The tool doesn't ask.
    case auto
    /// Stored Always allow.
    case always
    /// Allowed for this chat earlier.
    case chat
    /// The user was asked for this call.
    case prompt
    /// Stored Never allow.
    case never
    /// Refused before permission was looked at.
    case beforePermission = "none"
}

/// How a tool call went through the invoker, for instrumentation.
public struct BrowserToolCallTrace: Equatable, Sendable {
    public var permissionPath: BrowserToolPermissionPath
    /// Seconds the tool ran, without the wait for permission. Nil when it never ran.
    public var executionDuration: TimeInterval?

    public init(permissionPath: BrowserToolPermissionPath = .beforePermission, executionDuration: TimeInterval? = nil) {
        self.permissionPath = permissionPath
        self.executionDuration = executionDuration
    }
}

@MainActor
public protocol BrowserToolsInstrumentation {
    /// A finished tool call, other than `requestAccess` or one from a Fire window.
    /// - Parameter response: the reply Duck.ai gets, after the size limit.
    func toolCallDidFinish(tool: String, response: ExecuteClientToolResponse, trace: BrowserToolCallTrace)
}
