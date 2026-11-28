//
//  BrowserToolBookmarkFolder.swift
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

public enum BrowserToolBookmarkFolder {
    public static let maxDepth = 10
    public static let maxNameLength = 256

    public static func folderPath(from arguments: JSONValue?) -> [String]? {
        guard let value = arguments?["folder"], value != .null else { return [] }
        guard let values = value.arrayValue, (1...maxDepth).contains(values.count) else { return nil }
        let names = values.compactMap { value -> String? in
            guard let name = value.stringValue, (1...maxNameLength).contains(name.unicodeScalars.count) else { return nil }
            return name
        }
        return names.count == values.count ? names : nil
    }

    static func contents<Node>(of path: [String], in root: [Node],
                               childrenOfFolderNamed: (Node, String) -> [Node]?) -> [Node] {
        var contents = root
        for name in path {
            var folderContents: [Node]?
            for node in contents {
                if let children = childrenOfFolderNamed(node, name) {
                    folderContents = children
                    break
                }
            }
            guard let folderContents else { return [] }
            contents = folderContents
        }
        return contents
    }
}
