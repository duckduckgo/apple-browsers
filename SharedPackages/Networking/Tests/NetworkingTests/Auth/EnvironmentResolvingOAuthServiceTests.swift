//
//  EnvironmentResolvingOAuthServiceTests.swift
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

import XCTest
@_spi(Testing) @testable import Networking

final class EnvironmentResolvingOAuthServiceTests: XCTestCase {

    private struct RequestFailed: Error {}

    func testWhenTheEnvironmentChangesThenRequestsGoToTheNewEnvironment() async {
        var requestedHosts: [String] = []
        let apiService = MockAPIService { request in
            requestedHosts.append(request.host)
            return .failure(RequestFailed())
        }
        var environment = OAuthEnvironment.staging
        let service = EnvironmentResolvingOAuthService(apiService: apiService) { environment }

        _ = try? await service.getJWTSigners()
        environment = .production
        _ = try? await service.getJWTSigners()

        XCTAssertEqual(requestedHosts, [OAuthEnvironment.staging.url.host, OAuthEnvironment.production.url.host])
    }
}
