//
//  AttributedMetricOriginFileProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Darwin
import Foundation

func getXattr(named name: String, from path: String) -> String? {
    let length = getxattr(path, name, nil, 0, 0, 0)
    guard length > 0 else { return nil }
    var data = Data(count: length)
    let result = data.withUnsafeMutableBytes {
        getxattr(path, name, $0.baseAddress, length, 0, 0)
    }
    guard result >= 0 else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A type that provides the `origin` used to anonymously track installations without tracking retention.
public protocol AttributedMetricOriginProvider: AnyObject {
    /// A string representing the acquisition funnel.
    var origin: String? { get }
}

#if os(macOS)
public final class AttributedMetricOriginFileProvider: AttributedMetricOriginProvider {
    public let origin: String?

    /// Creates an instance that reads the origin from an xattr on the bundle path.
    /// - Parameters:
    ///   - xattrName: The xattr name to read (set by the variant DMG pipeline).
    ///   - bundle: The bundle whose path is checked for the xattr.
    public init(xattrName: String = "com.duckduckgo.origin", bundle: Bundle = .main) {
        origin = getXattr(named: xattrName, from: bundle.bundlePath)
    }
}
#endif
