//
//  PIRDebugEmailClient.swift
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

import Foundation
import Common
import DataBrokerProtectionCore

/// One disposable mailbox: the generated address plus the attempt id it was generated under. The
/// email-data endpoint keys on the pair, so both are needed to read or clear a mailbox.
public struct PIRDebugEmailMailbox: Equatable, Sendable {
    public let email: String
    public let attemptId: UUID

    public init(email: String, attemptId: UUID) {
        self.email = email
        self.attemptId = attemptId
    }
}

/// A freshly generated disposable email address (`/dbp/em/v0/generate`).
public struct PIRDebugGeneratedEmail: Codable, Equatable, Sendable {
    /// The `dataBroker` the address was generated for — the broker JSON's `url`.
    public let dataBroker: String
    public let email: String
    /// The broker's expected address pattern, when the service reports one.
    public let pattern: String?
    public let attemptId: String

    public var mailbox: PIRDebugEmailMailbox? {
        guard let uuid = UUID(uuidString: attemptId) else { return nil }
        return PIRDebugEmailMailbox(email: email, attemptId: uuid)
    }
}

/// What the email-data endpoint (`/dbp/em/v1/email-data`) currently holds for one mailbox.
public struct PIRDebugEmailInboxItem: Codable, Equatable, Sendable {

    public enum Status: String, Codable, Sendable {
        case ready
        case pending
        case unknown
        case error

        init(_ status: EmailStatusV1) {
            switch status {
            case .ready: self = .ready
            case .pending: self = .pending
            case .unknown: self = .unknown
            case .error: self = .error
            }
        }
    }

    public let email: String
    public let attemptId: String
    public let status: Status
    /// The service's error code (`server_error`, `extraction_error`, `request_error`) when `status`
    /// is `error`.
    public let errorCode: String?
    /// The `link` datum — the opt-out confirmation URL, present once `status` is `ready`.
    public let confirmationLink: String?
    /// Every datum the service extracted from the email, keyed by name (`link`, broker-specific
    /// codes, …). A broker's `getEmailData` action names the keys it waits for.
    public let data: [String: String]
    /// When the backend received the email.
    public let receivedAt: Date?

    init(_ item: EmailDataResponseItemV1) {
        self.email = item.email
        self.attemptId = item.attemptId
        self.status = Status(item.status)
        self.errorCode = item.errorCode?.rawValue
        self.confirmationLink = item.confirmationLink
        self.data = Dictionary(item.data.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        self.receivedAt = item.linkObtainedOnBEDate
    }

    enum CodingKeys: String, CodingKey {
        case email, attemptId, status, errorCode, confirmationLink, data, receivedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decode(String.self, forKey: .email)
        self.attemptId = try container.decode(String.self, forKey: .attemptId)
        self.status = try container.decode(Status.self, forKey: .status)
        self.errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        self.confirmationLink = try container.decodeIfPresent(String.self, forKey: .confirmationLink)
        self.data = try container.decodeIfPresent([String: String].self, forKey: .data) ?? [:]
        if let receivedAtString = try container.decodeIfPresent(String.self, forKey: .receivedAt) {
            guard let parsed = PIRDebugISO8601.date(from: receivedAtString) else {
                throw DecodingError.dataCorruptedError(forKey: .receivedAt, in: container,
                                                       debugDescription: "Not an ISO-8601 timestamp: \(receivedAtString)")
            }
            self.receivedAt = parsed
        } else {
            self.receivedAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encode(attemptId, forKey: .attemptId)
        try container.encode(status, forKey: .status)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(confirmationLink, forKey: .confirmationLink)
        try container.encode(data, forKey: .data)
        try container.encode(receivedAt.map(PIRDebugISO8601.string(from:)), forKey: .receivedAt)
    }
}

/// Direct access to the DBP disposable-email services, independent of a scan or opt-out run:
/// generate an address (v0), read what the backend extracted from mail sent to it (v1), and clear
/// it again (v1). These are the same services a ``PIRDebugSession`` drives from a broker's
/// `generateEmail` / `emailConfirmation` / `getEmailData` actions.
///
/// Every call needs an auth token; without one the services throw `AuthenticationError.noAuthToken`.
public final class PIRDebugEmailClient {

    /// Held for the client's lifetime: it owns the ephemeral defaults suite the services read.
    private let ephemeralSettings: PIRDebugEphemeralSettings
    private let emailServiceV0: EmailService
    private let emailServiceV1: EmailServiceV1

    public init(authManager: DataBrokerProtectionAuthenticationManaging,
                servicesEndpoint: PIRServicesEndpoint = .production,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels> = PIRDebugPixels.stderrLoggingPixelHandler(),
                urlSession: URLSession = .shared) throws {
        let ephemeralSettings = try PIRDebugEphemeralSettings(servicesEndpoint: servicesEndpoint)
        self.ephemeralSettings = ephemeralSettings
        let settings = ephemeralSettings.settings
        let servicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: pixelHandler,
                                                                           settings: settings)
        self.emailServiceV0 = EmailService(urlSession: urlSession,
                                          authenticationManager: authManager,
                                          settings: settings,
                                          servicePixel: servicePixels,
                                          baseURL: servicesEndpoint.baseURL)
        self.emailServiceV1 = EmailServiceV1(urlSession: urlSession,
                                            authenticationManager: authManager,
                                            settings: settings,
                                            servicePixel: servicePixels,
                                            baseURL: servicesEndpoint.baseURL)
    }

    /// Generates a disposable address for `dataBrokerURL` (the broker JSON's `url`, which is what
    /// the engine sends). `attemptId` ties the address to a mailbox — keep it to read the mailbox
    /// later.
    public func generateEmail(dataBrokerURL: String, attemptId: UUID = UUID()) async throws -> PIRDebugGeneratedEmail {
        let data = try await emailServiceV0.getEmail(dataBrokerURL: dataBrokerURL, attemptId: attemptId)
        return PIRDebugGeneratedEmail(dataBroker: dataBrokerURL,
                                      email: data.emailAddress,
                                      pattern: data.pattern,
                                      attemptId: attemptId.uuidString)
    }

    /// Reads what the backend has extracted for each mailbox. Items come back in the service's
    /// order, which need not match `mailboxes`.
    public func fetchInbox(_ mailboxes: [PIRDebugEmailMailbox]) async throws -> [PIRDebugEmailInboxItem] {
        let response = try await emailServiceV1.fetchEmailData(items: try requestItems(for: mailboxes))
        return response.items.map(PIRDebugEmailInboxItem.init)
    }

    /// Clears the backend's stored email data for each mailbox — what the app does once it has
    /// consumed a confirmation link.
    public func deleteInbox(_ mailboxes: [PIRDebugEmailMailbox]) async throws {
        try await emailServiceV1.deleteEmailData(items: try requestItems(for: mailboxes))
    }

    private func requestItems(for mailboxes: [PIRDebugEmailMailbox]) throws -> [EmailDataRequestItemV1] {
        // Checked here because the service asserts (traps in a debug build) above its batch cap.
        guard mailboxes.count <= EmailServiceV1.Constants.maxBatchSize else {
            throw PIRDebugError.emailBatchTooLarge(count: mailboxes.count,
                                                   maximum: EmailServiceV1.Constants.maxBatchSize)
        }
        return mailboxes.map { EmailDataRequestItemV1(email: $0.email, attemptId: $0.attemptId.uuidString) }
    }
}
