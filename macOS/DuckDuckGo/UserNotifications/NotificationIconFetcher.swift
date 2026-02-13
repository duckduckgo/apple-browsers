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
    /// - Parameters:
    ///   - url: The URL of the image to fetch.
    ///   - originURL: The URL of the page requesting the notification (for same-origin validation).
    /// - Returns: A notification attachment, or `nil` if the fetch fails.
    func fetchIcon(from url: URL, originURL: URL) async -> UNNotificationAttachment?
}

/// URLSession delegate that blocks redirects violating same-origin policy.
private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate {
    let originURL: URL
    let validateURL: (URL, URL) -> Bool

    init(originURL: URL, validateURL: @escaping (URL, URL) -> Bool) {
        self.originURL = originURL
        self.validateURL = validateURL
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let redirectURL = request.url, validateURL(redirectURL, originURL) else {
            Logger.general.debug("WebNotificationsHandler: Icon fetch blocked - invalid redirect")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
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

        // Security limits
        static let maxFileSizeBytes: Int64 = 5 * 1024 * 1024 // 5 MB
        static let requestTimeoutSeconds: TimeInterval = 10.0
    }

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.requestTimeoutSeconds
        configuration.timeoutIntervalForResource = Constants.requestTimeoutSeconds
        return URLSession(configuration: configuration)
    }()

    func fetchIcon(from url: URL, originURL: URL) async -> UNNotificationAttachment? {
        // Validate URL before fetching
        guard validateIconURL(url, originURL: originURL) else {
            Logger.general.debug("WebNotificationsHandler: Icon fetch blocked - validation failed for \(url.absoluteString)")
            return nil
        }

        // Create session with redirect blocking delegate
        let delegate = RedirectBlockingDelegate(originURL: originURL, validateURL: validateIconURL)
        let session = URLSession(configuration: urlSession.configuration, delegate: delegate, delegateQueue: nil)
        defer {
            // Invalidate session to break strong reference cycle with delegate
            session.finishTasksAndInvalidate()
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == Constants.httpStatusOK else {
                Logger.general.debug("WebNotificationsHandler: Icon fetch failed - bad response: \(String(describing: response))")
                return nil
            }

            // Enforce file size limit to prevent DoS
            guard Int64(data.count) <= Constants.maxFileSizeBytes else {
                Logger.general.debug("WebNotificationsHandler: Icon fetch blocked - file too large: \(data.count) bytes")
                return nil
            }

            let finalURL = response.url ?? url
            let fileExtension = self.fileExtension(from: httpResponse, url: finalURL)
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

    private func defaultPort(for scheme: String) -> Int {
        switch scheme.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return 0
        }
    }

    // MARK: - URL Validation

    /// Validates that the icon URL is safe to fetch.
    /// - Parameters:
    ///   - url: The icon URL to validate.
    ///   - originURL: The origin URL of the page requesting the notification.
    /// - Returns: `true` if the URL is safe to fetch, `false` otherwise.
    private func validateIconURL(_ url: URL, originURL: URL) -> Bool {
        // Block file:// scheme to prevent local file system access
        if url.scheme?.lowercased() == "file" {
            Logger.general.debug("WebNotificationsHandler: Icon fetch blocked - file:// scheme not allowed")
            return false
        }

        // Only allow http/https schemes
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            Logger.general.debug("WebNotificationsHandler: Icon fetch blocked - invalid scheme: \(url.scheme ?? "nil")")
            return false
        }

        // Enforce same-origin policy (automatically blocks cross-origin requests including internal networks)
        guard isSameOrigin(url, originURL: originURL) else {
            Logger.general.debug("WebNotificationsHandler: Icon fetch blocked - cross-origin request not allowed")
            return false
        }

        return true
    }

    /// Checks if two URLs have the same origin (scheme, host, and port must match).
    /// Per web standards, URL schemes and hosts are case-insensitive.
    private func isSameOrigin(_ url: URL, originURL: URL) -> Bool {
        // Normalize protocol and host to lowercase for case-insensitive comparison
        let iconProtocol = url.securityOrigin.protocol.lowercased()
        let iconHost = url.securityOrigin.host.lowercased()
        var iconPort = url.securityOrigin.port

        let pageProtocol = originURL.securityOrigin.protocol.lowercased()
        let pageHost = originURL.securityOrigin.host.lowercased()
        var pagePort = originURL.securityOrigin.port

        // Normalize ports (0 means default port for the scheme)
        if iconPort == 0 {
            iconPort = defaultPort(for: iconProtocol)
        }
        if pagePort == 0 {
            pagePort = defaultPort(for: pageProtocol)
        }

        // Compare normalized origins
        let iconOrigin = SecurityOrigin(protocol: iconProtocol, host: iconHost, port: iconPort)
        let pageOrigin = SecurityOrigin(protocol: pageProtocol, host: pageHost, port: pagePort)

        return iconOrigin == pageOrigin
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
