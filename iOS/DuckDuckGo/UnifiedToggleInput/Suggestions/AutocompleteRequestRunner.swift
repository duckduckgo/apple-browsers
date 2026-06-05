//
//  AutocompleteRequestRunner.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Foundation

/// Owns a single in-flight autocomplete network request and cancels the prior one when a new
/// request starts. One instance per suggestions surface — sharing a single task across surfaces
/// makes them cancel each other's requests.
final class AutocompleteRequestRunner {

    private var task: URLSessionDataTask?

    func run(_ request: URLRequest, completion: @escaping (Data?, Error?) -> Void) {
        task?.cancel()
        task = URLSession.shared.dataTask(with: request) { data, _, error in
            completion(data, error)
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
