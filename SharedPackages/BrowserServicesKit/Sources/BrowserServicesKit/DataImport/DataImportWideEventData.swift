//
//  DataImportWideEventData.swift
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
import PixelKit

public class DataImportWideEventData: WideEventData {

    typealias DataType = DataImport.DataType

    #if DEBUG
    public static let pixelName = "data_import_debug"
    #else
    public static let pixelName = "data_import"
    #endif

    public static let importTimeout: TimeInterval = .minutes(15)

    // Protocol Properties
    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    // DataImport specific
    public var source: DataImport.Source

    // Durations
    public var overallDuration: WideEvent.MeasuredInterval?
    public var bookmarkImporterDuration: WideEvent.MeasuredInterval?
    public var passwordImporterDuration: WideEvent.MeasuredInterval?
    public var creditCardImporterDuration: WideEvent.MeasuredInterval?

    // Per-type status
    public var bookmarkImportStatus: WideEventStatus?
    public var passwordImportStatus: WideEventStatus?
    public var creditCardImportStatus: WideEventStatus?

    // Per-type errors
    public var bookmarkImportError: WideEventErrorData?
    public var passwordImportError: WideEventErrorData?
    public var creditCardImportError: WideEventErrorData?

    public init(source: DataImport.Source,
                overallDuration: WideEvent.MeasuredInterval? = nil,
                bookmarkImporterDuration: WideEvent.MeasuredInterval? = nil,
                passwordImporterDuration: WideEvent.MeasuredInterval? = nil,
                creditCardImporterDuration: WideEvent.MeasuredInterval? = nil,
                bookmarkImportStatus: WideEventStatus? = nil,
                passwordImportStatus: WideEventStatus? = nil,
                creditCardImportStatus: WideEventStatus? = nil,
                bookmarkImportError: WideEventErrorData? = nil,
                passwordImportError: WideEventErrorData? = nil,
                creditCardImportError: WideEventErrorData? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.source = source

        self.overallDuration = overallDuration
        self.bookmarkImporterDuration = bookmarkImporterDuration
        self.passwordImporterDuration = passwordImporterDuration
        self.creditCardImporterDuration = creditCardImporterDuration

        // Per-type status
        self.bookmarkImportStatus = bookmarkImportStatus
        self.passwordImportStatus = passwordImportStatus
        self.creditCardImportStatus = creditCardImportStatus

        // Per-type errors
        self.bookmarkImportError = bookmarkImportError
        self.passwordImportError = passwordImportError
        self.creditCardImportError = creditCardImportError

        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            guard let start = overallDuration?.start else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            guard overallDuration?.end == nil else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            if Date() >= start.addingTimeInterval(Self.importTimeout) {
                return .complete(.unknown(reason: StatusReason.timeout.rawValue))
            }

            return .keepPending
        }
    }

    private static let featureName = "data-import"
}

// MARK: - Public

extension DataImportWideEventData {

    public enum StatusReason: String, Codable, CaseIterable {
        case partialData = "partial_data"
        case documentPickerCancelled = "document_picker_cancelled"
        case timeout
    }

    public func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        params[WideEventParameter.Feature.name] = Self.featureName
        params[WideEventParameter.DataImportFeature.source] = source.id

        if let overallDuration = overallDuration?.durationMilliseconds {
            params[WideEventParameter.DataImportFeature.latency] = String(Int(overallDuration))
        }

        for type in DataImport.DataType.allCases {
            addTypeStatusAndReason(self[keyPath: type.statusPath], type: type, to: &params)
            addTypeImporterLatency(self[keyPath: type.importerDurationPath], type: type, to: &params)
            addTypeError(self[keyPath: type.errorPath], type: type, to: &params)
        }

        return params
    }
}

// MARK: - Private

private extension DataImportWideEventData {

    func addTypeStatusAndReason(_ status: WideEventStatus?, type: DataType, to params: inout [String: String]) {
        guard let status else { return }
        params[WideEventParameter.DataImportFeature.status(for: type)] = status.description

        switch status {
        case .success(let reason?), .unknown(let reason):
            params[WideEventParameter.DataImportFeature.statusReason(for: type)]  = reason
        case .failure, .cancelled, .success(nil):
            break
        }
    }

    func addTypeImporterLatency(_ interval: WideEvent.MeasuredInterval?, type: DataType, to params: inout [String: String]) {
        guard let duration = interval?.durationMilliseconds else { return }
        params[WideEventParameter.DataImportFeature.latency(for: type)] = String(Int(duration))
    }

    func addTypeError(_ error: WideEventErrorData?, type: DataType, to params: inout [String: String]) {
        guard let error else { return }
        let errorParams = error.pixelParameters()
        for (key, value) in errorParams {
            let typeKey = transformErrorKey(key, for: type)
            params[typeKey] = value
        }
    }

    func transformErrorKey(_ key: String, for type: DataType) -> String {
        switch key {
        case WideEventParameter.Feature.errorDomain:
            return WideEventParameter.DataImportFeature.errorDomain(for: type)

        case WideEventParameter.Feature.errorCode:
            return WideEventParameter.DataImportFeature.errorCode(for: type)

        case WideEventParameter.Feature.errorDescription:
            return WideEventParameter.DataImportFeature.errorDescription(for: type)

        case let key where key.hasPrefix(WideEventParameter.Feature.underlyingErrorDomain):
            let suffix = key.dropFirst(WideEventParameter.Feature.underlyingErrorDomain.count)
            return WideEventParameter.DataImportFeature.errorUnderlyingDomain(for: type, suffix: String(suffix))

        case let key where key.hasPrefix(WideEventParameter.Feature.underlyingErrorCode):
            let suffix = key.dropFirst(WideEventParameter.Feature.underlyingErrorCode.count)
            return WideEventParameter.DataImportFeature.errorUnderlyingCode(for: type, suffix: String(suffix))

        default:
            assertionFailure("Unexpected error parameter key: \(key)")
            return key
        }
    }
}

// MARK: - Wide Event Parameters
extension WideEventParameter {

    public enum DataImportFeature {
        static let source = "feature.data.ext.source"
        static let latency = "feature.data.ext.latency_ms"

        static func latency(for type: DataImportWideEventData.DataType) -> String {
            "feature.data.ext.\(type.description)_importer_latency_ms"
        }

        static func status(for type: DataImportWideEventData.DataType) -> String {
            "feature.data.ext.\(type.description)_status"
        }

        static func statusReason(for type: DataImportWideEventData.DataType) -> String {
            "feature.data.ext.\(type.description)_status_reason"
        }

        static func errorDomain(for type: DataImportWideEventData.DataType) -> String {
            "feature.data.ext.\(type.description)_error.domain"
        }

        static func errorCode(for type: DataImportWideEventData.DataType) -> String {
            "feature.data.ext.\(type.description)_error.code"
        }

        static func errorDescription(for type: DataImportWideEventData.DataType) -> String {
            "feature.data.ext.\(type.description)_error.description"
        }

        static func errorUnderlyingDomain(for type: DataImportWideEventData.DataType, suffix: String) -> String {
            return "feature.data.ext.\(type.description)_error.underlying_domain\(suffix)"
        }

        static func errorUnderlyingCode(for type: DataImportWideEventData.DataType, suffix: String) -> String {
            return "feature.data.ext.\(type.description)_error.underlying_code\(suffix)"
        }
    }
}

public extension DataImport.DataType {
    var statusPath: WritableKeyPath<DataImportWideEventData, WideEventStatus?> {
        switch self {
        case .bookmarks: return \.bookmarkImportStatus
        case .passwords: return \.passwordImportStatus
        case .creditCards: return \.creditCardImportStatus
        }
    }

    var importerDurationPath: WritableKeyPath<DataImportWideEventData, WideEvent.MeasuredInterval?> {
        switch self {
        case .bookmarks: return \.bookmarkImporterDuration
        case .passwords: return \.passwordImporterDuration
        case .creditCards: return \.creditCardImporterDuration
        }
    }

    var errorPath: WritableKeyPath<DataImportWideEventData, WideEventErrorData?> {
        switch self {
        case .bookmarks: return \.bookmarkImportError
        case .passwords: return \.passwordImportError
        case .creditCards: return \.creditCardImportError
        }
    }
}
