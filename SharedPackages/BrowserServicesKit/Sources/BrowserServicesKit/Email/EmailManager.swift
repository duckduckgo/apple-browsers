//
//  EmailManager.swift
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
import Common

public enum EmailKeychainAccessType: String {
    case getUsername
    case getToken
    case getAlias
    case getCohort
    case getLastUseData
    case storeTokenUsernameCohort
    case storeAlias
    case storeLastUseDate
    case deleteAuthenticationState
    case deleteAlias
}

public enum EmailKeychainAccessError: Error, Equatable {
    case failedToDecodeKeychainValueAsData
    case failedToDecodeKeychainDataAsString
    case failedToDecodeKeychainDataAsInt
    case keychainSaveFailure(OSStatus)
    case keychainDeleteFailure(OSStatus)
    case keychainLookupFailure(OSStatus)
    case keychainFailedToSaveUsernameAfterSavingToken(OSStatus)

    public var errorDescription: String {
        switch self {
        case .failedToDecodeKeychainValueAsData: return "failedToDecodeKeychainValueAsData"
        case .failedToDecodeKeychainDataAsString: return "failedToDecodeKeychainDataAsString"
        case .failedToDecodeKeychainDataAsInt: return "failedToDecodeKeychainDataAsInt"
        case .keychainSaveFailure: return "keychainSaveFailure"
        case .keychainDeleteFailure: return "keychainDeleteFailure"
        case .keychainLookupFailure: return "keychainLookupFailure"
        case .keychainFailedToSaveUsernameAfterSavingToken: return "keychainFailedtoSaveUsernameAfterSavingToken"
        }
    }
}

public protocol EmailManagerStorage: AnyObject {
    func getUsername() throws -> String?
    func getToken() throws -> String?
    func getAlias() throws -> String?
    func getCohort() throws -> String?
    func getLastUseDate() throws -> String?
    func store(token: String, username: String, cohort: String?) throws
    func store(alias: String) throws
    func store(lastUseDate: String) throws
    func deleteAlias() throws
    func deleteAuthenticationState() throws
    func deleteWaitlistState() throws
}

public enum EmailManagerPermittedAddressType {
    case user
    case generated
    case none
}

public protocol EmailManagerAliasPermissionDelegate: AnyObject {

    func emailManager(_ emailManager: EmailManager,
                      didRequestInContextSignUp: @escaping (_ success: Bool) -> Void)
    func emailManager(_ emailManager: EmailManager,
                      didRequestPermissionToProvideAliasWithCompletion: @escaping (EmailManagerPermittedAddressType, _ autosave: Bool) -> Void)

}

public enum EmailManagerRequestDelegateError: Error {
    case serverError(statusCode: Int)
    case decodingError
}

public protocol EmailManagerRequestDelegate: AnyObject {

    var activeTask: URLSessionTask? { get set }

    func emailManager(_ emailManager: EmailManager,
                      requested url: URL,
                      method: String,
                      headers: [String: String],
                      parameters: [String: String]?,
                      httpBody: Data?,
                      timeoutInterval: TimeInterval) async throws -> Data

    func emailManagerKeychainAccessFailed(_ emailManager: EmailManager,
                                          accessType: EmailKeychainAccessType,
                                          error: EmailKeychainAccessError)

}

public extension Notification.Name {
    static let emailDidSignIn = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidSignIn")
    static let emailDidSignOut = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidSignOut")
    static let emailDidGenerateAlias = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidGenerateAlias")
    static let emailDidIncontextSignup = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidIncontextSignup")
    static let emailDidCloseEmailProtection = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidCloseEmailProtection")
}

public enum AliasRequestError: Error {
    case noDataError
    case signedOut
    case invalidResponse
    case userRefused
    case permissionDelegateNil
    case invalidToken
    case notFound
}

public struct EmailUrls {
    struct Url {
        static let emailAlias = "https://quack.duckduckgo.com/api/email/addresses"
    }

    var emailAliasAPI: URL {
        return URL(string: Url.emailAlias)!
    }

    public init() { }
}

public typealias AliasCompletion = (String?, AliasRequestError?) -> Void
public typealias AliasAutosaveCompletion = (String?, _ autosave: Bool, AliasRequestError?) -> Void
public typealias UsernameAndAliasCompletion = (_ username: String?, _ alias: String?, AliasRequestError?) -> Void
public typealias UserDataCompletion = (_ username: String?, _ alias: String?, _ token: String?, AliasRequestError?) -> Void
public typealias SignUpCompletion = (Bool, AliasRequestError?) -> Void

public enum EmailAliasStatus {
    case active
    case inactive
    case notFound
    case error
    case unknown
}

public class EmailManager {

    public static let emailDomain = "duck.com"
    private static let inContextEmailSignupPromptDismissedPermanentlyAtKey = "Autofill.InContextEmailSignup.dismissed.permanently.at"

    private let storage: EmailManagerStorage
    public weak var aliasPermissionDelegate: EmailManagerAliasPermissionDelegate?
    public weak var requestDelegate: EmailManagerRequestDelegate?

    public enum NotificationParameter {
        public static let cohort = "cohort"
        public static let isForcedSignOut = "isForcedSignOut"
    }

    private lazy var emailUrls = EmailUrls()
    private lazy var aliasAPIURL = emailUrls.emailAliasAPI

    /// This lock is static to prevent data races when using multiple instances of EmailManager to store data.
    private static let lock = NSRecursiveLock()

    private var dateFormatter = ISO8601DateFormatter()

    private var username: String? {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            return try storage.getUsername()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .getUsername, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }

            return nil
        }
    }

    private var token: String? {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            return try storage.getToken()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .getToken, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }

            return nil
        }
    }

    private var alias: String? {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            return try storage.getAlias()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .getAlias, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }

            return nil
        }
    }

    public var cohort: String? {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            return try storage.getCohort()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .getCohort, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }

            return nil
        }
    }

    public var lastUseDate: String {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            return try storage.getLastUseDate() ?? ""
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .getLastUseData, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }

            return ""
        }
    }

    public func updateLastUseDate() {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        let dateString = dateFormatter.string(from: Date())

        do {
            try storage.store(lastUseDate: dateString)
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .storeLastUseDate, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
        }
    }

    public var isSignedIn: Bool {
        return token != nil && username != nil
    }

    public var userEmail: String? {
        guard let username = username else { return nil }
        return username + "@" + EmailManager.emailDomain
    }

    private var inContextEmailSignupPromptDismissedPermanentlyAt: Double? {
        get {
            UserDefaults().object(forKey: Self.inContextEmailSignupPromptDismissedPermanentlyAtKey) as? Double ?? nil
        }

        set {
            UserDefaults().set(newValue, forKey: Self.inContextEmailSignupPromptDismissedPermanentlyAtKey)
        }
    }

    public init(storage: EmailManagerStorage = EmailKeychainManager()) {
        self.storage = storage

        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York") // Use ET time zone
    }

    public func signOut(isForced: Bool = false) throws {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        // Retrieve the cohort before it gets removed from storage, so that it can be passed as a notification parameter.
        let currentCohortValue = try? storage.getCohort()

        do {
            try storage.deleteAuthenticationState()

            var notificationParameters: [String: String] = [:]

            if let currentCohortValue = currentCohortValue {
                notificationParameters[NotificationParameter.cohort] = currentCohortValue
            }
            notificationParameters[NotificationParameter.isForcedSignOut] = isForced ? "true" : nil

            NotificationCenter.default.post(name: .emailDidSignOut, object: self, userInfo: notificationParameters)

        } catch {
            if let error = error as? EmailKeychainAccessError {
                self.requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .deleteAuthenticationState, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            throw error
        }
    }

    public func forceSignOut() {
        try? signOut(isForced: true)
    }

    public func emailAddressFor(_ alias: String) -> String {
        return alias + "@" + Self.emailDomain
    }

    public func aliasFor(_ email: String) -> String {
        return email.lowercased().replacingOccurrences(of: "@" + Self.emailDomain, with: "")
    }

    public func isPrivateEmail(email: String) -> Bool {
        if email != userEmail?.lowercased() && email.lowercased().hasSuffix(Self.emailDomain) {
            return true
        }
        return false
    }

    public func getAliasIfNeededAndConsume(timeoutInterval: TimeInterval = 4.0, completionHandler: @escaping AliasCompletion) {
        getAliasIfNeeded(timeoutInterval: timeoutInterval) { [weak self] newAlias, error in
            completionHandler(newAlias, error)
            if error == nil {
                self?.consumeAliasAndReplace()
            }
        }
    }

    public func getStatusFor(email: String, timeoutInterval: TimeInterval = 4.0) async throws -> EmailAliasStatus {
        do {
            return try await fetchStatusFor(alias: aliasFor(email), timeoutInterval: timeoutInterval)
        } catch {
            throw error
        }
    }

    public func setStatusFor(email: String, active: Bool, timeoutInterval: TimeInterval = 4.0) async throws -> EmailAliasStatus {
        do {
            return try await setStatusFor(alias: aliasFor(email), active: active)
        } catch {
            throw error
        }
    }

    public func resetEmailProtectionInContextPrompt() {
        UserDefaults().setValue(nil, forKey: Self.inContextEmailSignupPromptDismissedPermanentlyAtKey)
    }
}

extension EmailManager: AutofillEmailDelegate {
    public func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool {
         return isSignedIn
    }

    public func autofillUserScriptDidRequestUsernameAndAlias(_: AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion) {
        getAliasIfNeeded { [weak self] alias, error in
            guard let alias = alias, error == nil, let self = self else {
                completionHandler(nil, nil, error)
                return
            }

            completionHandler(self.username, alias, nil)
        }
    }

    public func autofillUserScriptDidRequestUserData(_: AutofillUserScript, completionHandler: @escaping UserDataCompletion) {
        getAliasIfNeeded { [weak self] alias, error in
            guard let alias = alias, error == nil, let self = self else {
                completionHandler(nil, nil, nil, error)
                return
            }

            completionHandler(self.username, alias, self.token, nil)
        }
    }

    public func autofillUserScriptDidRequestSignOut(_: AutofillUserScript) {
        try? self.signOut()
    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                                   shouldConsumeAliasIfProvided: Bool,
                                   completionHandler: @escaping AliasAutosaveCompletion) {

        getAliasIfNeeded { [weak self] newAlias, error in
            guard let newAlias = newAlias, error == nil, let self = self else {
                completionHandler(nil, false, error)
                return
            }

            if requiresUserPermission {
                guard let delegate = self.aliasPermissionDelegate else {
                    assertionFailure("EmailUserScript requires permission to provide Alias")
                    completionHandler(nil, false, .permissionDelegateNil)
                    return
                }

                delegate.emailManager(self, didRequestPermissionToProvideAliasWithCompletion: { [weak self] permissionType, autosave in
                    switch permissionType {
                    case .user:
                        if let username = self?.username {
                            completionHandler(username, autosave, nil)
                        } else {
                            completionHandler(nil, false, .userRefused)
                        }
                    case .generated:
                        // Only generated addresses should be autosaved
                        completionHandler(newAlias, autosave, nil)
                        if shouldConsumeAliasIfProvided {
                            self?.consumeAliasAndReplace()
                        }
                    case .none:
                        completionHandler(nil, false, .userRefused)
                    }
                })
            } else {
                completionHandler(newAlias, true, nil)
                if shouldConsumeAliasIfProvided {
                    self.consumeAliasAndReplace()
                }
            }
        }
    }

    public func autofillUserScriptDidRequestRefreshAlias(_: AutofillUserScript) {
        self.consumeAliasAndReplace()
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?) {
        try? storeToken(token, username: username, cohort: cohort)
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestSetInContextPromptValue value: Double) {
        inContextEmailSignupPromptDismissedPermanentlyAt = value
    }

    public func autofillUserScriptDidRequestInContextPromptValue(_: AutofillUserScript) -> Double? {
        inContextEmailSignupPromptDismissedPermanentlyAt
    }

    public func autofillUserScriptDidRequestInContextSignup(_: AutofillUserScript, completionHandler: @escaping SignUpCompletion) {
        if let delegate = self.aliasPermissionDelegate {
            delegate.emailManager(self, didRequestInContextSignUp: { success in
                completionHandler(success, nil)
            })
        } else {
            NotificationCenter.default.post(name: .emailDidIncontextSignup, object: self)
        }
    }

    public func autofillUserScriptDidCompleteInContextSignup(_: AutofillUserScript) {
        NotificationCenter.default.post(name: .emailDidCloseEmailProtection, object: self)
    }

}

// MARK: - Sync Support

public extension EmailManager {

    func getUsername() throws -> String? {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }
        return try storage.getUsername()
    }

    func getToken() throws -> String? {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }
        return try storage.getToken()
    }
}

// MARK: - Token Management

public extension EmailManager {
    func storeToken(_ token: String, username: String, cohort: String?) throws {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            try storage.store(token: token, username: username, cohort: cohort)

            var notificationParameters: [String: String] = [:]

            if let cohort = cohort {
                notificationParameters[NotificationParameter.cohort] = cohort
            }

            NotificationCenter.default.post(name: .emailDidSignIn, object: self, userInfo: notificationParameters)

        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .storeTokenUsernameCohort, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            throw error
        }

        fetchAndStoreAlias()
    }
}

// MARK: - Alias Management

private extension EmailManager {

    enum Constants {

        enum RequestMethods {
            static let get = "GET"
            static let put = "PUT"
            static let post = "POST"
        }

        enum RequestParameters {
            static let token = "token"
            static let status = "active"
            static let address = "address"
        }
    }

    struct EmailAliasResponse: Decodable {
        let address: String
    }

    struct EmailAliasStatusResponse: Decodable {
        let active: Bool
    }

    typealias HTTPHeaders = [String: String]

    var emailHeaders: HTTPHeaders {
        guard let token = token else {
            return [:]
        }
        return ["Authorization": "Bearer " + token]
    }

    func consumeAliasAndReplace() {
        Self.lock.lock()
        defer {
            Self.lock.unlock()
        }

        do {
            try storage.deleteAlias()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                self.requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .deleteAlias, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
        }

        fetchAndStoreAlias()
    }

    func getAliasIfNeeded(timeoutInterval: TimeInterval = 4.0, completionHandler: @escaping AliasCompletion) {
        if let alias = alias {
            completionHandler(alias, nil)
            return
        }
        fetchAndStoreAlias(timeoutInterval: timeoutInterval) { newAlias, error in
            guard let newAlias = newAlias, error == nil  else {
                completionHandler(nil, error)
                return
            }
            completionHandler(newAlias, nil)
        }
    }

    func fetchAndStoreAlias(timeoutInterval: TimeInterval = 60.0, completionHandler: AliasCompletion? = nil) {
        fetchAlias(timeoutInterval: timeoutInterval) { [weak self] alias, error in
            guard let alias = alias, error == nil else {
                completionHandler?(nil, error)
                return
            }
            // Check we haven't signed out whilst waiting
            // if so we don't want to save sensitive data
            guard let self = self, self.isSignedIn else {
                completionHandler?(nil, .signedOut)
                return
            }

            Self.lock.lock()
            defer {
                Self.lock.unlock()
            }

            do {
                try self.storage.store(alias: alias)
            } catch {
                if let error = error as? EmailKeychainAccessError {
                    self.requestDelegate?.emailManagerKeychainAccessFailed(self, accessType: .storeAlias, error: error)
                } else {
                    assertionFailure("Expected EmailKeychainAccessFailure")
                }
            }

            completionHandler?(alias, nil)
        }
    }

    func fetchAlias(timeoutInterval: TimeInterval = 60.0, completionHandler: AliasCompletion? = nil) {
        guard isSignedIn,
              let requestDelegate else {
            completionHandler?(nil, .signedOut)
            return
        }

        Task.detached { [aliasAPIURL, emailHeaders] in
            let result: Result<String, AliasRequestError>
            do {
                let data = try await requestDelegate.emailManager(self,
                                                                  requested: aliasAPIURL,
                                                                  method: Constants.RequestMethods.post,
                                                                  headers: emailHeaders,
                                                                  parameters: [:],
                                                                  httpBody: nil,
                                                                  timeoutInterval: timeoutInterval)
                do {
                    result = .success(try JSONDecoder().decode(EmailAliasResponse.self, from: data).address)
                } catch {
                    result = .failure(.invalidResponse)
                }
            } catch {
                result = .failure(.noDataError)
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .emailDidGenerateAlias, object: self)
                switch result {
                case .success(let alias):
                    completionHandler?(alias, nil)
                case .failure(let error):
                    completionHandler?(nil, error)
                }
            }
        }
    }

    func fetchStatusFor(alias: String, timeoutInterval: TimeInterval = 5.0) async throws -> EmailAliasStatus {
        guard isSignedIn,
              let requestDelegate else {
            throw AliasRequestError.signedOut
        }

        let data: Data

        do {
            let url = aliasAPIURL
            data = try await requestDelegate.emailManager(self,
                                                          requested: url,
                                                          method: Constants.RequestMethods.get,
                                                          headers: emailHeaders,
                                                          parameters: [Constants.RequestParameters.address: alias],
                                                          httpBody: nil,
                                                          timeoutInterval: timeoutInterval)
            let response: EmailAliasStatusResponse = try JSONDecoder().decode(EmailAliasStatusResponse.self, from: data)
            return response.active ? .active : .inactive
        } catch let error {
            switch error {
            case EmailManagerRequestDelegateError.serverError(let code):
                switch code {
                case 404:
                    return .notFound
                default:
                    return .error
                }
            default:
                return .error
            }
        }
    }

    func setStatusFor(alias: String, active: Bool, timeoutInterval: TimeInterval = 5.0) async throws -> EmailAliasStatus {
        guard isSignedIn,
              let requestDelegate else {
            throw AliasRequestError.signedOut
        }

        do {
            let url = aliasAPIURL
            let data = try await requestDelegate.emailManager(self,
                                                              requested: url,
                                                              method: Constants.RequestMethods.put,
                                                              headers: emailHeaders,
                                                              parameters: [
                                                                Constants.RequestParameters.address: alias,
                                                                Constants.RequestParameters.status: "\(active)"
                                                              ],
                                                              httpBody: nil,
                                                              timeoutInterval: timeoutInterval)
            let response: EmailAliasStatusResponse = try JSONDecoder().decode(EmailAliasStatusResponse.self, from: data)
            return response.active ? .active : .inactive
        } catch let error {
            switch error {
            case EmailManagerRequestDelegateError.serverError(let code):
                switch code {
                case 404:
                    return .notFound
                default:
                    return .error
                }
            default:
                return .error
            }
        }
    }

}
