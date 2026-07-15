//
//  PageContextAttachabilityPolicy.swift
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

public struct PageContextAttachabilityVerdict: Equatable {
    public let isAttachable: Bool
    public let preventionReason: String?

    static let attachable = PageContextAttachabilityVerdict(isAttachable: true, preventionReason: nil)

    static func prevented(_ reason: String) -> PageContextAttachabilityVerdict {
        PageContextAttachabilityVerdict(isAttachable: false, preventionReason: reason)
    }
}

public struct PageContextAttachabilityPolicy {
    private let settings: PageContextBlocklistSettings

    public init(settings: PageContextBlocklistSettings) {
        self.settings = settings
    }

    public func verdict(url: URL?, mimeType: String?) -> PageContextAttachabilityVerdict {
        guard let url else {
            return .prevented(PageContextExtractionOutcome.internalPageCategory)
        }
        if url.absoluteString == "about:blank" || url.isDuckAIURL {
            return .prevented(PageContextExtractionOutcome.internalPageCategory)
        }

        if let mimeType, !mimeType.isEmpty {
            if let category = category(forMIMEType: mimeType) {
                return .prevented(category)
            }
            return .attachable
        }

        if let category = category(forExtension: url.pathExtension) {
            return .prevented(category)
        }

        return .attachable
    }

    private func category(forMIMEType mimeType: String) -> String? {
        let lowered = mimeType.lowercased()
        for (name, rule) in settings.categories {
            if rule.contentTypes?.contains(where: { $0.lowercased() == lowered }) == true {
                return name
            }
            if rule.contentTypePrefixes?.contains(where: { lowered.hasPrefix($0.lowercased()) }) == true {
                return name
            }
        }
        return nil
    }

    private func category(forExtension pathExtension: String) -> String? {
        guard !pathExtension.isEmpty else { return nil }
        let dotted = "." + pathExtension.lowercased()
        for (name, rule) in settings.categories where rule.urlExtensions?.contains(where: { $0.lowercased() == dotted }) == true {
            return name
        }
        return nil
    }
}
