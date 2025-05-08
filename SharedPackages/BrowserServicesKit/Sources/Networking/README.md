#  Networking

This is the preferred Networking library for iOS and macOS DuckDuckGo apps.
If the library lacks the required features, please improve it.

## v2

### Configuration:

```swift
// Initialize API service with optional auth refresh callback

let configuration = URLSessionConfiguration.ephemeral
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
configuration.httpCookieStorage = nil
let urlSession = URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
let apiService = DefaultAPIService(urlSession: urlSession
                                   authorizationRefresherCallback: { request in
                                        // Refresh and return new token
                                        return "new_token"
                                   })
```

### API request creation

Create an `APIRequestV2`
```swift
let request = APIRequestV2(url: url,
                          method: .post,
                          queryItems: ["param1": "value1"],
                          headers: APIRequestV2.HeadersV2(
                              userAgent: "UserAgent",
                              contentType: .json,
                              authToken: "token"
                          ),
                          body: jsonData,
                          timeoutInterval: 20.0,
                          retryPolicy: APIRequestV2.RetryPolicy(maxRetries: 3, delay: .exponential(baseDelay: 2.0)),
                          responseConstraints: [.requireETagHeader, .allowHTTPNotModified])
```

#### Headers
The library supports various content types and header configurations:
```swift
let headers = APIRequestV2.HeadersV2(
    userAgent: "UserAgent",
    etag: "etag-value",
    cookies: [/* HTTPCookie array */],
    authToken: "Bearer token",
    contentType: .json,  // Supports multiple types: json, xml, formURLEncoded, etc.
    additionalHeaders: ["Custom-Header": "Value"]
)
```

#### Retry Policies

The library supports three types of retry policies for network errors (not API errors like 4xx or 5xx).

```swift
// Fixed
let fixedPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .fixed(2.0))

// Exponential
let exponentialPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .exponential(baseDelay: 2.0))

// Jitter
let jitterPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .jitter(backoff: 8.0))
```

#### Response Constraints
You can enforce specific requirements for responses:
```swift
let constraints: [APIResponseConstraints] = [
    .requireETagHeader,        // Requires ETag header in response
    .allowHTTPNotModified,     // Allows 304 Not Modified responses (otherwise throws error)
    .requireUserAgent          // Requires User-Agent in response header
]
```

#### Fetching

The library provides functions for fetching requests:

**Raw Response Fetching**: Returns an `APIResponseV2` containing the raw data and HTTP response.

```swift
let response: APIResponseV2 = try await apiService.fetch(request: request)
```

**Response Decoding**: Automatically decode the response body into a `Decodable` type:

```swift
let response = try await apiService.fetch(request: request)
let model: MyDecodableType = try response.decodeBody()

// Custom decoder configuration
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601 // Example: Customize date decoding
let model: MyDecodableType = try response.decodeBody(decoder: decoder)
```

### Authentication 

[Authentication V2 (AuthV2) documentation can be found here.](Auth/README.md)

`OAuthClient` supports automatic token refresh when receiving 401 Unauthorized responses, provided the request was initially authenticated (`authToken` was set in `HeadersV2`):
```swift
apiService.authorizationRefresherCallback = { request in
    // Logic to refresh authentication token
    let newAuthToken = try await refreshToken()
    // Return the new token as a String
    return newAuthToken
}
```

### Concurrency Considerations
This library is designed to be agnostic concerning concurrency models. It maintains a stateless architecture, and the `URLSession` instance is injected by the user, thereby delegating all concurrency management decisions to the user. The library facilitates task cancellation by frequently invoking `try Task.checkCancellation()`, ensuring responsive and cooperative cancellation handling.

### Mock

The `MockAPIService` implementing `APIService` can be found in `NetworkingTestingUtils`

```swift
let mockData = Data("{}".utf8)
let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!,
                                   statusCode: 200,
                                   httpVersion: nil,
                                   headerFields: ["ETag": "some-etag"])!
let mockAPIResponse = APIResponseV2(data: mockData, httpResponse: mockResponse)
let mockedAPIService = MockAPIService(apiResponse: .success(mockAPIResponse))

// Example usage with mock service
let myDecodedObject: MyDecodableType = try await mockedAPIService.fetch(request: someRequest).decodeBody()
```

## v1 (Legacy)

Not to be used. All V1 public functions have been deprecated and maintained only for backward compatibility.
