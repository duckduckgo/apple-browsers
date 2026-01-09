# Auth

## Overview

A Swift framework implementing a subset of OAuth 2.0 authentication for DuckDuckGo's Privacy Pro services on macOS and iOS. This library handles user authentication, token management, and secure communication with DuckDuckGo's authentication services.

[Overview of OAuth2 Implementation for Privacy Pro](https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#overview-of-oauth2-implementation-for-privacy-pro)

## Main Components

### TokenContainer
The structure that holds authentication token, the refresh token, and their decoded representations:

```swift
public struct TokenContainer: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let decodedAccessToken: JWTAccessToken
    public let decodedRefreshToken: JWTRefreshToken
}
```

**Warnings:**
- Never store or cache a TokenContainer outside this framework.
- Never pass the TokenContainer around, always ask the `OAuthClient` for it, use it and discard it. (Notable exception is IPC coms for the VPN SysExt)

**IPC Support:**
For IPC communication (e.g., VPN System Extension), `TokenContainer` provides convenience methods:
- `data: NSData?` - Encodes the container to NSData for IPC transmission
- `init(with data: NSData)` - Decodes a container from NSData received via IPC

### OAuthClient
The **main** interface for client applications to interact with the authentication system and the **only** source of truth for the authentication token. 

**Important:** `DefaultOAuthClient` is implemented as a Swift `actor`, which means:
- All method calls must be `await`ed
- The client provides thread-safe access to token storage
- Concurrent token refresh requests are automatically deduplicated

Key features include:
- Token management and refresh
- Account creation and activation
- Logout functionality
- Token refresh event tracking

### OAuthService
Handles the low-level communication with the authentication server, implementing the OAuth 2.0 protocol:
- Authorization code flow
- Token exchange
- Token refresh
- JWT verification

### OAuthRequest
Defines all API endpoints and request structures for the authentication service:
- Authorization
- Account creation
- Token management
- Account management
- Logout

## Key Features

- **Secure Token Management**: Automatic token refresh and secure storage
- **JWT Verification**: Built-in JWT verification using server-provided keys
- **Error Handling**: Comprehensive error handling with detailed error messages
- **Environment Support**: Support for both production and staging environments
- **Concurrent Safety**: Actor-based implementation ensures thread-safe token operations
- **Refresh Deduplication**: Multiple concurrent refresh requests share the same refresh task

## Usage

### Basic Authentication Flow

1. Initialise the OAuthClient with appropriate storage and service implementations.
2. Use the client to create or activate an account.
3. Use the stored tokens for authenticated requests via `getTokens(policy:)`.

### Example

```swift
// Initialise the client
let authService = DefaultOAuthService(baseURL: <API base URL>, apiService: <Your APIService>)
let refreshEventMapping: EventMapping<OAuthClientRefreshEvent>? = <Your event mapping or nil>
let oAuthClient = DefaultOAuthClient(
    tokensStorage: yourTokenStorage,
    authService: authService,
    refreshEventMapping: refreshEventMapping
)

// Create a new account (if needed)
let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)

// Or activate with platform signature (e.g., App Store receipt)
let tokenContainer = try await oAuthClient.activate(withPlatformSignature: signature)

// Use the tokens for authenticated requests
let validTokens = try await oAuthClient.getTokens(policy: .localValid)
```

**Warning:**

The `APIService` must disable automatic redirection because in our specific OAuth implementation, we manage the redirection, not the user.
This is done using our custom `SessionDelegate` as `URLSession` delegate.

```swift
public static func makeAPIServiceForAuthV2() -> APIService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    let urlSession = URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
    return DefaultAPIService(urlSession: urlSession)
}
```

## Token Management

The framework provides several token retrieval policies:

- `.local`: Use stored tokens as-is, throws `missingTokenContainer` if no token exists
- `.localValid`: Use stored tokens, automatically refreshes if expired or expiring soon (within 45 seconds)
- `.localForceRefresh`: Force refresh of stored tokens, throws `missingTokenContainer` if no refresh token exists
- `.createIfNeeded`: Like `.localValid`, but creates a new account if no token exists

**Token Refresh Behavior:**
- Tokens are automatically refreshed if they expire within 45 seconds (configurable via `tokenExpiryBufferInterval`)
- Multiple concurrent refresh requests share the same refresh task to avoid redundant network calls
- Refresh operations emit events via `OAuthClientRefreshEvent` if `refreshEventMapping` is provided

## Public API Methods

### Token Retrieval
- `getTokens(policy: AuthTokensCachePolicy) async throws -> TokenContainer` - Get tokens based on policy
- `currentTokenContainer() throws -> TokenContainer?` - Get current stored tokens without refresh
- `setCurrentTokenContainer(_ tokenContainer: TokenContainer?) throws` - Manually set tokens (use with caution)
- `isUserAuthenticated: Bool` - Check if user has stored tokens

### Account Management
- `activate(withPlatformSignature signature: String) async throws -> TokenContainer` - Activate account with platform signature (e.g., App Store receipt)
- `adopt(tokenContainer: TokenContainer) throws` - Adopt an externally-provided token container

### Token Operations
- `decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer` - Decode and verify tokens, returns a TokenContainer

### Logout
- `logout() async throws` - Invalidate tokens server-side and remove local storage
- `removeLocalAccount() throws` - Remove tokens from local storage only (does not invalidate server-side)

## Error Handling

The framework provides detailed error handling through `OAuthServiceError` and `OAuthClientError`:

```swift
public enum OAuthClientError: DDGError {
    case internalError(String)
    case missingTokenContainer
    case unauthenticated
    case invalidTokenRequest
    case unknownAccount
}
```

**Notable errors:**
- `missingTokenContainer`: No tokens are stored locally. Use `.createIfNeeded` policy or call `activate(withPlatformSignature:)` to create an account.
- `invalidTokenRequest`: The refresh token is invalid or has been revoked. User must re-authenticate.
- `unknownAccount`: The account associated with the refresh token no longer exists. User must create a new account.
- `unauthenticated`: The account is not authenticated. User must re-authenticate.

## Refresh Event System

The framework provides an optional refresh event system for monitoring token refresh operations:

```swift
public enum OAuthClientRefreshEvent {
    case tokenRefreshStarted(refreshID: String)
    case tokenRefreshRefreshingAccessToken(refreshID: String)
    case tokenRefreshRefreshedAccessToken(refreshID: String)
    case tokenRefreshFetchingJWKS(refreshID: String)
    case tokenRefreshFetchedJWKS(refreshID: String)
    case tokenRefreshVerifyingAccessToken(refreshID: String)
    case tokenRefreshVerifyingRefreshToken(refreshID: String)
    case tokenRefreshSavingTokens(refreshID: String)
    case tokenRefreshSucceeded(refreshID: String)
    case tokenRefreshFailed(refreshID: String, error: Error)
}
```

Each refresh operation is assigned a unique `refreshID` (UUID) that can be used to track the refresh lifecycle. Pass an `EventMapping<OAuthClientRefreshEvent>` to the initializer to receive these events, or `nil` to disable event tracking.

## Security and other considerations

- Secure token storage is not the responsibility of this framework and is provided by dependency injection of objects implementing `AuthTokenStoring`.
- JWT verification uses server-provided public keys fetched from `/api/auth/v2/.well-known/jwks.json`.
- The token is automatically refreshed if requested less than 45 seconds before expiration (configurable via `tokenExpiryBufferInterval`).
- On logout, the token is invalidated server-side and removed from local storage.
- Token durations:
    - Access Token: 4 hours (4 minutes in Staging)
    - Refresh Token: 30 days
- The client is implemented as a Swift `actor` for thread-safe access to token storage.
- Concurrent refresh requests are automatically deduplicated - multiple calls to refresh will share the same refresh task.

## Testing and mocks

The `NetworkTestingUtils` Swift package contains all needed mocks, factories and utilities needed for testing the Auth code itself and code that uses the AuthV2 authentication.

- `OAuthTokensFactory` creates different type of `TokenContainer` in different states of expiration.
- `MockURLProtocol` can be used for isolating the code from the real API and run integration tests  
- `HTTPURLResponseExtension` provides pre-configured `HTTPURLResponse` responses like `HTTPURLResponse.ok` or `HTTPURLResponse.internalServerError`

All mocks are completely independent and configurable with errors or successful responses for each function

## Additional Documentation
- [OAuth 2.0 protocol](https://auth0.com/intro-to-iam/what-is-oauth-2)
- [Auth API V2 Documentation](https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md)
- [Original Task with Tech Designs](https://app.asana.com/1/137249556945/project/72649045549333/task/1207591586576970?focus=true)
