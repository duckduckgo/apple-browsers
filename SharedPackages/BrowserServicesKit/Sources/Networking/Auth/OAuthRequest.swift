//
//  OAuthRequest.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import os.log
import Common

/// Auth API v2 Endpoints: https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#auth-api-v2-endpoints
public struct OAuthRequest {

    public let apiRequest: APIRequestV2
    public let httpSuccessCode: HTTPStatusCode
    public let httpErrorCodes: [HTTPStatusCode]
    public var url: URL {
        apiRequest.urlRequest.url!
    }

    public enum BodyErrorCode: String, Decodable {
        case invalidAuthorizationRequest = "invalid_authorization_request"
        case authorizeFailed = "authorize_failed"
        case invalidRequest = "invalid_request"
        case accountCreateFailed = "account_create_failed"
        case invalidEmailAddress = "invalid_email_address"
        case invalidSessionId = "invalid_session_id"
        case suspendedAccount = "suspended_account"
        case emailSendingError = "email_sending_error"
        case invalidLoginCredentials = "invalid_login_credentials"
        case unknownAccount = "unknown_account"
        case invalidTokenRequest = "invalid_token_request"
        case unverifiedAccount = "unverified_account"
        case emailAddressNotChanged = "email_address_not_changed"
        case failedMxCheck = "failed_mx_check"
        case accountEditFailed = "account_edit_failed"
        case invalidLinkSignature = "invalid_link_signature"
        case accountChangeEmailAddressFailed = "account_change_email_address_failed"
        case invalidToken = "invalid_token"
        case expiredToken = "expired_token"

        public var description: String {
            switch self {
            case .invalidAuthorizationRequest:
                return "One or more of the required parameters are missing or any provided parameters have invalid values"
            case .authorizeFailed:
                return "Failed to create the authorization session, either because of a reused code challenge or internal server error"
            case .invalidRequest:
                return "The ddg_auth_session_id is missing or has already been used to log in to a different account"
            case .accountCreateFailed:
                return "Failed to create the account because of an internal server error"
            case .invalidEmailAddress:
                return "Provided email address is missing or of an invalid format"
            case .invalidSessionId:
                return "The session id is missing, invalid or has already been used for logging in"
            case .suspendedAccount:
                return "The account you are logging in to is suspended"
            case .emailSendingError:
                return "Failed to send the OTP to the email address provided"
            case .invalidLoginCredentials:
                return "One or more of the provided parameters is invalid"
            case .unknownAccount:
                return "The login credentials appear valid but do not link to a known account"
            case .invalidTokenRequest:
                return "One or more of the required parameters are missing or any provided parameters have invalid values"
            case .unverifiedAccount:
                return "The token is valid but is for an unverified account"
            case .emailAddressNotChanged:
                return "New email address is the same as the old email address"
            case .failedMxCheck:
                return "DNS check to see if email address domain is valid failed"
            case .accountEditFailed:
                return "Something went wrong and the edit was aborted"
            case .invalidLinkSignature:
                return "The hash is invalid or does not match the provided email address and account"
            case .accountChangeEmailAddressFailed:
                return "Something went wrong and the edit was aborted"
            case .invalidToken:
                return "Provided access token is missing or invalid"
            case .expiredToken:
                return "Provided access token is expired"
            }
        }
    }

    struct BodyError: Decodable {
        let error: BodyErrorCode
    }

    private struct Defaults {
        static let defaultRetryPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .fixed(.seconds(2)))
    }

    static func ddgAuthSessionCookie(domain: String, path: String, authSessionID: String) -> HTTPCookie? {
        return HTTPCookie(properties: [
            .domain: domain,
            .path: path,
            .name: "ddg_auth_session_id",
            .value: authSessionID
        ])
    }

    // MARK: -

    init(apiRequest: APIRequestV2,
         httpSuccessCode: HTTPStatusCode = HTTPStatusCode.ok,
         httpErrorCodes: [HTTPStatusCode] = [HTTPStatusCode.badRequest, HTTPStatusCode.internalServerError]) {
        self.apiRequest = apiRequest
        self.httpSuccessCode = httpSuccessCode
        self.httpErrorCodes = httpErrorCodes
    }

    // MARK: Authorize

    static func authorize(baseURL: URL, codeChallenge: String) -> OAuthRequest? {
        guard codeChallenge.isEmpty == false else { return nil }

        let path = "/api/auth/v2/authorize"
        let queryItems: QueryItems = [
            (key: "response_type", value: "code"),
            (key: "code_challenge", value: codeChallenge),
            (key: "code_challenge_method", value: "S256"),
            (key: "client_id", value: "f4311287-0121-40e6-8bbd-85c36daf1837"),
            (key: "redirect_uri", value: "com.duckduckgo:/authcb"),
            (key: "scope", value: "privacypro")
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems,
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Create account

    static func createAccount(baseURL: URL, authSessionID: String) -> OAuthRequest? {
        guard authSessionID.isEmpty == false else { return nil }

        let path = "/api/auth/v2/account/create"
        guard let domain = baseURL.host,
              let cookie = Self.ddgAuthSessionCookie(domain: domain, path: path, authSessionID: authSessionID)
        else { return nil }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(cookies: [cookie])) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Sent OTP

    /// Unused in the current implementation
    static func requestOTP(baseURL: URL, authSessionID: String, emailAddress: String) -> OAuthRequest? {
        guard authSessionID.isEmpty == false,
              emailAddress.isEmpty == false else { return nil }

        let path = "/api/auth/v2/otp"
        let queryItems: QueryItems = [(key: "email", value: emailAddress)]
        guard let domain = baseURL.host,
              let cookie = Self.ddgAuthSessionCookie(domain: domain, path: path, authSessionID: authSessionID)
        else { return nil }
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(cookies: [cookie])) else {
            return nil
        }
        return OAuthRequest(apiRequest: request)
    }

    // MARK: Login

    static func login(baseURL: URL, authSessionID: String, method: OAuthLoginMethod) -> OAuthRequest? {
        guard authSessionID.isEmpty == false else { return nil }

        let path = "/api/auth/v2/login"
        var body: [String: String]

        guard let domain = baseURL.host,
              let cookie = Self.ddgAuthSessionCookie(domain: domain, path: path, authSessionID: authSessionID)
        else {
            Logger.OAuth.fault("Failed to create cookie")
            assertionFailure("Failed to create cookie")
            return nil
        }

        switch method.self {
        case is OAuthLoginMethodOTP:
            guard let otpMethod = method as? OAuthLoginMethodOTP else {
                return nil
            }
            body = [
                "method": otpMethod.name,
                "email": otpMethod.email,
                "otp": otpMethod.otp
            ]
        case is OAuthLoginMethodSignature:
            guard let signatureMethod = method as? OAuthLoginMethodSignature else {
                return nil
            }
            body = [
                "method": signatureMethod.name,
                "signature": signatureMethod.signature,
                "source": signatureMethod.source
            ]
        default:
            Logger.OAuth.fault("Unknown login method: \(String(describing: method))")
            assertionFailure("Unknown login method: \(String(describing: method))")
            return nil
        }

        guard let jsonBody = CodableHelper.encode(body) else {
            assertionFailure("Failed to encode body: \(body)")
            return nil
        }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(cookies: [cookie],
                                                                         contentType: .json),
                                         body: jsonBody,
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Access Token
    // Note: The API has a single endpoint for both getting a new token and refreshing an old one, but here I'll split the endpoint in 2 different calls for clarity
    // https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#access-token

    static func getAccessToken(baseURL: URL, clientID: String, codeVerifier: String, code: String, redirectURI: String) -> OAuthRequest? {
        guard clientID.isEmpty == false,
              codeVerifier.isEmpty == false,
              code.isEmpty == false,
              redirectURI.isEmpty == false else { return nil }

        let path = "/api/auth/v2/token"
        let queryItems: QueryItems = [
            (key: "grant_type", value: "authorization_code"),
            (key: "client_id", value: clientID),
            (key: "code_verifier", value: codeVerifier),
            (key: "code", value: code),
            (key: "redirect_uri", value: redirectURI)
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems,
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }

        return OAuthRequest(apiRequest: request)
    }

    static func refreshAccessToken(baseURL: URL, clientID: String, refreshToken: String) -> OAuthRequest? {
        guard clientID.isEmpty == false,
              refreshToken.isEmpty == false else { return nil }

        let path = "/api/auth/v2/token"
        let queryItems: QueryItems = [
            (key: "grant_type", value: "refresh_token"),
            (key: "client_id", value: clientID),
            (key: "refresh_token", value: refreshToken)
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems,
                                         timeoutInterval: 20.0) else {
            return nil
        }
        return OAuthRequest(apiRequest: request)
    }

    // MARK: Edit Account

    /// Unused in the current implementation
    static func editAccount(baseURL: URL, accessToken: String, email: String?) -> OAuthRequest? {
        guard accessToken.isEmpty == false else { return nil }

        let path = "/api/auth/v2/account/edit"
        var queryItems: QueryItems = []
        if let email {
            queryItems.append((key: "email", value: email))
        }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(
                                            authToken: accessToken)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.unauthorized, .internalServerError])
    }

    /// Unused in the current implementation
    static func confirmEditAccount(baseURL: URL, accessToken: String, email: String, hash: String, otp: String) -> OAuthRequest? {
        guard accessToken.isEmpty == false,
              email.isEmpty == false,
              hash.isEmpty == false,
              otp.isEmpty == false else { return nil }

        let path = "/account/edit/confirm"
        let queryItems: QueryItems = [
            (key: "email", value: email),
            (key: "hash", value: hash),
            (key: "otp", value: otp)
        ]

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(authToken: accessToken)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.unauthorized, .internalServerError])
    }

    // MARK: Logout

    static func logout(baseURL: URL, accessToken: String) -> OAuthRequest? {
        guard accessToken.isEmpty == false else { return nil }

        let path = "/api/auth/v2/logout"
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(authToken: accessToken)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.unauthorized, .internalServerError])
    }

    // MARK: Exchange token

    static func exchangeToken(baseURL: URL, accessTokenV1: String, authSessionID: String) -> OAuthRequest? {
        guard !accessTokenV1.isEmpty, !authSessionID.isEmpty else { return nil }

        let path = "/api/auth/v2/exchange"
        guard let domain = baseURL.host,
              let cookie = Self.ddgAuthSessionCookie(domain: domain, path: path, authSessionID: authSessionID)
        else { return nil }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(cookies: [cookie], authToken: accessTokenV1),
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }
        return OAuthRequest(apiRequest: request,
                            httpSuccessCode: .found,
                            httpErrorCodes: [.badRequest, .internalServerError])
    }

    // MARK: JWKs

    /// This endpoint is where the Auth service will publish public keys for consuming services and clients to use to independently verify access tokens. Tokens should be downloaded and cached for an hour upon first use. When rotating private keys for signing JWTs, the Auth service will publish new public keys 24 hours in advance of starting to sign new JWTs with them. This should provide consuming services with plenty of time to invalidate their public key cache and have the new key available before they can expect to start receiving JWTs signed with the old key. The old key will remain published until the next key rotation, so there should generally be two public keys available through this endpoint. The response format is a standard JWKS response, as documented in RFC 7517.
    static func jwks(baseURL: URL) -> OAuthRequest? {
        let path = "/api/auth/v2/.well-known/jwks.json"

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }
        return OAuthRequest(apiRequest: request,
                            httpSuccessCode: .ok,
                            httpErrorCodes: [.internalServerError])
    }
}
