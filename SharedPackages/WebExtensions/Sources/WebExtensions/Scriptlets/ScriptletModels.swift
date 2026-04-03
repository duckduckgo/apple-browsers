//
//  ScriptletModels.swift
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

public enum ScriptletAvailability: Equatable {
    case notAvailable
    case available([Scriptlet])
    case updating([Scriptlet])
}

public struct Scriptlet: Equatable, Codable {
    /// The original path from the descriptor, used as the installation target path.
    public let path: String

    /// The path to the cached file, relative to the cache root directory.
    public let relativeCachedPath: String

    public init(path: String, relativeCachedPath: String) {
        self.path = path
        self.relativeCachedPath = relativeCachedPath
    }
}

public struct ScriptletManifest: Equatable, Codable {
    public let version: String
    public let scriptlets: [ScriptletDescriptor]

    public init(version: String, scriptlets: [ScriptletDescriptor]) {
        self.version = version
        self.scriptlets = scriptlets
    }
}

public struct ScriptletDescriptor: Equatable, Codable {
    public let name: String
    public let url: URL
    public let signature: String

    public init(name: String, url: URL, signature: String) {
        self.name = name
        self.url = url
        self.signature = signature
    }
}

public struct FetchedScriptlet {
    public let descriptor: ScriptletDescriptor
    public let data: Data

    public init(descriptor: ScriptletDescriptor, data: Data) {
        self.descriptor = descriptor
        self.data = data
    }
}

public struct CachedScriptlets: Equatable, Codable {
    public let version: String
    public let scriptlets: [Scriptlet]

    public init(version: String, scriptlets: [Scriptlet]) {
        self.version = version
        self.scriptlets = scriptlets
    }
}

public struct ScriptletCacheMetadata: Codable, Equatable {
    public var extensions: [String: CachedScriptlets]

    public init(extensions: [String: CachedScriptlets] = [:]) {
        self.extensions = extensions
    }
}
