//
//  OAuthServiceTests.swift
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

import XCTest
@testable import Networking

final class AuthServiceTests: XCTestCase {

    let baseURL = OAuthEnvironment.staging.url

    override func setUpWithError() throws {
        /*
         var mockedApiService = MockAPIService(decodableResponse: <#T##Result<any Decodable, any Error>#>,
         apiResponse: <#T##Result<(data: Data?, httpResponse: HTTPURLResponse), any Error>#>)
         */
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    var realAPISService: APIService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let urlSession = URLSession(configuration: configuration,
                                    delegate: SessionDelegate(),
                                    delegateQueue: nil)
        return DefaultAPIService(urlSession: urlSession)
    }

    // MARK: - REAL tests, useful for development and debugging but disabled for normal testing

    func disabled_test_real_AuthoriseSuccess() async throws {
        let authService = DefaultOAuthService(baseURL: baseURL, apiService: realAPISService)
        let codeVerifier = try OAuthCodesGenerator.generateCodeVerifier()
        let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier)!
        let result = try await authService.authorize(codeChallenge: codeChallenge)
        XCTAssertNotNil(result)
    }

    func disabled_test_real_AuthoriseFailure() async throws {
        let authService = DefaultOAuthService(baseURL: baseURL, apiService: realAPISService)
        do {
            _ = try await authService.authorize(codeChallenge: "")
        } catch {
            switch error {
            case OAuthServiceError.authAPIError(let apiError):
                XCTAssertEqual(apiError.bodyError.errorCode.rawValue, "invalid_authorization_request")
                XCTAssertEqual(apiError.bodyError.errorCode.description, "One or more of the required parameters are missing or any provided parameters have invalid values")
            default:
                XCTFail("Wrong error")
            }
        }
    }

    func disabled_test_real_GetJWTSigner() async throws {
        let authService = DefaultOAuthService(baseURL: baseURL, apiService: realAPISService)
        let signer = try await authService.getJWTSigners()
        do {
            let _: JWTAccessToken = try signer.verify("sdfgdsdzfgsdf")
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testBodyErrorDecodingIncludesTokenStatus() throws {
        // Decoding should map error to errorCode and error_code to tokenStatus.
        let json = """
        {
          "error": "invalid_token_request",
          "error_code": 2
        }
        """
        let data = Data(json.utf8)
        let bodyError = try JSONDecoder().decode(OAuthRequest.BodyError.self, from: data)

        XCTAssertEqual(bodyError.errorCode, .invalidTokenRequest)
        XCTAssertEqual(bodyError.tokenStatus, .reused)
    }

    func testBodyErrorDecodingWithoutTokenStatus() throws {
        // When error_code is missing, tokenStatus should be nil.
        let json = """
        {
          "error": "invalid_authorization_request"
        }
        """
        let data = Data(json.utf8)
        let bodyError = try JSONDecoder().decode(OAuthRequest.BodyError.self, from: data)

        XCTAssertEqual(bodyError.errorCode, .invalidAuthorizationRequest)
        XCTAssertNil(bodyError.tokenStatus)
    }
}
