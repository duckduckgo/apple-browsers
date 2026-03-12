//
//  AttributionXattrCanaryValidator.swift
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
import PixelKit

/// Compares file-based and xattr-based attribution values and fires a one-time canary pixel
/// so we can validate that xattrs survive the DMG distribution pipeline.
final class AttributionXattrCanaryValidator {

    func validateAndReport(bundle: Bundle = .main) {
        let variantFile = readFile("variant", bundle: bundle)
        let variantXattr = getXattr(named: "com.duckduckgo.variant", from: bundle.bundlePath)
        let originFile = readFile("Origin", bundle: bundle)
        let originXattr = getXattr(named: "com.duckduckgo.origin", from: bundle.bundlePath)

        // Skip vanilla installs — no attribution data from either source
        guard [variantFile, variantXattr, originFile, originXattr].contains(where: { $0 != nil }) else { return }

        PixelKit.fire(
            GeneralPixel.attributionXattrCanary(
                variantMatch: match(variantFile, variantXattr),
                originMatch: match(originFile, originXattr)
            ),
            frequency: .uniqueByName
        )
    }

    // MARK: - Private

    private func readFile(_ name: String, bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: "txt"),
              let value = try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// Returns a human-readable match result for the pixel parameters.
    private func match(_ file: String?, _ xattr: String?) -> String {
        switch (file, xattr) {
        case let (f?, x?) where f == x:
            return "match"
        case (_?, _?):
            return "mismatch"
        case (_?, nil):
            return "file_only"
        case (nil, _?):
            return "xattr_only"
        case (nil, nil):
            return "both_nil"
        }
    }
}
