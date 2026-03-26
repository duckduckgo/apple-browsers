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
    public let name: String
    public let content: Data

    public init(name: String, content: Data) {
        self.name = name
        self.content = content
    }

    public var contentString: String? {
        String(data: content, encoding: .utf8)
    }

    public var fileName: String {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        return safeName.hasSuffix(".js") ? safeName : "\(safeName).js"
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

public struct CachedScriptlets {
    public let version: String
    public let scriptlets: [Scriptlet]

    public init(version: String, scriptlets: [Scriptlet]) {
        self.version = version
        self.scriptlets = scriptlets
    }
}

public struct ScriptletCacheMetadata: Codable, Equatable {
    public var extensions: [String: ExtensionScriptletMetadata]

    public init(extensions: [String: ExtensionScriptletMetadata] = [:]) {
        self.extensions = extensions
    }
}

public struct ExtensionScriptletMetadata: Codable, Equatable {
    public let extensionType: String
    public let version: String
    public let scriptlets: [ScriptletFileMetadata]

    public init(extensionType: String, version: String, scriptlets: [ScriptletFileMetadata]) {
        self.extensionType = extensionType
        self.version = version
        self.scriptlets = scriptlets
    }
}

public struct ScriptletFileMetadata: Codable, Equatable {
    public let targetPath: String
    public let cachedFileName: String

    public init(targetPath: String, cachedFileName: String) {
        self.targetPath = targetPath
        self.cachedFileName = cachedFileName
    }
}
