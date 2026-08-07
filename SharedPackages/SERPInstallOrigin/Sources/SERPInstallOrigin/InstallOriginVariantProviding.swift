//
//  InstallOriginVariantProviding.swift
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

/// Supplies the install-origin variant for a SERP campaign query.
public protocol InstallOriginVariantProviding: AnyObject {

    /// Returns the variant string for the given campaign, or `nil` when ineligible.
    ///
    /// - Parameter campaign: Campaign identifier from the SERP request.
    /// - Returns: The `content` segment of the install-origin xattr when all
    ///   eligibility gates pass; otherwise `nil`.
    func installOriginVariant(forCampaign campaign: String?) -> String?
}

/// Request payload for the `getInstallOriginVariant` SERP bridge message.
public struct GetInstallOriginVariantRequest: Decodable {
    public let campaign: String?
}

/// Response payload for the `getInstallOriginVariant` SERP bridge message.
public struct GetInstallOriginVariantResponse: Encodable, Equatable {
    public let variant: String?

    public init(variant: String?) {
        self.variant = variant
    }
}
