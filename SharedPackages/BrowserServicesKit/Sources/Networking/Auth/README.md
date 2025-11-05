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

### OAuthClient
The **main** interface for client applications to interact with the authentication system and the **only** source of truth for the authentication token. 

Key features include:
- Token management and refresh
- Account creation and activation
- Token migration from V1 to V2
- Logout functionality

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
- **Token Migration**: Support for migrating from Auth V1 to V2.
- **Environment Support**: Support for both production and staging environments.

## Usage

### Basic Authentication Flow

1. Initialise the OAuthClient with appropriate storage and service implementations.
2. Use the client to create or activate an account.
3. Store the returned TokenContainer for future use.
4. Use the stored tokens for authenticated requests.

### Example

```swift
// Initialise the client
let authService = DefaultOAuthService(baseURL: <API base URL>, apiService: <Your APIService>)
let oAuthClient = DefaultOAuthClient(
    tokensStorage: yourTokenStorage,
    legacyTokenStorage: yourLegacyStorage,
    authService: authService)
)

// Create a new account
let tokenContainer = try await oAuthClient.createAccount()

// Use the tokens for authenticated requests
let validTokens = try await oAuthClient.getTokens(policy: .localValid)
```

**Warning:**

The `APIService` must disable automatic redirection because in our specific OAuth implementation, we manage the redirection, not the user.
This is done using our custom `SessionDelegate` as `URLSession` delegate.

```
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

- `.local`: Use stored tokens as-is
- `.localValid`: Use stored tokens, refresh if needed
- `.localForceRefresh`: Force refresh of stored tokens
- `.createIfNeeded`: Create new tokens if none exist

## Error Handling

The framework provides detailed error handling through `OAuthServiceError` and `OAuthClientError`:

```swift
public enum OAuthClientError: DDGError {
    case internalError(String)
    case missingTokens
    case missingRefreshToken
    case unauthenticated
    case refreshTokenExpired
    case invalidTokenRequest
    case authMigrationNotPerformed
}
```

**Notable errors:**

- `refreshTokenExpired` is generally bad news, that means the account is become unusable, the token can't be refreshed and the user must be logged out.
- `authMigrationNotPerformed` is not really an error, just a state for when a migration is attempted but is not needed.

## Auth V1 to V2 Migration

The framework provides automatic migration from Auth V1 to V2 tokens. When initializing the `DefaultOAuthClient` with a `legacyTokenStorage` that contains a V1 token, the migration process will:

1. Check if a V2 token already exists
2. If no V2 token exists, attempt to exchange the V1 token for a V2 token container.
3. Store the new V2 token container while preserving the V1 token for potential rollback. This ensures a smooth transition while maintaining backward compatibility.
4. Use the V2 token container for all subsequent operations.

Note: A log out will remove both V1 and V2 tokens.

## Security and other considerations

- Secure token storage is not the responsibility of this framework and is provided by dependency injection of objects implementing `AuthTokenStoring` and `LegacyAuthTokenStoring`.
- JWT verification uses server-provided public keys.
- The token is automatically refreshed if requested less than 45s before expiration.
- On logout the token is invalidated server side.
- Tokens durations
    - Access Token: 4h (4m in Staging)
    - Refresh token: 1M
    
    
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
