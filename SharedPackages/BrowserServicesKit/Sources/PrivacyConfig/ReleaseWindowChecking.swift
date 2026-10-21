//
//  ReleaseWindowChecking.swift
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

public protocol ReleaseWindowChecking {}

public extension ReleaseWindowChecking {
    func isWithinReleaseWindow(minimumVersion: String,
                               currentAppVersion: String,
                               maxMinorReleaseOffset: Int) -> Bool {
        let minVersion = parse(versionString: minimumVersion)
        let currentVersion = parse(versionString: currentAppVersion)

        guard let maxVersion = maximumVersion(from: minVersion, byMinorReleaseOffset: maxMinorReleaseOffset) else {
            return false
        }

        return compareVersions(minVersion, currentVersion) != .orderedDescending &&
            compareVersions(currentVersion, maxVersion) == .orderedAscending
    }
}

private extension ReleaseWindowChecking {
    func parse(versionString: String) -> [Int] {
        versionString.split(separator: ".").map { Int($0) ?? 0 }
    }

    func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let lhsSegment = index < lhs.count ? lhs[index] : 0
            let rhsSegment = index < rhs.count ? rhs[index] : 0

            if lhsSegment < rhsSegment {
                return .orderedAscending
            }
            if lhsSegment > rhsSegment {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    func maximumVersion(from minimumVersion: [Int], byMinorReleaseOffset offset: Int) -> [Int]? {
        guard minimumVersion.count == 3 else { return nil }

        var result = minimumVersion
        result[1] += offset
        result[2] = 0

        return result
    }
}
