//
//  EmailServiceV1.swift
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
import Common
import os.log

public enum EmailErrorV1: Error, Equatable, Codable {
    case cantGenerateURL
    case batchSizeExceeded
    case httpError(statusCode: Int)
    case unknownHTTPError
    case noEmailData
    case invalidResponse
    case cancelled
}

public struct EmailDataRequestV1: Codable {
    public let items: [EmailDataRequestItemV1]

    public init(items: [EmailDataRequestItemV1]) {
        self.items = items
    }
}

public struct EmailDataRequestItemV1: Codable {
    public let email: String
    public let attemptId: String

    public init(email: String, attemptId: String) {
        self.email = email
        self.attemptId = attemptId
    }
}

public struct EmailDataResponseV1: Codable {
    public let items: [EmailDataResponseItemV1]
}

public struct EmailDataResponseItemV1: Codable {
    public let email: String
    public let attemptId: String
    public let status: EmailStatusV1
    public let errorCode: EmailErrorCodeV1?
    public let data: [EmailDatumV1]
    public let emailReceivedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case email, attemptId, status, data
        case errorCode = "error_code"
        case emailReceivedAt = "email_received_at"
    }

    public var confirmationLink: String? {
        data.first(where: { $0.name == "link" })?.value
    }

    public var linkObtainedOnBEDate: Date? {
        guard let emailReceivedAt else { return nil }
        return Date(timeIntervalSince1970: emailReceivedAt)
    }
}

public enum EmailStatusV1: String, Codable {
    case ready
    case pending
    case unknown
    case error
}

public enum EmailErrorCodeV1: String, Codable {
    case serverError = "server_error"
    case extractionError = "extraction_error"
    case requestError = "request_error"
}

public struct EmailDatumV1: Codable {
    public let name: String
    public let value: String
}

public struct DeleteEmailDataRequestV1: Codable {
    public let items: [EmailDataRequestItemV1]

    public init(items: [EmailDataRequestItemV1]) {
        self.items = items
    }
}

public protocol EmailServiceV1Protocol {
    func fetchEmailData(items: [EmailDataRequestItemV1]) async throws -> EmailDataResponseV1
    func deleteEmailData(items: [EmailDataRequestItemV1]) async throws
}

public struct EmailServiceV1: EmailServiceV1Protocol {
    public struct Constants {
        static let endpointSubPath = "/dbp/em/v1"
        static let maxBatchSize = 100
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

    public func fetchEmailData(items: [EmailDataRequestItemV1]) async throws -> EmailDataResponseV1 {
        Logger.service.log("✉️ [EmailServiceV1] Fetching email data for \(items.count, privacy: .public) items")
        guard !items.isEmpty else {
            throw EmailErrorV1.noEmailData
        }

        guard items.count <= Constants.maxBatchSize else {
            assertionFailure("Batch size exceeded: \(items.count) > \(Constants.maxBatchSize)")
            throw EmailErrorV1.batchSizeExceeded
        }

        var urlComponents = URLComponents(url: settings.endpointURL, resolvingAgainstBaseURL: true)
        urlComponents?.path += "\(Constants.endpointSubPath)/email-data"

        guard let url = urlComponents?.url else {
            throw EmailErrorV1.cantGenerateURL
        }

        var request = URLRequest(url: url)
        guard let authHeader = await authenticationManager.getAuthHeader() else {
            servicePixel.fireEmptyAccessToken(callSite: .fetchEmailData)
            throw AuthenticationError.noAuthToken
        }

        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"

        let requestBody = EmailDataRequestV1(items: items)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response)
        Logger.service.log("✉️ [EmailServiceV1] Email data API call successful for \(items.count, privacy: .public) items")

        do {
            return try JSONDecoder().decode(EmailDataResponseV1.self, from: data)
        } catch {
            Logger.service.error("✉️ [EmailServiceV1] Failed to decode email data response: \(error, privacy: .public)")
            throw EmailErrorV1.invalidResponse
        }
    }

    public func deleteEmailData(items: [EmailDataRequestItemV1]) async throws {
        guard !items.isEmpty else {
            return
        }
        Logger.service.log("✉️ [EmailServiceV1] Deleting email data for \(items.count, privacy: .public) items")

        var urlComponents = URLComponents(url: settings.endpointURL, resolvingAgainstBaseURL: true)
        urlComponents?.path += "\(Constants.endpointSubPath)/email-data/delete"

        guard let url = urlComponents?.url else {
            throw EmailErrorV1.cantGenerateURL
        }

        var request = URLRequest(url: url)
        guard let authHeader = await authenticationManager.getAuthHeader() else {
            servicePixel.fireEmptyAccessToken(callSite: .deleteEmailData)
            throw AuthenticationError.noAuthToken
        }

        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"

        let requestBody = DeleteEmailDataRequestV1(items: items)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response)
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                servicePixel.fireGenerateEmailHTTPError(statusCode: httpResponse.statusCode)
                throw EmailErrorV1.httpError(statusCode: httpResponse.statusCode)
            }
        } else {
            throw EmailErrorV1.unknownHTTPError
        }
    }
}
