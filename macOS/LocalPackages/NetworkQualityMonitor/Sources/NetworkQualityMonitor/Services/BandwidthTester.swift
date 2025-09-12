//
//  BandwidthTester.swift
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

public final class BandwidthTester: BandwidthTesting {
    
    // MARK: - Constants
    
    private enum Constants {
        static let downloadProgressMessage = "Testing download speed..."
        static let uploadProgressMessage = "Testing upload speed..."
        static let httpMethodGet = "GET"
        static let httpMethodPost = "POST"
        static let rangeHeader = "Range"
        static let contentTypeHeader = "Content-Type"
        static let rangeBytes10MB = "bytes=0-10485760"
        static let applicationOctetStream = "application/octet-stream"
        static let quickTestTimeout: TimeInterval = 5
        static let serverCompetitiveThreshold = 0.8  // 80% of best speed
        static let megabitsPerByte = 8.0 / 1_000_000
    }
    private let session: NetworkSession
    
    public init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }
    
    public func performDownloadTest(configuration: TestConfiguration,
                            progressCallback: ((String) -> Void)? = nil) async throws -> Double {
        progressCallback?(Constants.downloadProgressMessage)
        
        var bestSpeed: Double = 0
        
        for server in configuration.bandwidthTestURLs {
            // Quick test to find best server
            let quickSpeed = await measureQuickDownload(from: server, timeout: Constants.quickTestTimeout)
            
            if quickSpeed > bestSpeed * Constants.serverCompetitiveThreshold {
                // Full test
                let fullSpeed = await measureFullDownload(
                    from: server,
                    runs: configuration.bandwidthRunsPerServer,
                    timeout: configuration.bandwidthTestTimeout
                )
                
                if fullSpeed > bestSpeed {
                    bestSpeed = fullSpeed
                }
            }
        }
        
        guard bestSpeed > 0 else {
            throw NetworkError.allTestsFailed
        }
        
        return bestSpeed
    }
    
    public func performUploadTest(configuration: TestConfiguration,
                          progressCallback: ((String) -> Void)? = nil) async throws -> Double {
        progressCallback?(Constants.uploadProgressMessage)
        
        var bestSpeed: Double = 0
        let testData = Data(count: configuration.uploadChunkSize)
        
        for server in configuration.uploadTestURLs {
            let speed = await measureUpload(
                to: server,
                data: testData,
                chunks: configuration.uploadChunkCount,
                timeout: configuration.uploadTestTimeout
            )
            
            if speed > bestSpeed {
                bestSpeed = speed
            }
        }
        
        guard bestSpeed > 0 else {
            throw NetworkError.allTestsFailed
        }
        
        return bestSpeed
    }
    
    // MARK: - Private Methods
    
    private func measureQuickDownload(from url: URL, timeout: TimeInterval) async -> Double {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpMethod = Constants.httpMethodGet
        request.setValue(Constants.rangeBytes10MB, forHTTPHeaderField: Constants.rangeHeader)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let (data, response) = try await session.data(from: url)
            let endTime = CFAbsoluteTimeGetCurrent()
            
            if let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode || httpResponse.statusCode == 206 {
                let duration = endTime - startTime
                let speedMbps = Double(data.count) * Constants.megabitsPerByte / duration
                return speedMbps
            }
        } catch {
            // Download failed
        }
        
        return 0
    }
    
    private func measureFullDownload(from url: URL, runs: Int, timeout: TimeInterval) async -> Double {
        var speeds: [Double] = []
        
        for _ in 0..<runs {
            let speed = await measureSingleDownload(from: url, timeout: timeout)
            if speed > 0 {
                speeds.append(speed)
            }
        }
        
        guard !speeds.isEmpty else { return 0 }
        
        // Return the best speed
        return speeds.max() ?? 0
    }
    
    private func measureSingleDownload(from url: URL, timeout: TimeInterval) async -> Double {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let (data, response) = try await session.data(from: url)
            let endTime = CFAbsoluteTimeGetCurrent()
            
            if let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode {
                let duration = endTime - startTime
                let speedMbps = Double(data.count) * Constants.megabitsPerByte / duration
                return speedMbps
            }
        } catch {
            // Download failed
        }
        
        return 0
    }
    
    private func measureUpload(to url: URL, data: Data, chunks: Int, timeout: TimeInterval) async -> Double {
        var request = URLRequest(url: url)
        request.httpMethod = Constants.httpMethodPost
        request.timeoutInterval = timeout
        request.setValue(Constants.applicationOctetStream, forHTTPHeaderField: Constants.contentTypeHeader)
        
        var totalBytes = 0
        var totalDuration: TimeInterval = 0
        
        for _ in 0..<chunks {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            do {
                let (_, response) = try await session.upload(for: request, from: data)
                let endTime = CFAbsoluteTimeGetCurrent()
                
                if let httpResponse = response as? HTTPURLResponse,
                   200...299 ~= httpResponse.statusCode {
                    totalBytes += data.count
                    totalDuration += (endTime - startTime)
                }
            } catch {
                // Upload failed, continue with other chunks
            }
        }
        
        guard totalDuration > 0 else { return 0 }
        
        let speedMbps = Double(totalBytes) * Constants.megabitsPerByte / totalDuration
        return speedMbps
    }
}