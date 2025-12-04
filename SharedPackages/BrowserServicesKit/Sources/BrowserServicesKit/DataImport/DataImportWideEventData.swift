//
//  DataImportWideEventData.swift
//  BrowserServicesKit
//
//  Created by Hanyu Tang on 04/12/2025.
//

import Foundation
import PixelKit

public class DataImportWideEventData: WideEventData {

    #if DEBUG
    public static let pixelName = "data_import_debug"
    #else
    public static let pixelName = "data_import"
    #endif

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

    private static let featureName = "data-import"
}

// MARK: - Public

extension DataImportWideEventData {
    
    public enum StatusReason: String, Codable, CaseIterable {
        case partialData = "partial_data"
        case timeout
    }

    public enum ImportType: String, Codable, CaseIterable {
        case bookmark
        case password
        case creditCard = "credit_card"

        public var statusPath: WritableKeyPath<DataImportWideEventData, WideEventStatus?> {
            switch self {
            case .bookmark: return \.bookmarkImportStatus
            case .password: return \.passwordImportStatus
            case .creditCard: return \.creditCardImportStatus
            }
        }
        
        public var importerDurationPath: WritableKeyPath<DataImportWideEventData, WideEvent.MeasuredInterval?> {
            switch self {
            case .bookmark: return \.bookmarkImporterDuration
            case .password: return \.passwordImporterDuration
            case .creditCard: return \.creditCardImporterDuration
            }
        }


        public var errorPath: WritableKeyPath<DataImportWideEventData, WideEventErrorData?> {
            switch self {
            case .bookmark: return \.bookmarkImportError
            case .password: return \.passwordImportError
            case .creditCard: return \.creditCardImportError
            }
        }
    }

    public func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        params[WideEventParameter.Feature.name] = Self.featureName
        params[WideEventParameter.DataImportFeature.source] = source.id

        // Overall latency
        if let overallDuration = overallDuration?.durationMilliseconds {
            params[WideEventParameter.DataImportFeature.latency] = String(Int(overallDuration))
        }

        for type in ImportType.allCases {
            addTypeStatusAndReason(self[keyPath: type.statusPath], type: type, to: &params)
            addTypeImporterLatency(self[keyPath: type.importerDurationPath], type: type, to: &params)
            addTypeError(self[keyPath: type.errorPath], type: type, to: &params)
        }

        return params
    }
}

// MARK: - Private

private extension DataImportWideEventData {
    
    func addTypeStatusAndReason(_ status: WideEventStatus?, type: ImportType, to params: inout [String: String]) {
        guard let status else { return }
        params[WideEventParameter.DataImportFeature.status(for: type)] = status.description

        switch status {
        case .success(let reason?), .unknown(let reason):
            params[WideEventParameter.DataImportFeature.statusReason(for: type)]  = reason
        case .failure, .cancelled, .success(nil):
            break
        }
    }

    func addTypeImporterLatency(_ interval: WideEvent.MeasuredInterval?, type: ImportType, to params: inout [String: String]) {
        guard let duration = interval?.durationMilliseconds else { return }
        params[WideEventParameter.DataImportFeature.latency(for: type)] = String(Int(duration))
    }

    func addTypeError(_ error: WideEventErrorData?, type: ImportType, to params: inout [String: String]) {
        guard let error else { return }
        let errorParams = error.pixelParameters()
        for (key, value) in errorParams {
            let typeKey = transformErrorKey(key, for: type)
            params[typeKey] = value
        }
    }

    func transformErrorKey(_ key: String, for type: ImportType) -> String {
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

        static func latency(for type: DataImportWideEventData.ImportType) -> String {
            "feature.data.ext.\(type.rawValue)_importer_latency_ms"
        }
        
        static func status(for type: DataImportWideEventData.ImportType) -> String {
            "feature.data.ext.\(type.rawValue)_import_status"
        }
        
        static func statusReason(for type: DataImportWideEventData.ImportType) -> String {
            "feature.data.ext.\(type.rawValue)_import_status_reason"
        }

        static func errorDomain(for type: DataImportWideEventData.ImportType) -> String {
            "feature.data.ext.\(type.rawValue)_import_error.domain"
        }

        static func errorCode(for type: DataImportWideEventData.ImportType) -> String {
            "feature.data.ext.\(type.rawValue)_import_error.code"
        }

        static func errorDescription(for type: DataImportWideEventData.ImportType) -> String {
            "feature.data.ext.\(type.rawValue)_import_error.description"
        }

        static func errorUnderlyingDomain(for type: DataImportWideEventData.ImportType, suffix: String) -> String {
            return "feature.data.ext.\(type.rawValue)_import_error.underlying_domain\(suffix)"
        }

        static func errorUnderlyingCode(for type: DataImportWideEventData.ImportType, suffix: String) -> String {
            return "feature.data.ext.\(type.rawValue)_import_error.underlying_code\(suffix)"
        }
    }
}
