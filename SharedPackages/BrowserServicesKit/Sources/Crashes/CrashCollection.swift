//
//  CrashCollection.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Persistence
import os.log
import Common

public enum CrashCollectionPlatform {
    case iOS, macOS, macOSAppStore

    var userAgent: String {
        switch self {
        case .iOS:
            return "ddg_ios"
        case .macOS:
            return "ddg_mac"
        case .macOSAppStore:
            return "ddg_mac_appstore"
        }
    }
}

@available(iOSApplicationExtension, unavailable)
@available(iOS 13, macOS 12, *)
public final class CrashCollection {

    public init(crashReportSender: CrashReportSending,
                crashCollectionStorage: KeyValueStoring = UserDefaults.standard) {
        self.crashHandler = CrashHandler()
        self.crashSender = crashReportSender
        self.crashCollectionStorage = crashCollectionStorage
        self.crcidManager = CRCIDManager(store: crashCollectionStorage)
    }

    public func start(didFindCrashReports: @escaping (_ pixelParameters: [[String: String]], _ payloads: [Data], _ uploadReports: @escaping () -> Void) -> Void) {
        start(process: { payloads in
            payloads.map { $0.jsonRepresentation() }
        }, didFindCrashReports: didFindCrashReports)
    }

    /// Start `MXDiagnostic` (App Store) crash processing with callbacks called when crash data is found
    /// - Parameters:
    ///   - process: callback preprocessing `MXDiagnosticPayload` Array and returning processed JSON Data Array to be uploaded
    ///   - didFindCrashReports: callback called after payload preprocessing is finished.
    ///     Provides processed JSON data to be presented to the user and Pixel parameters to fire a crash Pixel.
    ///     `uploadReports` callback is used when the user accepts uploading the crash report and starts crash upload to the server.
    public func start(process: @escaping ([MXDiagnosticPayload]) -> [Data],
                      didFindCrashReports: @escaping (_ pixelParameters: [[String: String]],
                                                      _ payloads: [Data],
                                                      _ uploadReports: @escaping () -> Void) -> Void,
                      didFinishHandlingResponse: @escaping (() -> Void) = {}) {
        let first = isFirstCrash
        isFirstCrash = false

        crashHandler.crashDiagnosticsPayloadHandler = { payloads in
            Logger.general.log("😵 loaded \(payloads.count, privacy: .public) diagnostic payloads")
            let pixelParameters = payloads
                .compactMap(\.crashDiagnostics)
                .flatMap { $0 }
                .map { diagnostic in

                    var params = [
                        "appVersion": "\(diagnostic.applicationVersion).\(diagnostic.metaData.applicationBuildVersion)",
                        "code": "\(diagnostic.exceptionCode ?? -1)",
                        "type": "\(diagnostic.exceptionType ?? -1)",
                        "signal": "\(diagnostic.signal ?? -1)",
                    ]
                    if first {
                        params["first"] = "1"
                    }

                    let metadataJSON = try? JSONSerialization.jsonObject(with: diagnostic.metaData.jsonRepresentation()) as? [String: Any]
                    params["bundle"] = metadataJSON?["bundleIdentifier"] as? String
                    return params
                }
            let processedData = process(payloads)
            didFindCrashReports(pixelParameters, processedData) {
                Task {
                    for payload in processedData {
                        // Note: It's important that we submit crashes to our service one by one.  CRCIDs are assigned (or potentially expired
                        // and updated with a new one) in response to a call to crash.js, and making multiple calls in parallel would mean
                        // the server may assign several CRCIDs to a single client in rapid succession.
                        let result =  await self.crashSender.send(payload, crcid: self.crcidManager.crcid)
                        self.crcidManager.handleCrashSenderResult(result: result.result, response: result.response)
                    }
                    didFinishHandlingResponse()
                }
            }
        }

        MXMetricManager.shared.add(crashHandler)
    }

    /// Start `MXDiagnostic` (App Store) crash processing with `didFindCrashReports` callback called when crash data is found and processed.
    /// This method collects additional NSException/C++ exception data (message and stack trace) saved by `CrashLogMessageExtractor` and attaches it to payloads.
    /// - Parameters:
    ///   - didFindCrashReports: callback called after payload preprocessing is finished.
    ///     Provides processed JSON data to be presented to the user and Pixel parameters to fire a crash Pixel.
    ///     `uploadReports` callback is used when the user accepts uploading the crash report and starts crash upload to the server.
    public func startAttachingCrashLogMessages(didFindCrashReports: @escaping (_ pixelParameters: [[String: String]], _ payloads: [Data], _ uploadReports: @escaping () -> Void) -> Void) {
        start(process: { payloads in
            payloads.compactMap { payload in
                var dict = payload.dictionaryRepresentation()

                var pid: pid_t?
                if #available(macOS 14.0, iOS 17.0, *) {
                    pid = payload.crashDiagnostics?.first?.metaData.pid
                }
                // The `MXDiagnostic` payload may not include `crashDiagnostics`, but may instead contain `cpuExceptionDiagnostics`,
                // `diskWriteExceptionDiagnostics`, or `hangDiagnostics`.
                // For now, we are ignoring these.
                if var crashDiagnostics = dict["crashDiagnostics"] as? [[AnyHashable: Any]], !crashDiagnostics.isEmpty {
                    var crashDiagnosticsDict = crashDiagnostics[0]
                    var diagnosticMetaDataDict = crashDiagnosticsDict["diagnosticMetaData"] as? [AnyHashable: Any] ?? [:]
                    var objCexceptionReason = diagnosticMetaDataDict["objectiveCexceptionReason"] as? [AnyHashable: Any] ?? [:]

                    var exceptionMessage = (objCexceptionReason["composedMessage"] as? String)?.sanitized()
                    var stackTrace: [String]?

                    // Look up for NSException/C++ exception diagnostics data (name, reason, `userInfo` dictionary, stack trace)
                    // by searching for the related crash diagnostics file using the provided crash event timestamp and/or the crashed process PID.
                    // The stored data was sanitized to remove any potential filename or email occurrences.
                    if let diagnostic = try? CrashLogMessageExtractor().crashDiagnostic(for: payload.timeStampBegin, pid: pid)?.diagnosticData(), !diagnostic.isEmpty {
                        // append the loaded crash diagnostics message if the `MXDiagnostic` already contains one
                        if let existingMessage = exceptionMessage, !existingMessage.isEmpty {
                            exceptionMessage = existingMessage + "\n\n---\n\n" + diagnostic.message
                        } else {
                            // set the loaded diagnostics message in place of the original `MXDiagnostic` exceptionMessage if none exists
                            exceptionMessage = diagnostic.message
                        }
                        stackTrace = diagnostic.stackTrace
                    }

                    /** Rebuild the original `MXDiagnostic` JSON with appended crash diagnostics:
                    ```
                     {
                       "crashDiagnostics": [
                         {
                           "callStackTree": { ... },
                           "diagnosticMetaData": {
                             "appVersion": "1.95.0",
                             "objectiveCexceptionReason": {
                               "composedMessage": "NSTableViewException: Row index 9223372036854775807 out of row range (numberOfRows: 0)",
                               "stackTrace": [
                                 "0   CoreFoundation                      0x00000001930072ec __exceptionPreprocess + 176",
                                 "1   libobjc.A.dylib                     0x0000000192aee788 objc_exception_throw + 60",
                                 "2   AppKit                              0x00000001968dc20c -[NSTableRowData _availableRowViewWhileUpdatingAtRow:] + 0,",
                                 ...
                               ]
                             },
                             ...
                           }
                         }
                       ],
                       "timeStampBegin": "2024-07-05 14:10:00",
                     }
                    ``` */
                    objCexceptionReason["composedMessage"] = exceptionMessage
                    objCexceptionReason["stackTrace"] = stackTrace
                    diagnosticMetaDataDict["objectiveCexceptionReason"] = objCexceptionReason
                    crashDiagnosticsDict["diagnosticMetaData"] = diagnosticMetaDataDict
                    crashDiagnostics[0] = crashDiagnosticsDict
                    dict["crashDiagnostics"] = crashDiagnostics
                }

                guard JSONSerialization.isValidJSONObject(dict) else {
                    assertionFailure("Invalid JSON object: \(dict)")
                    return nil
                }
                return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            }

        }, didFindCrashReports: didFindCrashReports)
    }

    public func clearCRCID() {
        self.crcidManager.crcid = nil
    }

    var isFirstCrash: Bool {
        get {
            crashCollectionStorage.object(forKey: Const.firstCrashKey) as? Bool ?? true
        }

        set {
            crashCollectionStorage.set(newValue, forKey: Const.firstCrashKey)
        }
    }

    let crashHandler: CrashHandler
    let crashSender: CrashReportSending
    let crashCollectionStorage: KeyValueStoring
    let crcidManager: CRCIDManager

    enum Const {
        static let firstCrashKey = "CrashCollection.first"
    }
}
