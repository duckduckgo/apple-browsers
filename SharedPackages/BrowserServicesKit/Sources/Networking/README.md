#  Networking

This is the preferred Networking library for iOS and macOS DuckDuckGo apps.
If the library lacks the required features, please improve it. 

## v2

### Usage

#### Configuration:
```
let request = APIRequestV2(url: HTTPURLResponse.testUrl,
                           method: .post,
                           queryItems: ["Query,Item1%Name": "Query,Item1%Value"],
                           headers: APIRequestV2.HeadersV2(userAgent: "UserAgent"),
                           body: Data(),
                           timeoutInterval: TimeInterval(20),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                           responseConstraints: [.allowHTTPNotModified,
                                                 .requireETagHeader,
                                                 .requireUserAgent],
                           allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))
let apiService = DefaultAPIService(urlSession: URLSession.shared)
```

#### Fetching

The library provides a primary function for fetching requests:

**Raw Response Fetching**: This function returns an `APIResponseV2`, which is a tuple containing the raw data and the HTTP response.
   
   ```swift
   let result = try await apiService.fetch(request: request)
   ```
   
   The `APIResponseV2` is defined as:
   
   ```swift
   typealias APIResponseV2 = (data: Data?, httpResponse: HTTPURLResponse)
   ```

**Response body decoding**: `APIResponseV2` provides a utility function for decoding the request body `Data` in the inferred `Decodable` type.

```
let response = try await apiService.fetch(request: request.apiRequest)
let decodedModel: MyDecodableModelType = try response.decodeBody()
```


**Concurrency Considerations**: This library is designed to be agnostic concerning concurrency models. It maintains a stateless architecture, and the URLSession instance is injected by the user, thereby delegating all concurrency management decisions to the user. The library facilitates task cancellation by frequently invoking `try Task.checkCancellation()`, ensuring responsive and cooperative cancellation handling.

### Mock

The `MockPIService` implementing `APIService` can be found in `BSK/TestUtils`

```
let apiResponse = (Data(), HTTPURLResponse(url: HTTPURLResponse.testUrl,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: nil)!)
let mockedAPIService = MockAPIService(apiResponse: Result.success(apiResponse))
```

## v1 (Legacy)

Not to be used. All V1 public functions have been deprecated and maintained only for backward compatibility.
