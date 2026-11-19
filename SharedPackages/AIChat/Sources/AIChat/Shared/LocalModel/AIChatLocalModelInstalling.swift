//
//  AIChatLocalModelInstalling.swift
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
import Foundation

/// Why setting up a downloadable model failed, as `submitAIChatLocalModelState` reports it.
public enum AIChatLocalModelSetupError: String, Codable, Equatable, Sendable {
    case network
    case diskFull = "disk_full"
    case unknown
}

public enum AIChatLocalModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(receivedBytes: Int64, totalBytes: Int64)
    case installed(URL)
    case failed(AIChatLocalModelSetupError)

    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Downloads and removes the model file a llama.cpp engine runs.
@MainActor
public protocol AIChatLocalModelInstalling: AnyObject {
    var spec: AIChatLocalModelSpec { get }
    var state: AIChatLocalModelInstallState { get }
    var statePublisher: AnyPublisher<AIChatLocalModelInstallState, Never> { get }

    /// Starts or continues the download, and remembers the request so it continues after a relaunch.
    func install()
    /// The user stopped the download: deletes what was downloaded.
    func cancel()
    /// Deletes the model.
    func uninstall()
    /// Stops for now and keeps what was downloaded, for example while the feature flag is off.
    func pause()
    /// Continues a download the user asked for before the app quit or `pause()` was called.
    func resumeIfNeeded()
}
