//
//  URLExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Network

extension URL {

    public static let empty = (NSURL(string: "") ?? NSURL()) as URL

    public var isEmpty: Bool {
        absoluteString.isEmpty
    }

    public func matches(_ other: URL) -> Bool {
        let string1 = self.absoluteString
        let string2 = other.absoluteString
        return string1.droppingHashedSuffix().dropping(suffix: "/").appending(string1.hashedSuffix ?? "")
            == string2.droppingHashedSuffix().dropping(suffix: "/").appending(string2.hashedSuffix ?? "")
    }

    /// URL without the scheme and the '/' suffix of the path.
    /// Useful for finding duplicate URLs
    public var naked: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.scheme = nil
        components.host = components.host?.droppingWwwPrefix()
        if components.path.last == "/" {
            components.path.removeLast()
        }
        return components.url
    }

    public var nakedString: String? {
        naked?.absoluteString.dropping(prefix: "//")
    }

    public var root: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    public var isRoot: Bool {
        (path.isEmpty || path == "/") &&
        query == nil &&
        fragment == nil &&
        user == nil &&
        password == nil
    }

    public var securityOrigin: SecurityOrigin {
        SecurityOrigin(protocol: self.scheme ?? "",
                       host: self.host ?? "",
                       port: self.port ?? 0)
    }

    public func isPart(ofDomain domain: String) -> Bool {
        guard let host = host else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    public struct NavigationalScheme: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public static let separator = "://"

        public static let http = NavigationalScheme(rawValue: "http")
        public static let https = NavigationalScheme(rawValue: "https")
        public static let ftp = NavigationalScheme(rawValue: "ftp")
        public static let file = NavigationalScheme(rawValue: "file")
        public static let data = NavigationalScheme(rawValue: "data")
        public static let blob = NavigationalScheme(rawValue: "blob")
        public static let about = NavigationalScheme(rawValue: "about")
        public static let duck = NavigationalScheme(rawValue: "duck")
        public static let mailto = NavigationalScheme(rawValue: "mailto")
        public static let webkitExtension = NavigationalScheme(rawValue: "webkit-extension")

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public func separated() -> String {
            if case .mailto = self {
                return self.rawValue + ":"
            }
            return self.rawValue + Self.separator
        }

        public static var navigationalSchemes: [NavigationalScheme] {
            return [.http, .https, .ftp, .file, .data, .blob, .about, duck]
        }

        public static var schemesWithRemovableBasicAuth: [NavigationalScheme] {
            return [.http, .https, .ftp, .file]
        }

        public static var hypertextSchemes: [NavigationalScheme] {
            return [.http, .https]
        }

        public static var punycodeEncodableSchemes: [NavigationalScheme] {
            return [.http, .https, .ftp, .mailto]
        }

        public var defaultPort: Int? {
            switch self {
            case .http: return 80
            case .https: return 443
            case .ftp: return 23
            default: return nil
            }
        }
    }

    public var navigationalScheme: NavigationalScheme? {
        self.scheme.map(NavigationalScheme.init(rawValue:))
    }

    public var isValid: Bool {
        guard let navigationalScheme else { return false }

        if NavigationalScheme.hypertextSchemes.contains(navigationalScheme) {
           return host?.isValidHost == true
        }

        // This effectively allows file:// and External App Scheme URLs to be entered by user
        // Without this check single word entries get treated like domains
        return true
    }

    // swiftlint:disable cyclomatic_complexity
    /// URL and URLComponents can't cope with emojis and international characters so this routine does some manual processing while trying to
    /// retain the input as much as possible.
    public init?(trimmedAddressBarString: String) {
        var s = trimmedAddressBarString

        // Creates URL even if user enters one slash "/" instead of two slashes "//" after the hypertext scheme component
        if let scheme = NavigationalScheme.hypertextSchemes.first(where: { s.hasPrefix($0.rawValue + ":/") }),
           !s.hasPrefix(scheme.separated()) {
            s = scheme.separated() + s.dropFirst(scheme.separated().count - 1)
        }

        let url: URL?
        let urlWithScheme: URL?
        if #available(macOS 14.0, iOS 17.0, *) {
            // Making sure string is strictly valid according to the RFC
            url = URL(string: s, encodingInvalidCharacters: false)
            urlWithScheme = URL(string: NavigationalScheme.http.separated() + s, encodingInvalidCharacters: false)
        } else {
            url = URL(string: s)
            urlWithScheme = URL(string: NavigationalScheme.http.separated() + s)
        }

        if let url {
            // if URL has domain:port or user:password@domain mistakengly interpreted as a scheme
            if url.navigationalScheme != .mailto,
               let urlWithScheme,
               urlWithScheme.port != nil || urlWithScheme.user != nil {
                // could be a local domain but user needs to use the protocol to specify that
                // make exception for "localhost"
                let hasDomain = urlWithScheme.host?.contains(".") == true
                guard hasDomain || urlWithScheme.host == .localhost else { return nil }

                let isInvalidUserInfo = {
                    let hasUser = urlWithScheme.user != nil
                    let hasPassword = urlWithScheme.password != nil
                    let hasPath = !urlWithScheme.path.isEmpty
                    let hasPort = urlWithScheme.port != nil
                    let hasFragment = urlWithScheme.fragment != nil

                    return hasUser && !hasPassword && !hasPath && !hasPort && !hasFragment
                }()

                if isInvalidUserInfo {
                    return nil
                }

                self = urlWithScheme
                return

            } else if url.scheme != nil {
                self = url
                return

            } else if let hostname = s.split(separator: "/").first {
                guard hostname.contains(".") || String(hostname) == .localhost else {
                    // could be a local domain but user needs to use the protocol to specify that
                    return nil
                }
                if IPv4Address(String(hostname)) != nil {
                    // Require 4 octets specified explicitly for an IPv4 address (avoid 1.4 -> 1.0.0.4 expansion)
                    guard hostname.split(separator: ".").count == 4 else {
                        return nil
                    }
                }
            } else {
                return nil
            }

            s = NavigationalScheme.http.separated() + s
        }

        self.init(punycodeEncodedString: s)
    }
    // swiftlint:enable cyclomatic_complexity

    private init?(punycodeEncodedString: String) {
        var s = punycodeEncodedString
        let scheme: String

        let supportedSchemes = NavigationalScheme.punycodeEncodableSchemes
        if let navigationalScheme = supportedSchemes.first(where: { s.hasPrefix($0.separated()) }) {
            scheme = navigationalScheme.separated()
            s = s.dropping(prefix: scheme)
        } else if !s.contains(".") {
            return nil
        } else if s.hasPrefix("#") {
            return nil
        } else {
            scheme = URL.NavigationalScheme.http.separated()
        }

        guard let (authData, urlPart, query) = Self.fixupAndSplitURLString(s) else { return nil }

        let componentsWithoutQuery = urlPart.split(separator: "/").map(String.init)
        guard !componentsWithoutQuery.isEmpty else { return nil }

        let host = componentsWithoutQuery[0].punycodeEncodedHostname

        let encodedPath = componentsWithoutQuery
            .dropFirst()
            .map { $0.percentEncoded(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")

        let hostPathSeparator = !encodedPath.isEmpty || urlPart.hasSuffix("/") ? "/" : ""
        let trailingPathSeparator = !encodedPath.isEmpty && urlPart.hasSuffix("/") ? "/" : ""
        let url = scheme + (authData != nil ? String(authData!) + "@" : "") + host + hostPathSeparator + encodedPath + trailingPathSeparator + query

        self.init(string: url)
    }

    private static func fixupAndSplitURLString(_ s: String) -> (authData: String.SubSequence?, domainAndPath: String.SubSequence, query: String)? {
        let urlAndFragment = s.split(separator: "#", maxSplits: 1)
        guard !urlAndFragment.isEmpty else { return nil }

        let authDataAndUrl = urlAndFragment[0].split(separator: "@", maxSplits: 1)
        guard !authDataAndUrl.isEmpty else { return nil }

        let urlAndQuery = authDataAndUrl.last!.split(separator: "?", maxSplits: 1)

        guard let host = urlAndQuery.first?.split(separator: "/", maxSplits: 1).first,
              !host.contains(" ") else { return nil }

        var query = ""
        if urlAndQuery.count > 1 {
            // escape invalid characters with %20 in query values
            // keep already encoded characters and + sign in place
            query = "?" + urlAndQuery[1].split(separator: "&").map { component in
                component.split(separator: "=", maxSplits: 1).map { component -> String in
                    return component.percentEncoded(withAllowedCharacters: .urlQueryStringAllowed)
                }.joined(separator: "=")
            }.joined(separator: "&")
        } else if urlAndFragment[0].hasSuffix("?") {
            query = "?"
        }
        if urlAndFragment.count > 1 {
            query += "#" + urlAndFragment[1].percentEncoded(withAllowedCharacters: .urlQueryStringAllowed)
        } else if s.hasSuffix("#") {
            query += "#"
        }

        return (authData: authDataAndUrl.count > 1 && !authDataAndUrl[0].isEmpty ? authDataAndUrl[0] : nil,
                domainAndPath: urlAndQuery[0],
                query: query)
    }

    public func replacing(host: String?) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.host = host
        return components.url
    }

    public func replacing(path: String?) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.path = ""

        guard let url = components.url else { return self }

        if let path {
            return url.appendingPathComponent(path)
        } else {
            return url
        }
    }

    public func appending(_ path: String) -> URL {
        if #available(macOS 13.0, iOS 16.0, *) {
            return appending(path: path)
        } else {
            return appendingPathComponent(path)
        }
    }

    /// returns true if URLs are equal except the #fragment part
    public func isSameDocument(_ other: URL) -> Bool {
        self.absoluteString.droppingHashedSuffix() == other.absoluteString.droppingHashedSuffix()
    }

    /// Drops text fragment from a URL.
    ///
    /// The `#:~:text=` URL fragment is used to highlight text on a website.
    /// When a website fails to load, WebKit (and Safari) may drop that fragment
    /// from the URL. This function is here to support this case specifically.
    ///
    /// > The implementation matches only the `:~:` string even though it's not a valid
    /// text fragment, but manual testing shows that it's what WebKit already considers
    /// a text fragment and decides to drop on some occasions.
    public func removingTextFragment() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              components.fragment?.hasPrefix(":~:") == true
        else {
            return self
        }
        components.fragment = nil
        return components.url
    }

    // MARK: - HTTP/HTTPS

    public enum URLProtocol: String {
        case http
        case https

        public var scheme: String {
            return "\(rawValue)://"
        }
    }

    public func toHttps() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        guard components.scheme == URLProtocol.http.rawValue else { return self }
        components.scheme = URLProtocol.https.rawValue
        return components.url
    }

    public var isHttp: Bool {
        scheme == "http"
    }

    public var isHttps: Bool {
        scheme == "https"
    }

    // MARK: - Parameters

    @_disfavoredOverload // prefer ordered KeyValuePairs collection when `parameters` passed as a Dictionary literal to preserve order.
    public func appendingParameters<QueryParams: Collection>(_ parameters: QueryParams, allowedReservedCharacters: CharacterSet? = nil) -> URL
    where QueryParams.Element == (key: String, value: String) {
        let result = self.appending(percentEncodedQueryItems: parameters.map { name, value in
            URLQueryItem(percentEncodingName: name, value: value, withAllowedCharacters: allowedReservedCharacters)
        })
        return result
    }

    public func appendingParameters(_ parameters: KeyValuePairs<String, String>, allowedReservedCharacters: CharacterSet? = nil) -> URL {
        let result = self.appending(percentEncodedQueryItems: parameters.map { name, value in
            URLQueryItem(percentEncodingName: name, value: value, withAllowedCharacters: allowedReservedCharacters)
        })
        return result
    }

    public func appendingParameter(name: String, value: String, allowedReservedCharacters: CharacterSet? = nil) -> URL {
        let queryItem = URLQueryItem(percentEncodingName: name, value: value, withAllowedCharacters: allowedReservedCharacters)
        return self.appending(percentEncodedQueryItem: queryItem)
    }

    public func appending(percentEncodedQueryItem: URLQueryItem) -> URL {
        appending(percentEncodedQueryItems: [percentEncodedQueryItem])
    }

    public func appending(percentEncodedQueryItems: [URLQueryItem]) -> URL {
        guard !percentEncodedQueryItems.isEmpty,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }

        var existingPercentEncodedQueryItems = components.percentEncodedQueryItems ?? [URLQueryItem]()
        existingPercentEncodedQueryItems.append(contentsOf: percentEncodedQueryItems)
        components.percentEncodedQueryItems = existingPercentEncodedQueryItems
        let result = components.url ?? self

        return result
    }

    public func getQueryItems() -> [URLQueryItem]? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let encodedQuery = components.percentEncodedQuery
        else { return nil }
        components.percentEncodedQuery = encodedQuery.encodingPlusesAsSpaces()
        return components.queryItems ?? nil
    }

    public func getQueryItem(named name: String) -> URLQueryItem? {
        getQueryItems()?.first(where: { queryItem -> Bool in
            queryItem.name == name
        })
    }

    public func getParameter(named name: String) -> String? {
        getQueryItem(named: name)?.value
    }

    public func isThirdParty(to otherUrl: URL, tld: TLD) -> Bool {
        guard let thisHost = host else {
            return false
        }
        guard let otherHost = otherUrl.host else {
            return false
        }
        let thisRoot = tld.eTLDplus1(thisHost)
        let otherRoot = tld.eTLDplus1(otherHost)

        return thisRoot != otherRoot
    }

    public func removingParameters(named parametersToRemove: Set<String>) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }

        var percentEncodedQueryItems = components.percentEncodedQueryItems ?? [URLQueryItem]()
        percentEncodedQueryItems.removeAll { parametersToRemove.contains($0.name) }
        components.percentEncodedQueryItems = percentEncodedQueryItems

        return components.url ?? self
    }

    // MARK: Basic Auth username/password

    public var basicAuthCredential: URLCredential? {
        guard let navigationalScheme,
              NavigationalScheme.schemesWithRemovableBasicAuth.contains(navigationalScheme),
              let user = self.user?.removingPercentEncoding else { return nil }

        return URLCredential(user: user, password: self.password?.removingPercentEncoding ?? "", persistence: .forSession)
    }

    public func removingBasicAuthCredential() -> URL {
        guard let navigationalScheme,
              NavigationalScheme.schemesWithRemovableBasicAuth.contains(navigationalScheme),
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }

        components.user = nil
        components.password = nil

        return components.url ?? self
    }

    public var basicAuthProtectionSpace: URLProtectionSpace? {
        guard let host, let scheme else {
            return nil
        }
        return URLProtectionSpace(host: host,
                                  port: port ?? navigationalScheme?.defaultPort ?? 0,
                                  protocol: scheme,
                                  realm: nil,
                                  authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
    }

    public func matches(_ protectionSpace: URLProtectionSpace) -> Bool {
        return host == protectionSpace.host && (port ?? navigationalScheme?.defaultPort) == protectionSpace.port && scheme == protectionSpace.protocol
    }

    // MARK: Canonicalization
    public func canonicalHost(shouldRemoveWWW: Bool = false) -> String? {
        // Step 1: Extract hostname portion from the URL
        guard var canonicalHost = self.host else {
            return nil
        }

        // Step 2: Decode any %XX escapes present in the hostname
        if let decodedHost = canonicalHost.removingPercentEncoding {
            canonicalHost = decodedHost
        }

        // Step 3: Discard any characters outside the range 0x20 to 0x7E
        canonicalHost = canonicalHost.filter { character in
            let asciiValue = character.unicodeScalars.first?.value ?? 0
            return (asciiValue >= 0x20 && asciiValue <= 0x7E)
        }

        // Step 4: Discard any leading and/or trailing full-stops
        canonicalHost = canonicalHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Step 5: Replace sequences of two or more full-stops with a single full-stop
        canonicalHost = canonicalHost.replacingOccurrences(of: "\\.+", with: ".", options: .regularExpression)

        // Step 6: If the hostname is a numeric IPv4 address then reduce it to the canonical dotted quad form
        let ipv4AddressComponents = canonicalHost.components(separatedBy: ".")
        if ipv4AddressComponents.count == 4, ipv4AddressComponents.allSatisfy({ Int($0) != nil }) {
            canonicalHost = ipv4AddressComponents.joined(separator: ".")
        }

        // Step 7: Replace any characters other than letters, numbers, ".", and "-" with "%XX" escape codes, using lowercase hexadecimal digits
        canonicalHost = canonicalHost.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""

        // Step 8: Strip www. prefix (if present)
        if shouldRemoveWWW {
            canonicalHost = canonicalHost.droppingWwwPrefix()
        }

        // Step 9: If more than six components in the resulting hostname, discard all but the rightmost six components
        let components = canonicalHost.components(separatedBy: ".").suffix(6)
        canonicalHost = components.joined(separator: ".")

        return canonicalHost
     }

    public func canonicalURL(shouldRemoveWWW: Bool = false) -> URL? {
        // Step 1: Remove tab (0x09), CR (0x0d), and LF (0x0a) characters
        var urlString = self.absoluteString.filter { $0 != "\t" && $0 != "\r" && $0 != "\n" }

        // Step 2: Remove the fragment
        if let fragmentRange = urlString.range(of: "#") {
            urlString.removeSubrange(fragmentRange.lowerBound..<urlString.endIndex)
        }

        // Step 3: Repeatedly percent-unescape the URL until it has no more percent-escapes
        urlString = urlString.fullyRemovingPercentEncoding()

        // Step 4: Remove all trailing slashes, but keep the single slash after the domain
        if let url = URL(string: urlString), url.path == "/" {
            // Do not remove the single trailing slash if it's just the domain
        } else {
            while urlString.last == "/" {
                urlString.removeLast()
            }
        }

        // Step 5: Remove all occurrences of more than one "/", but not in the protocol part
        if let range = urlString.range(of: "://") {
            let protocolPart = urlString[..<range.upperBound]
            let restOfURL = urlString[range.upperBound...]
            urlString = protocolPart + restOfURL.replacingOccurrences(of: "/+", with: "/", options: .regularExpression)
        }

        // Step 6: Remove all occurrences of "/./" in the path
        urlString = urlString.replacingOccurrences(of: "/./", with: "/")

        // Step 7: Remove all occurrences of "/../" in the path
        while let range = urlString.range(of: "/../") {
            let previousComponentRange = urlString.range(of: "/", options: .backwards, range: urlString.startIndex..<range.lowerBound)
            if let previousComponentRange = previousComponentRange {
                urlString.removeSubrange(previousComponentRange.upperBound..<range.upperBound)
            } else {
                break
            }
        }

        // Step 8: Lowercase everything
        urlString = urlString.lowercased()

        // Step 9: Remove "www." from the host component
        if shouldRemoveWWW, let tempURL = URL(string: urlString) {
            if let urlWithoutWWW = tempURL.removingWWWFromHost() {
                urlString = urlWithoutWWW.absoluteString
            }
        }

        // Validate the URL according to RFC 2396
        guard let validURL = URL(string: urlString), validURL.path.count > 0 else {
            return nil
        }

        return validURL
    }

    public func removingWWWFromHost() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let host = components.host,
              host.hasPrefix("www.") else {
            return self
        }

        components.host = host.droppingWwwPrefix()
        return components.url
    }

}

public extension CharacterSet {

    /**
     * As per [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986#section-2.2).
     *
     * This set contains all reserved characters that are otherwise
     * included in `CharacterSet.urlQueryAllowed` but still need to be percent-escaped.
     */
    static let urlQueryReserved = CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=")

    static let urlQueryParameterAllowed = CharacterSet.urlQueryAllowed.subtracting(Self.urlQueryReserved)
    static let urlQueryStringAllowed = CharacterSet(charactersIn: "%+?").union(.urlQueryParameterAllowed)

}

public extension URLQueryItem {

    init(percentEncodingName name: String, value: String, withAllowedCharacters allowedReservedCharacters: CharacterSet? = nil) {
        let allowedCharacters: CharacterSet = {
            if let allowedReservedCharacters = allowedReservedCharacters {
                return .urlQueryParameterAllowed.union(allowedReservedCharacters)
            }
            return .urlQueryParameterAllowed
        }()

        let percentEncodedName = name.percentEncoded(withAllowedCharacters: allowedCharacters)
        let percentEncodedValue = value.percentEncoded(withAllowedCharacters: allowedCharacters)

        self.init(name: percentEncodedName, value: percentEncodedValue)
    }

}
