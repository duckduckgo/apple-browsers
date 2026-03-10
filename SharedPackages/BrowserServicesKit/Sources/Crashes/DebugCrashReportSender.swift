//
//  DebugCrashReportSender.swift
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

import Common
import Foundation
import os.log

/// A `CrashReportSending` implementation that does not send crash reports to the crash reporting endpoint.
/// Used in DEBUG and REVIEW builds to avoid sending noisy crash reports to Sentry.
public final class DebugCrashReportSender: CrashReportSending {

    public var pixelEvents: EventMapping<CrashReportSenderError>?

    public init(platform: CrashCollectionPlatform, pixelEvents: EventMapping<CrashReportSenderError>?) {
        self.pixelEvents = pixelEvents
    }

    public func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?) {
        return (.success(nil), nil)
    }

    public func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void) {
        completion(.success(nil), nil)
    }

}
