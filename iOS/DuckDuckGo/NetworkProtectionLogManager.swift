//
//  NetworkProtectionLogManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import VPN

final class NetworkProtectionLogManager {
    
    enum LogManagerError: Error {
        case appGroupContainerNotFound
        case fileReadFailed
        case noLogsFound
    }
    
    private let appGroupIdentifier: String
    private let fileManager = FileManager.default
    
    init() {
        self.appGroupIdentifier = Bundle.main.vpnAppGroupName
    }
    
    func getExistingLogFiles() throws -> [URL] {
        let containerURL = try getAppGroupContainer()
        let logsDirectory = containerURL.appendingPathComponent("debug-logs")
        
        guard fileManager.fileExists(atPath: logsDirectory.path) else {
            return []
        }
        
        let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
            .filter { $0.pathExtension == "txt" && $0.lastPathComponent.hasPrefix("iOS-VPN-logs-") }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
        
        return logFiles
    }
    
    func readLogFile(at url: URL) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            throw LogManagerError.fileReadFailed
        }
        
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    func deleteLogFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
    
    private func getAppGroupContainer() throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw LogManagerError.appGroupContainerNotFound
        }
        return containerURL
    }
}
