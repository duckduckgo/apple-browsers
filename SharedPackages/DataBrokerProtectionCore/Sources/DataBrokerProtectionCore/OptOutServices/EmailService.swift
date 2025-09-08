//
//  EmailService.swift
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
import Common
import os.log

public enum EmailError: Error, Equatable, Codable {
    case cantGenerateURL
    case cantFindEmail
    case invalidEmailLink
    case linkExtractionTimedOut
    case cantDecodeEmailLink
    case unknownStatusReceived(email: String)
    case cancelled
    case httpError(statusCode: Int)
    case unknownHTTPError
    case extractionError
    case requestError
    case serverError
    case retriesExceeded
}

public struct EmailData: Decodable {
    let pattern: String?
    let emailAddress: String

    public init(pattern: String?, emailAddress: String) {
        self.pattern = pattern
        self.emailAddress = emailAddress
    }
}

public protocol EmailServiceProtocol {
    func getEmail(dataBrokerURL: String, attemptId: UUID) async throws -> EmailData
    func getConfirmationLink(from email: String,
                             numberOfRetries: Int,
                             pollingInterval: TimeInterval,
                             attemptId: UUID,
                             shouldRunNextStep: @escaping () -> Bool) async throws -> URL
}

public struct EmailService: EmailServiceProtocol {
    private struct Constants {
        static let endpointSubPath = "/dbp/em/v0"
    }

    public let urlSession: URLSession
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let settings: DataBrokerProtectionSettings
    private let servicePixel: DataBrokerProtectionBackendServicePixels

    public init(urlSession: URLSession = URLSession.shared,
                authenticationManager: DataBrokerProtectionAuthenticationManaging,
                settings: DataBrokerProtectionSettings,
                servicePixel: DataBrokerProtectionBackendServicePixels) {
        self.urlSession = urlSession
        self.authenticationManager = authenticationManager
        self.settings = settings
        self.servicePixel = servicePixel
    }

    public func getEmail(dataBrokerURL: String, attemptId: UUID) async throws -> EmailData {
        Logger.service.log("✉️ [EmailService] Getting email for dataBroker: \(dataBrokerURL, privacy: .public), attemptId: \(attemptId.uuidString, privacy: .public)")

        var urlComponents = URLComponents(url: settings.endpointURL, resolvingAgainstBaseURL: true)
        urlComponents?.path += "\(Constants.endpointSubPath)/generate"
        urlComponents?.queryItems = [
            URLQueryItem(name: "dataBroker", value: dataBrokerURL),
            URLQueryItem(name: "attemptId", value: attemptId.uuidString)
        ]

        guard let url = urlComponents?.url else {
            throw EmailError.cantGenerateURL
        }

        var request = URLRequest(url: url)
        guard let authHeader = await authenticationManager.getAuthHeader() else {
            servicePixel.fireEmptyAccessToken(callSite: .getEmail)
            throw AuthenticationError.noAuthToken
        }

        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response)

        do {
            let emailData = try JSONDecoder().decode(EmailData.self, from: data)
            Logger.service.log("✉️ [EmailService] Successfully generated email: \(emailData.emailAddress, privacy: .public)")
            return emailData
        } catch {
            Logger.service.error("✉️ [EmailService] Failed to decode email data: \(error, privacy: .public)")
            throw EmailError.cantFindEmail
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                servicePixel.fireGenerateEmailHTTPError(statusCode: httpResponse.statusCode)
                throw EmailError.httpError(statusCode: httpResponse.statusCode)
            }
        } else {
            servicePixel.fireGenerateEmailHTTPError(statusCode: 0)
            throw EmailError.unknownHTTPError
        }
    }

    public func getConfirmationLink(from email: String,
                                    numberOfRetries: Int,
                                    pollingInterval: TimeInterval,
                                    attemptId: UUID,
                                    shouldRunNextStep: @escaping () -> Bool) async throws -> URL {
        Logger.service.log("✉️ [EmailService] Getting confirmation link from email: \(email, privacy: .public), attemptId: \(attemptId.uuidString, privacy: .public)")
        let pollingTimeInNanoSecondsSeconds = UInt64(pollingInterval * 1000) * NSEC_PER_MSEC

        guard let emailResult = try? await extractEmailLink(email: email, attemptId: attemptId) else {
            Logger.service.error("✉️ [EmailService] Failed to extract email link for: \(email, privacy: .public)")
            throw EmailError.cantFindEmail
        }

        if !shouldRunNextStep() {
            throw EmailError.cancelled
        }

        switch emailResult.status {
        case .ready:
            if let link = emailResult.link, let url = URL(string: link) {
                Logger.service.log("✉️ [EmailService] Email received with confirmation link")
                return url
            } else {
                Logger.service.error("✉️ [EmailService] Invalid email link")
                throw EmailError.invalidEmailLink
            }
        case .pending:
            if numberOfRetries == 0 {
                Logger.service.error("✉️ [EmailService] Link extraction timed out after retries for: \(email, privacy: .public)")
                throw EmailError.linkExtractionTimedOut
            }
            Logger.service.log("✉️ [EmailService] No email yet. Waiting for a new request... (\(numberOfRetries, privacy: .public) retries remaining)")
            try await Task.sleep(nanoseconds: pollingTimeInNanoSecondsSeconds)
            return try await getConfirmationLink(from: email,
                                                 numberOfRetries: numberOfRetries - 1,
                                                 pollingInterval: pollingInterval,
                                                 attemptId: attemptId,
                                                 shouldRunNextStep: shouldRunNextStep)
        case .unknown:
            Logger.service.error("✉️ [EmailService] Unknown status received for email: \(email, privacy: .public)")
            throw EmailError.unknownStatusReceived(email: email)
        }
    }

    private func extractEmailLink(email: String, attemptId: UUID) async throws -> EmailResponse {
        Logger.service.log("✉️ [EmailService] Extracting email link for: \(email, privacy: .public), attemptId: \(attemptId.uuidString, privacy: .public)")
        var urlComponents = URLComponents(url: settings.endpointURL, resolvingAgainstBaseURL: true)
        urlComponents?.path += "\(Constants.endpointSubPath)/links"
        urlComponents?.queryItems = [
            URLQueryItem(name: "e", value: email),
            URLQueryItem(name: "attemptId", value: attemptId.uuidString)
        ]

        guard let url = urlComponents?.url else {
            throw EmailError.cantGenerateURL
        }

        var request = URLRequest(url: url)

        guard let authHeader = await authenticationManager.getAuthHeader() else {
            servicePixel.fireEmptyAccessToken(callSite: .extractEmailLink)
            throw AuthenticationError.noAuthToken
        }

        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, _) = try await urlSession.data(for: request)

        return try JSONDecoder().decode(EmailResponse.self, from: data)
    }
}

internal struct EmailResponse: Codable {
    enum Status: String, Codable {
        case ready
        case unknown
        case pending
    }

    let status: Status
    let link: String?
}
