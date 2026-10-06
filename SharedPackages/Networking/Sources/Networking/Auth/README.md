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

## Token Container Lifecycle

Understanding the lifecycle of a `TokenContainer` helps clarify when and how tokens are created, refreshed, and invalidated.

### 1. Creation

A `TokenContainer` is created in one of two ways:

**Account Creation:**
- User initiates account creation via `getTokens(policy: .createIfNeeded)` or `activate(withPlatformSignature:)`
- OAuth authorization flow generates authorization code
- Authorization code is exchanged for access token and refresh token
- Both tokens are decoded and verified using server-provided JWKS keys
- `TokenContainer` is created with both tokens and their decoded representations
- Container is stored in `AuthTokenStoring` implementation (typically Keychain)

**Account Activation:**
- User activates existing account with platform signature (e.g., App Store receipt)
- Similar flow to creation, but uses login endpoint instead of create endpoint
- New `TokenContainer` is created and stored

### 2. Storage

- `TokenContainer` is persisted via `AuthTokenStoring` (injected dependency)
- Storage is typically Keychain-based for security
- Both access token and refresh token are stored together
- Decoded token representations are also stored (for quick expiry checks without re-decoding)

### 3. Usage

- Applications request tokens via `getTokens(policy:)` with appropriate policy
- `.localValid` policy automatically checks expiry and refreshes if needed
- Access token is used for authenticated API requests
- Refresh token remains stored and is only used for token refresh operations

### 4. Refresh

When access token expires or is about to expire (within 45 seconds):

1. **Detection**: `getTokens(policy: .localValid)` detects expiry from decoded token
2. **Deduplication**: If refresh already in progress, concurrent requests await same task
3. **Refresh Request**: Refresh token is sent to server to obtain new access token
4. **JWKS Fetch**: Server's public keys are fetched for token verification
5. **Verification**: Both new access token and refresh token are verified using JWKS
6. **Storage**: New `TokenContainer` replaces old one in storage
7. **Return**: New container is returned to caller

**Important**: The refresh token may also be rotated (new refresh token issued), so the entire `TokenContainer` is replaced, not just the access token.

### 5. Expiration

**Access Token Expiration:**
- Access tokens expire after 4 hours (4 minutes in Staging)
- Expired access tokens cannot be used for API requests
- Framework automatically refreshes before expiration (45-second buffer)
- If refresh fails, user must re-authenticate

**Refresh Token Expiration:**
- Refresh tokens expire after 30 days
- Once expired, cannot be used to obtain new access tokens
- User must create new account or re-authenticate
- Expired refresh token results in `invalidTokenRequest` or `unknownAccount` error

### 6. Invalidation

Tokens can be invalidated in two ways:

**Logout (`logout()`):**
- Access token is invalidated server-side via logout API
- `TokenContainer` is removed from local storage
- User must create new account or activate existing account to continue

**Local Removal (`removeLocalAccount()`):**
- `TokenContainer` is removed from local storage only
- Server-side token remains valid (can be security risk if token is compromised)
- Typically used for local cleanup without server invalidation

### 7. Error Recovery

When token operations fail:

- **`missingTokenContainer`**: No tokens stored → Create new account or activate
- **`invalidTokenRequest`**: Refresh token invalid → User must re-authenticate
- **`unknownAccount`**: Account no longer exists → User must create new account
- **`unauthenticated`**: Authentication state lost → User must re-authenticate

### Lifecycle Summary

```
Creation → Storage → Usage → [Refresh Loop] → Expiration/Invalidation
   ↓         ↓         ↓            ↓                    ↓
OAuth     Keychain   API      Auto-refresh        Logout/Remove
Flow      Storage    Calls    (every 4h)          or Expiry
```

**Key Points:**
- Tokens are ephemeral - access tokens last 4 hours, refresh tokens 30 days
- Framework handles refresh automatically when using `.localValid` policy
- Storage is abstracted via `AuthTokenStoring` protocol
- Server-side invalidation requires explicit `logout()` call
- Failed refresh requires user re-authentication

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
