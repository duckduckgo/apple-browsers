//
//  NetworkQualityMonitor.swift
//  NetworkQualityMonitor
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

/// Main public interface for network quality monitoring
/// This class maintains backward compatibility while using the refactored implementation
public final class NetworkQualityMonitor {
    
    private let implementation: NetworkQualityMonitorRefactored
    
    /// Progress callback for UI updates
    public var progressCallback: ((Double, String) -> Void)? {
        get { implementation.progressCallback }
        set { implementation.progressCallback = newValue }
    }
    
    /// Initialize with default configuration
    public init() {
        self.implementation = NetworkQualityMonitorRefactored(configuration: .standard)
    }
    
    /// Initialize with custom configuration
    public init(configuration: TestConfiguration) {
        self.implementation = NetworkQualityMonitorRefactored(configuration: configuration)
    }
    
    /// Run the complete network quality test
    public func runTest() async throws -> NetworkTestResults {
        try await implementation.runTest()
    }
    
    /// Quick connectivity check
    public func checkConnectivity() async -> Bool {
        await implementation.checkConnectivity()
    }
}