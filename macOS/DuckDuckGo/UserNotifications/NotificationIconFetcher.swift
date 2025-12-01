//
//  NotificationIconFetcher.swift
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

import Common
import Foundation
import OSLog
import UserNotifications

/// Abstraction for fetching notification icons, enabling dependency injection and testing.
protocol NotificationIconFetching {

    /// Fetches an image from the given URL and creates a notification attachment.
    /// - Parameter url: The URL of the image to fetch.
    /// - Returns: A notification attachment, or `nil` if the fetch fails.
    func fetchIcon(from url: URL) async -> UNNotificationAttachment?
}

/// Downloads images from URLs and creates `UNNotificationAttachment` instances.
///
/// `UNNotificationAttachment` requires a file URL, so this fetcher writes the downloaded
/// image data to a temporary file before creating the attachment.
final class NotificationIconFetcher: NotificationIconFetching {

    private enum Constants {
        static let httpStatusOK = 200
        static let contentTypeHeader = "Content-Type"

        static let extensionPNG = "png"
        static let extensionJPG = "jpg"
        static let extensionJPEG = "jpeg"
        static let extensionGIF = "gif"

        static let supportedExtensions = [extensionPNG, extensionJPG, extensionJPEG, extensionGIF]
    }

    func fetchIcon(from url: URL) async -> UNNotificationAttachment? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == Constants.httpStatusOK else {
                Logger.general.debug("WebNotificationsHandler: Icon fetch failed - bad response")
                return nil
            }

            let fileExtension = self.fileExtension(from: httpResponse, url: url)
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileName = UUID().uuidString + "." + fileExtension
            let fileURL = tempDirectory.appendingPathComponent(fileName)

            try data.write(to: fileURL)

            let attachment = try UNNotificationAttachment(
                identifier: UUID().uuidString,
                url: fileURL,
                options: nil)

            return attachment
        } catch {
            Logger.general.debug("WebNotificationsHandler: Icon fetch failed - \(error.localizedDescription)")
            return nil
        }
    }

    /// Determines file extension from HTTP response content type, falling back to URL path extension.
    private func fileExtension(from response: HTTPURLResponse, url: URL) -> String {
        if let contentType = response.value(forHTTPHeaderField: Constants.contentTypeHeader) {
            switch contentType {
            case let type where type.contains(Constants.extensionPNG):
                return Constants.extensionPNG
            case let type where type.contains(Constants.extensionJPEG), let type where type.contains(Constants.extensionJPG):
                return Constants.extensionJPG
            case let type where type.contains(Constants.extensionGIF):
                return Constants.extensionGIF
            default:
                break
            }
        }

        let pathExtension = url.pathExtension.lowercased()
        if Constants.supportedExtensions.contains(pathExtension) {
            return pathExtension
        }

        return Constants.extensionPNG
    }
}
