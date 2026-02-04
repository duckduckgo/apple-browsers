//
//  WideEventParameters.swift
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

import Foundation

public protocol WideEventParameterProviding {
    func pixelParameters() -> [String: String]
    func jsonParameters() -> [String: Encodable]
}

public extension WideEventParameterProviding {
    func jsonParameters() -> [String: Encodable] {
        // Allows all event types to get JSON endpoint support for free.
        // This only needs to be overriden by objects that don't want to return string values in their JSON
        // bodies, such as the sample_rate value for global data objects.
        return pixelParameters()
    }
}

public enum WideEventParameter {

    public enum Meta {
        static let type = "meta.type"
        static let version = "meta.version"
    }

    public enum Global {
        static let platform = "global.platform"
        static let type = "global.type"
        static let sampleRate = "global.sample_rate"
        static let isFirstDailyOccurrence = "global.is_first_daily_occurrence"
    }

    public enum App {
        static let name = "app.name"
        static let version = "app.version"
        static let formFactor = "app.form_factor"
        static let internalUser = "app.internal_user"
    }

    public enum Context {
        static let name = "context.name"
    }

    public enum Feature {
        public static let name = "feature.name"
        public static let status = "feature.status"
        public static let statusReason = "feature.data.ext.status_reason"

        public static let errorDomain = "feature.data.error.domain"
        public static let errorCode = "feature.data.error.code"
        public static let errorDescription = "feature.data.error.description"
        public static let underlyingErrorDomain = "feature.data.error.underlying_domain"
        public static let underlyingErrorCode = "feature.data.error.underlying_code"
    }
}
