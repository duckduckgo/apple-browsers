# AuthV2

A Swift framework implementing OAuth 2.0 authentication for DuckDuckGo's Privacy Pro services on macOS and iOS. This library handles user authentication, token management, and secure communication with DuckDuckGo's authentication services.

## Overview

The AuthV2 framework provides a complete implementation of OAuth 2.0 authentication flow, specifically designed for DuckDuckGo's Privacy Pro services. It handles token management, secure storage, and automatic token refresh, while providing a clean API for client applications.

## Main Components

### TokenContainer
The core data structure that holds authentication tokens and their decoded representations:

```swift
public struct TokenContainer: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let decodedAccessToken: JWTAccessToken
    public let decodedRefreshToken: JWTRefreshToken
}
```

### OAuthClient
The main interface for client applications to interact with the authentication system. Key features include:
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
- **Token Migration**: Support for migrating from Auth V1 to V2
- **Environment Support**: Support for both production and staging environments

## Usage

### Basic Authentication Flow

1. Initialize the OAuthClient with appropriate storage and service implementations
2. Use the client to create or activate an account
3. Store the returned TokenContainer for future use
4. Use the stored tokens for authenticated requests

### Example

```swift
// Initialize the client
let oAuthClient = DefaultOAuthClient(
    tokensStorage: yourTokenStorage,
    legacyTokenStorage: yourLegacyStorage,
    authService: DefaultOAuthService(baseURL: environment.url, apiService: yourAPIService)
)

// Create a new account
let tokenContainer = try await oAuthClient.createAccount()

// Use the tokens for authenticated requests
let validTokens = try await oAuthClient.getTokens(policy: .localValid)
```

## Token Management

The framework provides several token management policies:

- `.local`: Use stored tokens as-is
- `.localValid`: Use stored tokens, refresh if needed
- `.localForceRefresh`: Force refresh of stored tokens
- `.createIfNeeded`: Create new tokens if none exist

## Error Handling

The framework provides detailed error handling through `OAuthServiceError` and `OAuthClientError`:

```swift
public enum OAuthClientError: Error {
    case internalError(String)
    case missingTokens
    case missingRefreshToken
    case unauthenticated
    case refreshTokenExpired
    case invalidTokenRequest
    case authMigrationNotPerformed
}
```

## Auth V1 to V2 Migration

The framework provides automatic migration from Auth V1 to V2 tokens. When initializing the `DefaultOAuthClient` with a `legacyTokenStorage` that contains a V1 token, the migration process will:

1. Check if a V2 token already exists
2. If no V2 token exists, attempt to exchange the V1 token for a V2 token container
3. Store the new V2 token container while preserving the V1 token for potential rollback. This ensures a smooth transition while maintaining backward compatibility.
4. Use the V2 token container for all subsequent operations

Note: A log out will remove both v1 and v2 tokens

## Security Considerations

- Secure tokens storage is not responsibility of this framework and is provided by dependency injection of objects implementing `AuthTokenStoring` and `LegacyAuthTokenStoring`
- JWT verification uses server-provided public keys
- Automatic token refresh before expiration
- Support for token invalidation and logout

## Additional Documentation
- [OAuth 2.0 protocol](https://auth0.com/intro-to-iam/what-is-oauth-2)
- [Auth API V2 Documentation](https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md)
- [Original Task with Tech Designs](https://app.asana.com/1/137249556945/project/72649045549333/task/1207591586576970?focus=true)