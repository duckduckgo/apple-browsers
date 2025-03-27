//
//  CrashReportSender.swift
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
import MetricKit
import Common
import os.log

public protocol CrashReportSending {
    var pixelEvents: EventMapping<CrashReportSenderError>? { get }

    init(platform: CrashCollectionPlatform, pixelEvents: EventMapping<CrashReportSenderError>?)

    func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?)
    func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void)
}

public enum CrashReportSenderError: Error {
    case crcidMissing
    case submissionFailed(HTTPURLResponse?)
}

public final class CrashReportSender: CrashReportSending {
    static let reportServiceUrl = URL(string: "https://duckduckgo.com/crash.js")!

    static let httpHeaderCRCID = "crcid"

    public let platform: CrashCollectionPlatform
    public var pixelEvents: EventMapping<CrashReportSenderError>?

    private let session = URLSession(configuration: .ephemeral)

    public init(platform: CrashCollectionPlatform, pixelEvents: EventMapping<CrashReportSenderError>?) {
        self.platform = platform
        self.pixelEvents = pixelEvents
    }

    public func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void) {
        var request = URLRequest(url: Self.reportServiceUrl)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(platform.userAgent, forHTTPHeaderField: "User-Agent")

        let crcidHeaderValue = crcid ?? ""
        request.setValue(crcidHeaderValue, forHTTPHeaderField: CrashReportSender.httpHeaderCRCID)
        Logger.general.debug("Configured crash report HTTP request with crcid: \(crcidHeaderValue)")

        request.httpMethod = "POST"
        request.httpBody = crashReportData

        Logger.general.debug("CrashReportSender: Awaiting session data")
        let task = session.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse {
                Logger.general.debug("CrashReportSender: Received HTTP response code: \(response.statusCode)")
                if response.statusCode == 200 {
                    response.allHeaderFields.forEach { headerField in
                        Logger.general.debug("CrashReportSender: \(String(describing: headerField.key)): \(String(describing: headerField.value))")
                    }
                    let receivedCRCID = response.allHeaderFields[CrashReportSender.httpHeaderCRCID]
                    if receivedCRCID == nil || receivedCRCID as? String == "" {
                        let crashReportError = CrashReportSenderError.crcidMissing
                        self.pixelEvents?.fire(crashReportError)
                    }
                } else {
                    assertionFailure("CrashReportSender: Failed to send the crash report: \(response.statusCode)")
                }

                if let data {
                    completion(.success(data), response)
                } else if let error {
                    let crashReportError = CrashReportSenderError.submissionFailed(response)
                    self.pixelEvents?.fire(crashReportError)
                    completion(.failure(error), response)
                } else {
                    let crashReportError = CrashReportSenderError.submissionFailed(response)
                    self.pixelEvents?.fire(crashReportError)
                    completion(.failure(crashReportError), response)
                }
            } else {
                let crashReportError = CrashReportSenderError.submissionFailed(nil)
                self.pixelEvents?.fire(crashReportError)
                completion(.failure(crashReportError), nil)
            }
        }
        task.resume()
    }

    public func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?) {
        await withCheckedContinuation { continuation in
            send(crashReportData, crcid: crcid) { result, response in
                continuation.resume(returning: (result, response))
            }
        }
    }
}
