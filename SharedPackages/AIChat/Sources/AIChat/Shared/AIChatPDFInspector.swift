//
//  AIChatPDFInspector.swift
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

import CoreGraphics
import Foundation

/// Outcome of inspecting a PDF's bytes for page-count / readability. Drives attachment
/// validation (page-count limit, encrypted / unreadable rejection) on both iOS and macOS.
public enum AIChatPDFInspectionResult: Sendable, Equatable {
    case notPDF
    case readable(pageCount: Int)
    case encrypted
    case unreadable

    public var pageCount: Int? {
        guard case .readable(let pageCount) = self else { return nil }
        return pageCount
    }

    public var isEncrypted: Bool {
        guard case .encrypted = self else { return false }
        return true
    }
}

/// Inspects PDF bytes via CoreGraphics. Platform-agnostic (CoreGraphics is available on both
/// iOS and macOS) so iOS and macOS share one implementation rather than maintaining parallel copies.
public enum AIChatPDFInspector {

    public static func inspect(data: Data, mimeType: String) -> AIChatPDFInspectionResult {
        guard mimeType == "application/pdf" else { return .notPDF }
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            return .unreadable
        }
        guard document.isEncrypted == false || document.isUnlocked else {
            return .encrypted
        }

        let pageCount = document.numberOfPages
        guard pageCount > 0 else { return .unreadable }
        return .readable(pageCount: pageCount)
    }
}
