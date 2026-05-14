//
//  DuckAiNativeStoragePixelFiring.swift
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

public enum DuckAiNativeStorageEvent {
    // Initialization
    case initSuccess
    case initError(Error)

    // Migration
    case migrationDone(key: String)
    case migrationDoneBlankKey
    case migrationStarted
    case migrationAlreadyDone
    case migrationError(Error)

    // Entries errors (previously Settings)
    case settingsPutError(Error)
    case settingsGetError(Error)
    case settingsDeleteError(Error)

    // Chat errors
    case chatPutError(Error)
    case chatGetError(Error)
    case chatDeleteError(Error)

    // File errors
    case filePutError(Error)
    case fileGetError(Error)
    case fileListError(Error)
    case fileDeleteError(Error)
}

public protocol DuckAiNativeStoragePixelFiring {
    func fire(_ event: DuckAiNativeStorageEvent)
}

public struct NullDuckAiNativeStoragePixelFiring: DuckAiNativeStoragePixelFiring {
    public init() {}
    public func fire(_ event: DuckAiNativeStorageEvent) {}
}
