//
//  APIRequest.swift
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
import os.log

public typealias APIResponse = (data: Data?, response: HTTPURLResponse)
public typealias APIRequestCompletion = (APIResponse?, APIRequest.Error?) -> Void

public struct APIRequest {
    let request: URLRequest
    private let requirements: APIResponseRequirements
    private let urlSession: URLSession

    public init<QueryParams: Collection>(configuration: APIRequest.Configuration<QueryParams>,
                                         requirements: APIResponseRequirements = [],
                                         urlSession: URLSession = .shared) {
        self.request = configuration.request
        self.requirements = requirements
        self.urlSession = urlSession

        guard request.allHTTPHeaderFields?[HTTPHeaderKey.userAgent] != nil else {
            assertionFailure("A user agent must be included in the request's HTTP header fields.")
            return
        }
    }

    @available(*, deprecated, message: "Please use 'APIService' instead.")
    @discardableResult public func fetch(completion: @escaping APIRequestCompletion) -> URLSessionDataTask {
        Logger.networking.debug("Requesting \(request.httpMethod ?? "") \(request.url?.absoluteString ?? ""), headers \(String(describing: request.allHTTPHeaderFields ?? [:]))")
        let task = urlSession.dataTask(with: request) { (data, urlResponse, error) in
            if let error = error {
                completion(nil, .urlSession(error))
            } else {
                do {
                    guard let urlResponse = urlResponse else { throw APIRequest.Error.invalidResponse }
                    let response = try self.validateAndUnwrap(data: data, response: urlResponse)
                    completion(response, nil)
                } catch {
                    completion(nil, error as? APIRequest.Error ?? .urlSession(error))
                }
            }
        }
        task.resume()
        return task
    }

    fileprivate func validateAndUnwrap(data: Data?, response: URLResponse) throws -> APIResponse {
        let httpResponse = try response.asHTTPURLResponse()

        Logger.networking.debug("Request completed: \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "") response code: \(httpResponse.statusCode)")

        var data = data
        if requirements.contains(.allowHTTPNotModified), httpResponse.httpStatus == .notModified {
            data = nil // avoid returning empty data
        } else {
            guard httpResponse.httpStatus.isSuccess else {
                throw APIRequest.Error.invalidStatusCode(httpResponse.statusCode)
            }
            let data = data ?? Data()
            if requirements.contains(.requireNonEmptyData), data.isEmpty {
                throw APIRequest.Error.emptyData
            }
        }

        if requirements.contains(.requireETagHeader), httpResponse.etag == nil {
            throw APIRequest.Error.missingEtagInResponse
        }

        return (data, httpResponse)
    }

    @available(*, deprecated, message: "Please use 'APIService' instead.")
    public func fetch() async throws -> APIResponse {
        Logger.networking.debug("Requesting \(request.httpMethod ?? "") \(request.url?.absoluteString ?? ""), headers \(String(describing: request.allHTTPHeaderFields ?? [:]))")
        let (data, response) = try await fetch(for: request)
        return try validateAndUnwrap(data: data, response: response)
    }

    fileprivate func fetch(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error {
            throw Error.urlSession(error)
        }
    }
}
