//
//  HTTPHeaderKey.swift
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

public struct HTTPHeaderKey {

    // Common HTTP header keys
    public static let accept = "Accept"
    public static let acceptCharset = "Accept-Charset"
    public static let acceptEncoding = "Accept-Encoding"
    public static let acceptLanguage = "Accept-Language"
    public static let acceptRanges = "Accept-Ranges"
    public static let accessControlAllowCredentials = "Access-Control-Allow-Credentials"
    public static let accessControlAllowHeaders = "Access-Control-Allow-Headers"
    public static let accessControlAllowMethods = "Access-Control-Allow-Methods"
    public static let accessControlAllowOrigin = "Access-Control-Allow-Origin"
    public static let accessControlExposeHeaders = "Access-Control-Expose-Headers"
    public static let accessControlMaxAge = "Access-Control-Max-Age"
    public static let accessControlRequestHeaders = "Access-Control-Request-Headers"
    public static let accessControlRequestMethod = "Access-Control-Request-Method"
    public static let age = "Age"
    public static let allow = "Allow"
    public static let authorization = "Authorization"
    public static let cacheControl = "Cache-Control"
    public static let connection = "Connection"
    public static let contentDisposition = "Content-Disposition"
    public static let contentEncoding = "Content-Encoding"
    public static let contentLanguage = "Content-Language"
    public static let contentLength = "Content-Length"
    public static let contentLocation = "Content-Location"
    public static let contentRange = "Content-Range"
    public static let contentSecurityPolicy = "Content-Security-Policy"
    public static let contentType = "Content-Type"
    public static let cookie = "Cookie"
    public static let date = "Date"
    public static let etag = "ETag"
    public static let expect = "Expect"
    public static let expires = "Expires"
    public static let from = "From"
    public static let host = "Host"
    public static let ifMatch = "If-Match"
    public static let ifModifiedSince = "If-Modified-Since"
    public static let ifNoneMatch = "If-None-Match"
    public static let ifRange = "If-Range"
    public static let ifUnmodifiedSince = "If-Unmodified-Since"
    public static let lastModified = "Last-Modified"
    public static let link = "Link"
    public static let location = "Location"
    public static let maxForwards = "Max-Forwards"
    public static let origin = "Origin"
    public static let pragma = "Pragma"
    public static let proxyAuthenticate = "Proxy-Authenticate"
    public static let proxyAuthorization = "Proxy-Authorization"
    public static let range = "Range"
    public static let referer = "Referer"
    public static let retryAfter = "Retry-After"
    public static let server = "Server"
    public static let setCookie = "Set-Cookie"
    public static let strictTransportSecurity = "Strict-Transport-Security"
    public static let te = "TE"
    public static let trailer = "Trailer"
    public static let transferEncoding = "Transfer-Encoding"
    public static let upgrade = "Upgrade"
    public static let userAgent = "User-Agent"
    public static let vary = "Vary"
    public static let via = "Via"
    public static let warning = "Warning"
    public static let wwwAuthenticate = "WWW-Authenticate"
    public static let authToken = "X-Auth-Token"
    public static let xContentTypeOptions = "X-Content-Type-Options"
    public static let xFrameOptions = "X-Frame-Options"
    public static let xPoweredBy = "X-Powered-By"
    public static let xRequestedWith = "X-Requested-With"
    public static let xXSSProtection = "X-XSS-Protection"

    // DuckDuckGo specific HTTP header keys
    public static let moreInfo = "X-DuckDuckGo-MoreInfo"
}
