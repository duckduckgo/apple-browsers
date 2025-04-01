//
//  DataImport.swift
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

import SecureStorage
import PixelKit
import Foundation

public enum DataImport {

    public enum Source: String, RawRepresentable, CaseIterable, Equatable {
        case brave
        case chrome
        case chromium
        case coccoc
        case edge
        case firefox
        case opera
        case operaGX
        case safari
        case safariTechnologyPreview
        case tor
        case vivaldi
        case yandex
        case onePassword8
        case onePassword7
        case bitwarden
        case lastPass
        case csv
        case bookmarksHTML

        static let preferredSources: [Self] = [.chrome, .safari]

    }

    public enum DataType: String, Hashable, CaseIterable, CustomStringConvertible {

        case bookmarks
        case passwords

        public var description: String { rawValue }

        public var importAction: DataImportAction {
            switch self {
            case .bookmarks: .bookmarks
            case .passwords: .passwords
            }
        }

    }

    public struct DataTypeSummary: Equatable {
        public let successful: Int
        public let duplicate: Int
        public let failed: Int

        public var isEmpty: Bool {
            self == .empty
        }

        public static var empty: Self {
            DataTypeSummary(successful: 0, duplicate: 0, failed: 0)
        }

        public init(successful: Int, duplicate: Int, failed: Int) {
            self.successful = successful
            self.duplicate = duplicate
            self.failed = failed
        }
        public init(_ bookmarksImportSummary: BookmarksImportSummary) {
            self.init(successful: bookmarksImportSummary.successful, duplicate: bookmarksImportSummary.duplicates, failed: bookmarksImportSummary.failed)
        }
    }

    public enum ErrorType: String, CustomStringConvertible, CaseIterable {
        case noData
        case decryptionError
        case dataCorrupted
        case keychainError
        case other

        public var description: String { rawValue }
    }

}

public enum DataImportAction: String, RawRepresentable {
    case bookmarks
    case passwords
    case favicons
    case generic

    public init(_ type: DataImport.DataType) {
        switch type {
        case .bookmarks: self = .bookmarks
        case .passwords: self = .passwords
        }
    }
}

public protocol DataImportError: Error, CustomNSError, ErrorWithPixelParameters, LocalizedError {
    associatedtype OperationType: RawRepresentable where OperationType.RawValue == Int

    var action: DataImportAction { get }
    var type: OperationType { get }
    var underlyingError: Error? { get }

    var errorType: DataImport.ErrorType { get }

}
extension DataImportError /* : CustomNSError */ {
    public var errorCode: Int {
        type.rawValue
    }

    public var errorUserInfo: [String: Any] {
        guard let underlyingError else { return [:] }
        return [
            NSUnderlyingErrorKey: underlyingError
        ]
    }
}
extension DataImportError /* : ErrorWithParameters */ {
    public var errorParameters: [String: String] {
        underlyingError?.pixelParameters ?? [:]
    }
}
extension DataImportError /* : LocalizedError */ {

    public var errorDescription: String? {
        let error = (self as NSError)
        return "\(error.domain) \(error.code)" + {
            guard let underlyingError = underlyingError as NSError? else { return "" }
            return " (\(underlyingError.domain) \(underlyingError.code))"
        }()
    }

}

public struct FetchableRecordError<T>: Error, CustomNSError {
    let column: Int

    public static var errorDomain: String { "FetchableRecordError.\(T.self)" }
    public var errorCode: Int { column }

    public init(column: Int) {
        self.column = column
    }

}

public enum DataImportProgressEvent {
    case initial
    case importingPasswords(numberOfPasswords: Int?, fraction: Double)
    case importingBookmarks(numberOfBookmarks: Int?, fraction: Double)
    case done
}

public typealias DataImportSummary = [DataImport.DataType: DataImportResult<DataImport.DataTypeSummary>]
public typealias DataImportTask = TaskWithProgress<DataImportSummary, Never, DataImportProgressEvent>
public typealias DataImportProgressCallback = DataImportTask.ProgressUpdateCallback

/// Represents an object able to import data from an outside source. The outside source may be capable of importing multiple types of data.
/// For instance, a browser data importer may be able to import passwords and bookmarks.
public protocol DataImporter {

    /// Performs a quick check to determine if the data is able to be imported. It does not guarantee that the import will succeed.
    /// For example, a CSV importer will return true if the URL it has been created with is a CSV file, but does not check whether the CSV data matches the expected format.
    var importableTypes: [DataImport.DataType] { get }

    /// validate file access/encryption password requirement before starting import. Returns non-empty dictionary with failures if access validation fails.
    func validateAccess(for types: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]?
    /// Start import process. Returns cancellable TaskWithProgress
    func importData(types: Set<DataImport.DataType>) -> DataImportTask

    func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool

}

extension DataImporter {

    public var importableTypes: [DataImport.DataType] {
        [.bookmarks, .passwords]
    }

    public func validateAccess(for types: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]? {
        nil
    }

    public func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool {
        false
    }

}

public enum DataImportResult<T>: CustomStringConvertible {
    case success(T)
    case failure(any DataImportError)

    public func get() throws -> T {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    public var isSuccess: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }

    public var error: (any DataImportError)? {
        if case .failure(let error) = self {
            error
        } else {
            nil
        }
    }

    /// Returns a new result, mapping any success value using the given transformation.
    /// - Parameter transform: A closure that takes the success value of this instance.
    /// - Returns: A `Result` instance with the result of evaluating `transform`
    ///   as the new success value if this instance represents a success.
    @inlinable public func map<NewT>(_ transform: (T) -> NewT) -> DataImportResult<NewT> {
        switch self {
        case .success(let value):
            return .success(transform(value))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Returns a new result, mapping any success value using the given transformation and unwrapping the produced result.
    ///
    /// - Parameter transform: A closure that takes the success value of the instance.
    /// - Returns: A `Result` instance, either from the closure or the previous
    ///   `.failure`.
    @inlinable public func flatMap<NewT>(_ transform: (T) throws -> DataImportResult<NewT>) rethrows -> DataImportResult<NewT> {
        switch self {
        case .success(let value):
            switch try transform(value) {
            case .success(let transformedValue):
                return .success(transformedValue)
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    public var description: String {
        switch self {
        case .success(let value):
            ".success(\(value))"
        case .failure(let error):
            ".failure(\(error))"
        }
    }

}

extension DataImportResult: Equatable where T: Equatable {
    public static func == (lhs: DataImportResult<T>, rhs: DataImportResult<T>) -> Bool {
        switch lhs {
        case .success(let value):
            if case .success(value) = rhs {
                true
            } else {
                false
            }
        case .failure(let error1):
            if case .failure(let error2) = rhs {
                error1.errorParameters == error2.errorParameters
            } else {
                false
            }
        }
    }

}

public struct LoginImporterError: DataImportError {

    private let error: Error?
    private let _type: OperationType?

    public var action: DataImportAction { .passwords }

    public init(error: Error?, type: OperationType? = nil) {
        self.error = error
        self._type = type
    }

    public struct OperationType: RawRepresentable, Equatable {
        public let rawValue: Int

        static let malformedCSV = OperationType(rawValue: -2)

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public var type: OperationType {
        _type ?? OperationType(rawValue: (error as NSError?)?.code ?? 0)
    }

    public var underlyingError: Error? {
        switch error {
        case let secureStorageError as SecureStorageError:
            switch secureStorageError {
            case .initFailed(let error),
                 .authError(let error),
                 .failedToOpenDatabase(let error),
                 .databaseError(let error):
                return error

            case .keystoreError(let status), .keystoreReadError(let status), .keystoreUpdateError(let status):
                return NSError(domain: "KeyStoreError", code: Int(status))

            case .secError(let status):
                return NSError(domain: "secError", code: Int(status))

            case .authRequired,
                 .invalidPassword,
                 .noL1Key,
                 .noL2Key,
                 .duplicateRecord,
                 .generalCryptoError,
                 .encodingFailed:
                return secureStorageError
            }
        default:
            return error
        }
    }

    public var errorType: DataImport.ErrorType {
        if case .malformedCSV = type {
            return .dataCorrupted
        }
        if let secureStorageError = error as? SecureStorageError {
            switch secureStorageError {
            case .initFailed,
                 .authError,
                 .failedToOpenDatabase,
                 .databaseError:
                return .keychainError

            case .keystoreError, .secError, .keystoreReadError, .keystoreUpdateError:
                return .keychainError

            case .authRequired,
                 .invalidPassword,
                 .noL1Key,
                 .noL2Key,
                 .duplicateRecord,
                 .generalCryptoError,
                 .encodingFailed:
                return .decryptionError
            }
        }
        return .other
    }

}
