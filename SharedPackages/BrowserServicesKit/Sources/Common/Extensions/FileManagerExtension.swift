//
//  FileManagerExtension.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

extension FileManager {

    public func applicationSupportDirectoryForComponent(named name: String) -> URL {
#if os(macOS)
        let sandboxPathComponent = "Containers/\(Bundle.main.bundleIdentifier!)/Data/Library/Application Support/"
        let libraryURL = urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = libraryURL.appendingPathComponent(sandboxPathComponent)
#else
        guard let dir = urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find application support directory")
        }
#endif
        return dir.appendingPathComponent(name)
    }

    public var diagnosticsDirectory: URL {
        applicationSupportDirectoryForComponent(named: "Diagnostics")
    }

}
