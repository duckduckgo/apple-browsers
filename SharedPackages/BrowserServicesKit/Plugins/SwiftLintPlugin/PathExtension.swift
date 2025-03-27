//
//  PathExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import PackagePlugin

extension Path {

    static let mv = Path("/bin/mv")
    static let echo = Path("/bin/echo")
    static let cat = Path("/bin/cat")
    static let sh = Path("/bin/sh")

    private static let swiftlintConfig = ".swiftlint.yml"

    /// Scans the receiver, then all of its parents looking for a configuration file with the name ".swiftlint.yml".
    ///
    /// - returns: Path to the configuration file, or nil if one cannot be found.
    func firstParentContainingConfigFile() -> Path? {
        let proposedDirectory = sequence(
            first: self,
            next: { path in
                guard path.stem.count > 1 else {
                    // Check we're not at the root of this filesystem, as `removingLastComponent()`
                    // will continually return the root from itself.
                    return nil
                }

                return path.removingLastComponent()
            }
        ).first { path in
            let potentialConfigurationFile = path.appending(subpath: Self.swiftlintConfig)
            return potentialConfigurationFile.isAccessible()
        }
        return proposedDirectory
    }

    /// Safe way to check if the file is accessible from within the current process sandbox.
    private func isAccessible() -> Bool {
        let result = string.withCString { pointer in
            access(pointer, R_OK)
        }

        return result == 0
    }

    /// Get file modification date
    var modified: Date {
        get throws {
            try FileManager.default.attributesOfItem(atPath: self.string)[.modificationDate] as? Date ?? { throw CocoaError(.fileReadUnknown) }()
        }
    }

    var url: URL {
        URL(fileURLWithPath: self.string)
    }

}
