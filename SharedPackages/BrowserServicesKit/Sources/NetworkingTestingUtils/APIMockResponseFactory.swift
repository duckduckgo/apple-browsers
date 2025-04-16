//
//  APIMockResponseFactory.swift
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
@testable import Networking

public struct APIMockResponseFactory {

    static let authCookieHeaders = [ HTTPHeaderKey.setCookie: "ddg_auth_session_id=kADeCPMmCIHIV5uD6AFoB7Fk7pRiXFzlmQE4gW9r7FRKV8OGC1rRnZcTXoa7iIa8qgjiQCqZYq6Caww6k5HJl3; domain=duckduckgo.com; path=/api/auth/v2/; max-age=600; SameSite=Strict; secure; HttpOnly"]

    static let someAPIBodyErrorJSON = "{\"error\":\"invalid_authorization_request\"}"
    static var someAPIBodyErrorJSONData: Data {
        someAPIBodyErrorJSON.data(using: .utf8)!
    }

    static func setErrorResponse(forRequest request: APIRequestV2, apiService: MockAPIService) {
        let httpResponse = HTTPURLResponse(url: request.urlRequest.url!,
                                           statusCode: HTTPStatusCode.badRequest.rawValue,
                                           httpVersion: nil,
                                           headerFields: [:])!
        let response = APIResponseV2(data: someAPIBodyErrorJSONData, httpResponse: httpResponse)
        apiService.set(response: response, forRequest: request)
    }

    public static func mockAuthoriseResponse(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = OAuthRequest.authorize(baseURL: OAuthEnvironment.staging.url, codeChallenge: "codeChallenge")!
        if success {
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: request.httpSuccessCode.rawValue,
                                               httpVersion: nil,
                                               headerFields: authCookieHeaders)!
            let response = APIResponseV2(data: nil, httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }

    public static func mockCreateAccountResponse(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = OAuthRequest.createAccount(baseURL: OAuthEnvironment.staging.url, authSessionID: "someAuthSessionID")!
        if success {
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: request.httpSuccessCode.rawValue,
                                               httpVersion: nil,
                                               headerFields: [HTTPHeaderKey.location: "com.duckduckgo:/authcb?code=NgNjnlLaqUomt9b5LDbzAtTyeW9cBNhCGtLB3vpcctluSZI51M9tb2ZDIZdijSPTYBr4w8dtVZl85zNSemxozv"])!
            let response = APIResponseV2(data: nil, httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }

    public static func mockGetAccessTokenResponse(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = OAuthRequest.getAccessToken(baseURL: OAuthEnvironment.staging.url,
                                                  clientID: "clientID",
                                                  codeVerifier: "codeVerifier",
                                                  code: "code",
                                                  redirectURI: "redirectURI")!
        if success {
            let jsonString = """
{"access_token":"eyJraWQiOiIzODJiNzQ5Yy1hNTc3LTRkOTMtOTU0My04NTI5MWZiYTM3MmEiLCJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiJxWHk2TlRjeEI2UkQ0UUtSU05RYkNSM3ZxYU1SQU1RM1Q1UzVtTWdOWWtCOVZTVnR5SHdlb1R4bzcxVG1DYkJKZG1GWmlhUDVWbFVRQnd5V1dYMGNGUjo3ZjM4MTljZi0xNTBmLTRjYjEtOGNjNy1iNDkyMThiMDA2ZTgiLCJzY29wZSI6InByaXZhY3lwcm8iLCJhdWQiOiJQcml2YWN5UHJvIiwic3ViIjoiZTM3NmQ4YzQtY2FhOS00ZmNkLThlODYtMTlhNmQ2M2VlMzcxIiwiZXhwIjoxNzMwMzAxNTcyLCJlbWFpbCI6bnVsbCwiaWF0IjoxNzMwMjg3MTcyLCJpc3MiOiJodHRwczovL3F1YWNrZGV2LmR1Y2tkdWNrZ28uY29tIiwiZW50aXRsZW1lbnRzIjpbXSwiYXBpIjoidjIifQ.wOYgz02TXPJjDcEsp-889Xe1zh6qJG0P1UNHUnFBBELmiWGa91VQpqdl41EOOW3aE89KGvrD8YphRoZKiA3nHg",
    "refresh_token":"eyJraWQiOiIzODJiNzQ5Yy1hNTc3LTRkOTMtOTU0My04NTI5MWZiYTM3MmEiLCJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcGkiOiJ2MiIsImlzcyI6Imh0dHBzOi8vcXVhY2tkZXYuZHVja2R1Y2tnby5jb20iLCJleHAiOjE3MzI4NzkxNzIsInN1YiI6ImUzNzZkOGM0LWNhYTktNGZjZC04ZTg2LTE5YTZkNjNlZTM3MSIsImF1ZCI6IkF1dGgiLCJpYXQiOjE3MzAyODcxNzIsInNjb3BlIjoicmVmcmVzaCIsImp0aSI6InFYeTZOVGN4QjZSRDRRS1JTTlFiQ1IzdnFhTVJBTVEzVDVTNW1NZ05Za0I5VlNWdHlId2VvVHhvNzFUbUNiQkpkbUZaaWFQNVZsVVFCd3lXV1gwY0ZSOmU2ODkwMDE5LWJmMDUtNGQxZC04OGFhLThlM2UyMDdjOGNkOSJ9.OQaGCmDBbDMM5XIpyY-WCmCLkZxt5Obp4YAmtFP8CerBSRexbUUp6SNwGDjlvCF0-an2REBsrX92ZmQe5ewqyQ","expires_in": 14400,"token_type": "Bearer"}
"""
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: request.httpSuccessCode.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: jsonString.data(using: .utf8), httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }

    public static func mockRefreshAccessTokenResponse(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = OAuthRequest.refreshAccessToken(baseURL: OAuthEnvironment.staging.url,
                                                      clientID: "clientID",
                                                      refreshToken: "someExpiredToken")!
        if success {
            let jsonString = """
{"access_token":"eyJraWQiOiIzODJiNzQ5Yy1hNTc3LTRkOTMtOTU0My04NTI5MWZiYTM3MmEiLCJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiJxWHk2TlRjeEI2UkQ0UUtSU05RYkNSM3ZxYU1SQU1RM1Q1UzVtTWdOWWtCOVZTVnR5SHdlb1R4bzcxVG1DYkJKZG1GWmlhUDVWbFVRQnd5V1dYMGNGUjo3ZjM4MTljZi0xNTBmLTRjYjEtOGNjNy1iNDkyMThiMDA2ZTgiLCJzY29wZSI6InByaXZhY3lwcm8iLCJhdWQiOiJQcml2YWN5UHJvIiwic3ViIjoiZTM3NmQ4YzQtY2FhOS00ZmNkLThlODYtMTlhNmQ2M2VlMzcxIiwiZXhwIjoxNzMwMzAxNTcyLCJlbWFpbCI6bnVsbCwiaWF0IjoxNzMwMjg3MTcyLCJpc3MiOiJodHRwczovL3F1YWNrZGV2LmR1Y2tkdWNrZ28uY29tIiwiZW50aXRsZW1lbnRzIjpbXSwiYXBpIjoidjIifQ.wOYgz02TXPJjDcEsp-889Xe1zh6qJG0P1UNHUnFBBELmiWGa91VQpqdl41EOOW3aE89KGvrD8YphRoZKiA3nHg",
    "refresh_token":"eyJraWQiOiIzODJiNzQ5Yy1hNTc3LTRkOTMtOTU0My04NTI5MWZiYTM3MmEiLCJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcGkiOiJ2MiIsImlzcyI6Imh0dHBzOi8vcXVhY2tkZXYuZHVja2R1Y2tnby5jb20iLCJleHAiOjE3MzI4NzkxNzIsInN1YiI6ImUzNzZkOGM0LWNhYTktNGZjZC04ZTg2LTE5YTZkNjNlZTM3MSIsImF1ZCI6IkF1dGgiLCJpYXQiOjE3MzAyODcxNzIsInNjb3BlIjoicmVmcmVzaCIsImp0aSI6InFYeTZOVGN4QjZSRDRRS1JTTlFiQ1IzdnFhTVJBTVEzVDVTNW1NZ05Za0I5VlNWdHlId2VvVHhvNzFUbUNiQkpkbUZaaWFQNVZsVVFCd3lXV1gwY0ZSOmU2ODkwMDE5LWJmMDUtNGQxZC04OGFhLThlM2UyMDdjOGNkOSJ9.OQaGCmDBbDMM5XIpyY-WCmCLkZxt5Obp4YAmtFP8CerBSRexbUUp6SNwGDjlvCF0-an2REBsrX92ZmQe5ewqyQ","expires_in": 14400,"token_type": "Bearer"}
"""
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: request.httpSuccessCode.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: jsonString.data(using: .utf8), httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }

    public static func mockGetJWKS(destinationMockAPIService apiService: MockAPIService, success: Bool) {
        let request = OAuthRequest.jwks(baseURL: OAuthEnvironment.staging.url)!
        if success {
            let jsonString = """
{"keys":[{"alg":"ES256","crv":"P-256","kid":"382b749c-a577-4d93-9543-85291fba372a","kty":"EC","ts":1727109704,"x":"e-WcWXtyf0mzVuc8lzAErb0EYq0kiOj7u8Ia4qsB4z4","y":"2WYzD5-POgIx2_3B_J6u84giGwSwgrYMTj83djMSWxM"},{"crv":"P-256","kid":"aa4c0019-9da9-4143-9866-3f7b54224a46","kty":"EC","ts":1722282670,"x":"kN2BXRyRbylNSaw3CrZKiKdATXjF1RIp2FpOxYMeuWg","y":"wovX-ifQuoKKAi-ZPYFcZ9YBhCxN_Fng3qKSW2wKpdg"}]}
"""
            let httpResponse = HTTPURLResponse(url: request.apiRequest.urlRequest.url!,
                                               statusCode: request.httpSuccessCode.rawValue,
                                               httpVersion: nil,
                                               headerFields: [:])!
            let response = APIResponseV2(data: jsonString.data(using: .utf8), httpResponse: httpResponse)
            apiService.set(response: response, forRequest: request.apiRequest)
        } else {
            setErrorResponse(forRequest: request.apiRequest, apiService: apiService)
        }
    }
}
