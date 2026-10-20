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
import DDGError
import os.log
import Common
import FoundationExtensions

/// A request to the Auth API v2, with the status codes that decide how `OAuthService` reads its response.
/// Auth API v2 Endpoints: https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#auth-api-v2-endpoints
public struct OAuthRequest {

    /// The HTTP request to send.
    public let apiRequest: APIRequestV2
    /// The status of a successful response.
    public let httpSuccessCode: HTTPStatusCode
    /// The failure statuses whose response body is decoded as a `BodyError` and thrown as `OAuthServiceError.authAPIError`,
    /// or as `OAuthServiceError.missingResponseValue(.bodyError)` when it can't be decoded.
    /// Any other status than `httpSuccessCode` is thrown as `OAuthServiceError.invalidResponseCode`.
    public let httpErrorCodes: [HTTPStatusCode]
    /// The URL of `apiRequest`.
    public var url: URL {
        apiRequest.urlRequest.url!
    }

    /// The `error` value of an Auth API error response body.
    public enum BodyErrorCode: String, Decodable, Equatable {
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

        /// A human-readable explanation of the error code, as documented by the Auth API.
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

    /// API `TOKEN_STATUS` values describing refresh token validity.
    /// https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#access-token scroll down to `TOKEN_STATUS` enum values
    /// Task: https://app.asana.com/1/137249556945/project/1205842942115003/task/1212840065651597?focus=true
    public enum TokenStatus: Int, Equatable, Decodable, DDGError, CustomStringConvertible {
        /// Token is invalid in a non-stateful way (e.g., bad signature, malformed, etc) or the request failed for a reason unrelated to the token itself (e.g., suspended account).
        case invalid = 0
        /// Token is valid but has expired. Specifically the exp claim in the JWT indicates a time in the past. This means the tokens is more than 30 days old.
        case expired = 1
        /// Token has prematurely expired because it was previously used more than an hour ago. The refresh token reuse window has expired and the token can no longer be reused.
        case reused = 2
        /// Token was logged out and can no longer be used. Tokens are immediately marked invalid on logout.
        case loggedOut = 3
        /// Token has been invalidated due to detected fraud during the authentication flow. This can happen if an authentication session is reused during login (e.g., same login credentials are submitted multiple times for the same session id) or if an authorization code is reused in the Access Token Request for the authorization_code grant_type.
        case fraudDetected = 4

        public var description: String {
            switch self {
            case .invalid:
                return "Token is invalid or request failed"
            case .expired:
                return "Token is expired"
            case .reused:
                return "Token reuse window expired"
            case .loggedOut:
                return "Token was logged out"
            case .fraudDetected:
                return "Token invalidated due to suspected fraud"
            }
        }

        public static var errorDomain: String { "com.duckduckgo.networking.TokenStatus" }

        public var errorCode: Int { rawValue }

        public var underlyingError: Error? { nil }
    }

    /// An Auth API error response body, `{ "error": "...", "error_code": ... }`.
    public struct BodyError: Decodable, Equatable {
        /// The error, decoded from `error`.
        public let errorCode: BodyErrorCode
        /// Why the token was rejected, decoded from `error_code`. Nil when the response doesn't include it.
        public let tokenStatus: TokenStatus?

        private enum CodingKeys: String, CodingKey {
            case errorCode = "error"
            case tokenStatus = "error_code"
        }

        /// The error code's explanation, followed by the token status when there is one.
        public var description: String {
            var result = "Error code: \(self.errorCode.description)"
            if let tokenStatus = self.tokenStatus {
                result += ", token status: \(tokenStatus.description)"
            }
            return result
        }
    }

    private struct Defaults {
        /// Up to 3 retries, 2 seconds apart.
        static let defaultRetryPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .fixed(.seconds(2)))
    }

    /// The `ddg_auth_session_id` cookie that identifies an authorization session.
    /// - Parameters:
    ///   - domain: The cookie's domain, the Auth API host.
    ///   - path: The path of the request the cookie is sent with.
    ///   - authSessionID: The authorization session ID returned by `authorize`.
    /// - Returns: The cookie, or nil if the properties don't form a valid cookie.
    static func ddgAuthSessionCookie(domain: String, path: String, authSessionID: String) -> HTTPCookie? {
        return HTTPCookie(properties: [
            .domain: domain,
            .path: path,
            .name: "ddg_auth_session_id",
            .value: authSessionID
        ])
    }

    // MARK: -

    /// - Parameters:
    ///   - apiRequest: The HTTP request to send.
    ///   - httpSuccessCode: The status of a successful response.
    ///   - httpErrorCodes: The failure statuses whose response body is decoded as a `BodyError`.
    init(apiRequest: APIRequestV2,
         httpSuccessCode: HTTPStatusCode = HTTPStatusCode.ok,
         httpErrorCodes: [HTTPStatusCode] = [HTTPStatusCode.badRequest, HTTPStatusCode.internalServerError]) {
        self.apiRequest = apiRequest
        self.httpSuccessCode = httpSuccessCode
        self.httpErrorCodes = httpErrorCodes
    }

    // MARK: Authorize

    /// A request that starts an authorization session. Success is a 302 redirect that sets the `ddg_auth_session_id` cookie.
    /// Not retried.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - codeChallenge: The PKCE code challenge, S256.
    /// - Returns: The request, or nil when `codeChallenge` is empty.
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
                                         queryItems: queryItems) else { // we don't want to retry: https://app.asana.com/1/137249556945/task/1210411170978663/comment/1210411574944338?focus=true
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Create account

    /// A request that creates an account for an authorization session. Success is a 302 redirect carrying the authorization code.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - authSessionID: The authorization session ID returned by `authorize`, sent as a cookie.
    /// - Returns: The request, or nil when `authSessionID` is empty or the cookie can't be created.
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

    /// A request that emails a one-time password for logging in. Unused in the current implementation.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - authSessionID: The authorization session ID returned by `authorize`, sent as a cookie.
    ///   - emailAddress: Where the one-time password is sent.
    /// - Returns: The request, or nil when an argument is empty or the cookie can't be created.
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

    /// A request that logs in to an existing account for an authorization session. Success is a 302 redirect carrying the authorization code.
    /// Retried with the default retry policy.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - authSessionID: The authorization session ID returned by `authorize`, sent as a cookie.
    ///   - method: How to log in: a one-time password (`OAuthLoginMethodOTP`) or a purchase signature (`OAuthLoginMethodSignature`).
    /// - Returns: The request, or nil when `authSessionID` is empty, the cookie or body can't be created, or `method` is of another type.
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

    /// A request that exchanges an authorization code for a token pair. Retried with the default retry policy.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - clientID: The OAuth client ID.
    ///   - codeVerifier: The PKCE code verifier the code challenge was made from.
    ///   - code: The authorization code from `createAccount` or `login`.
    ///   - redirectURI: The redirect URI registered for the client.
    /// - Returns: The request, or nil when an argument is empty.
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

    /// A request that exchanges `refreshToken` for a new token pair. A 400 response is decoded as an auth API error;
    /// any other failure status, a 500 included, is thrown as `OAuthServiceError.invalidResponseCode`.
    /// Retried with the default retry policy, with a 20 second timeout.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - clientID: The OAuth client ID.
    ///   - refreshToken: The refresh token to spend.
    /// - Returns: The request, or nil when an argument is empty.
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
                                         timeoutInterval: 20.0,
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.badRequest])
    }

    // MARK: Edit Account

    /// A request that changes the account's email address. Unused in the current implementation.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - accessToken: The access token authorizing the request.
    ///   - email: The new email address, or nil.
    /// - Returns: The request, or nil when `accessToken` is empty.
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

    /// A request that confirms an email address change. Unused in the current implementation.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - accessToken: The access token authorizing the request.
    ///   - email: The new email address.
    ///   - hash: The hash from the confirmation email.
    ///   - otp: The one-time password from the confirmation email.
    /// - Returns: The request, or nil when an argument is empty.
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

    /// A request that logs out, revoking every token issued from the same login.
    /// - Parameters:
    ///   - baseURL: The Auth API base URL.
    ///   - accessToken: The access token of the session to log out.
    /// - Returns: The request, or nil when `accessToken` is empty.
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

    // MARK: JWKs

    /// This endpoint is where the Auth service will publish public keys for consuming services and clients to use to independently verify access tokens. Tokens should be downloaded and cached for an hour upon first use. When rotating private keys for signing JWTs, the Auth service will publish new public keys 24 hours in advance of starting to sign new JWTs with them. This should provide consuming services with plenty of time to invalidate their public key cache and have the new key available before they can expect to start receiving JWTs signed with the old key. The old key will remain published until the next key rotation, so there should generally be two public keys available through this endpoint. The response format is a standard JWKS response, as documented in RFC 7517.
    /// Any failure status is thrown as `OAuthServiceError.invalidResponseCode`. Retried with the default retry policy.
    /// - Parameter baseURL: The Auth API base URL.
    /// - Returns: The request, or nil when the URL can't be built.
    static func jwks(baseURL: URL) -> OAuthRequest? {
        let path = "/api/auth/v2/.well-known/jwks.json"

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         retryPolicy: Defaults.defaultRetryPolicy) else {
            return nil
        }
        return OAuthRequest(apiRequest: request,
                            httpSuccessCode: .ok,
                            httpErrorCodes: [])
    }
}
