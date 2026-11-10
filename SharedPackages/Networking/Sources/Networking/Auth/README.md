# Auth

A Swift implementation of the subset of OAuth 2.0 that DuckDuckGo's subscription (Privacy Pro) uses on iOS and macOS. It creates and activates accounts, stores and refreshes the token pair, keeps a backup pair that can restore a lost session, and talks to the Auth API v2.

[Overview of OAuth2 Implementation for Privacy Pro](https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#overview-of-oauth2-implementation-for-privacy-pro)

## Contents

- [Main components](#main-components)
- [Usage](#usage)
- [Token retrieval policies](#token-retrieval-policies)
- [Token container lifecycle](#token-container-lifecycle)
  - [Creation](#creation)
  - [Storage](#storage)
  - [Refresh](#refresh)
  - [Expiration](#expiration)
  - [Sign-out and local removal](#sign-out-and-local-removal)
- [Backup token](#backup-token)
  - [Renewal](#renewal)
  - [Restore](#restore)
  - [Sign-out cut-off](#sign-out-cut-off)
  - [When the backup is deleted](#when-the-backup-is-deleted)
  - [The authBackupToken flag](#the-authbackuptoken-flag)
- [Sessions and concurrency](#sessions-and-concurrency)
- [Error handling](#error-handling)
  - [How the Auth API's responses are read](#how-the-auth-apis-responses-are-read)
  - [Errors](#errors)
  - [Classifying a failed restore](#classifying-a-failed-restore)
- [Events](#events)
- [How the apps use it](#how-the-apps-use-it)
- [Public API](#public-api)
- [Security and other considerations](#security-and-other-considerations)
- [Testing and mocks](#testing-and-mocks)
- [Additional documentation](#additional-documentation)

## Main components

| Type | Role |
|---|---|
| `TokenContainer` | The access token, the refresh token and their decoded JWT payloads. |
| `OAuthClient` / `DefaultOAuthClient` | The interface the apps use, and the only source of truth for the current token. Owns storage, refresh, account creation, sign-out and the backup. |
| `TokenRefreshing` / `DefaultTokenRefresher` | Spends a refresh token for a new pair (`refresh`), spends it several times for independent pairs (`fork`), and verifies tokens (`decode`). Never touches storage. |
| `TokenBackupStore` | Internal. Reads and writes the backup, decides when it needs renewal, validates it before a restore, and keeps the sign-out cut-off. |
| `OAuthService` / `DefaultOAuthService` | Sends the Auth API requests and turns their responses into values or errors. |
| `OAuthRequest` | Builds each Auth API request and declares which status codes are success and which carry a decodable error body. |
| `AuthTokenStoring` | Where a token container is kept. Injected; the apps use the keychain. |
| `BackupRestoreFailure` | Classifies a failed restore as temporary, permanent or unknown, so callers can decide whether to retry. |

### TokenContainer

```swift
public struct TokenContainer: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let decodedAccessToken: JWTAccessToken
    public let decodedRefreshToken: JWTRefreshToken
}
```

- Two containers are equal when their encoded access and refresh tokens are equal.
- `decodedAccessToken.externalID` identifies the account; the backup code uses it to tell accounts apart.
- `decodedRefreshToken.issuedAtDate` and `expirationDate` drive backup renewal, the sign-out cut-off and the iOS background refresh.
- For IPC, such as handing the token to the macOS VPN system extension, `data: NSData?` encodes the container and `init(with: NSData)` decodes it.

**Warnings:**
- Never store or cache a `TokenContainer` outside this framework.
- Never pass a `TokenContainer` around: ask the `OAuthClient` for it, use it and discard it. The exception is the IPC above.

### OAuthClient

`DefaultOAuthClient` is a Swift `actor`:
- Every call is `await`ed.
- Storage is accessed from one place at a time.
- Concurrent refreshes share one request, and so do concurrent restores.

## Usage

1. Create a `DefaultOAuthService` with an `APIService` that doesn't follow redirects.
2. Create a `DefaultOAuthClient` with the storage for the current token and, to keep a backup, the storage for the backup.
3. Get tokens through `getTokens(policy:)`.

```swift
let authService = DefaultOAuthService(baseURL: OAuthEnvironment.production.url,
                                      apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: userAgent))

// Without a backup
let oAuthClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                     authService: authService,
                                     refreshEventMapping: refreshEventMapping)

// With a backup, as the main apps do
let oAuthClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                     authService: authService,
                                     refreshEventMapping: refreshEventMapping,
                                     backupStorage: backupTokenStorage,
                                     isBackupEnabled: { featureFlagger.isFeatureOn(.authBackupToken) },
                                     backupUserDefaults: subscriptionUserDefaults,
                                     backupEventMapping: backupEventMapping)

// Create an account if there is no usable token
let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)

// Or sign in with a purchase signature, such as an App Store receipt
let tokenContainer = try await oAuthClient.activate(withPlatformSignature: signature)

// A valid token for an authenticated request
let validTokens = try await oAuthClient.getTokens(policy: .localValid)
```

**Warning:** the `APIService` must not follow redirects, because the authorization flow reads them itself. `APIServiceFactory.makeAPIServiceForAuthV2` does this with `SessionDelegate`:

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
configuration.httpCookieStorage = nil
let urlSession = URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
```

## Token retrieval policies

`getTokens(policy:trigger:)` returns a `TokenContainer` according to `AuthTokensCachePolicy`. `getTokens(policy:)` uses the `.client` trigger.

| Policy | Behavior |
|---|---|
| `.local` | Returns the stored container as it is. Throws `missingTokenContainer` when none is stored. |
| `.localValid` | Returns the stored container, refreshing it first when the access token has expired or expires within 45 seconds. Throws `missingTokenContainer` when none is stored. |
| `.localForceRefresh` | Always refreshes the stored container. Throws `missingTokenContainer` when none is stored. |
| `.createIfNeeded` | Reads storage first and throws if the read fails, so a locked keychain never leads to a new account. Then behaves like `.localValid`; if that throws for any reason, it creates a new account and stores it. |

The `trigger` (`TokenRefreshTrigger`) says what started the request and is reported on the refresh wide event: `.client`, `.backend` (a 401 retry path), `.createIfNeeded` and `.tokenAdoption`.

The client never restores from the backup on its own. A missing or rejected token is reported to the caller, which decides whether to call `restoreFromBackup(expectedExternalID:)`. See [How the apps use it](#how-the-apps-use-it).

## Token container lifecycle

### Creation

- **New account** (`.createIfNeeded`): `authorize` with a PKCE code challenge, `createAccount` for an authorization code, then exchange the code for a token pair.
- **Sign-in** (`activate(withPlatformSignature:)`): the same flow, with `login` and the purchase signature instead of `createAccount`.
- **Adoption** (`adopt(tokenContainer:)`): stores a container obtained elsewhere, such as the subscription page's email restore flow.

Each new pair is verified against the published signing keys before it's stored. Storing a container of another account deletes the backup.

### Storage

- `AuthTokenStoring` keeps one container. `readTokenContainer()` tells a stored item that can't be decoded (`.undecodable`) apart from a missing one (`.missing`); the default implementation reports both as `.missing`.
- The apps use `SubscriptionTokenKeychainStorage`: the `tokenContainer` field for the current pair, shared with the app's extensions, and the `backupTokenContainer` field for the backup, kept by the main app only.

### Refresh

When the access token has expired or expires within 45 seconds, `.localValid` refreshes it:

1. If a refresh is running, the caller waits for it and gets its result.
2. The stored refresh token is sent to `/api/auth/v2/token`.
3. The signing keys are fetched and both new tokens are verified.
4. The new container replaces the stored one. The refresh token rotates, so the whole container is replaced.
5. If the session changed while the request ran, the new pair is discarded and the container stored at that point is returned. See [Sessions and concurrency](#sessions-and-concurrency).
6. If the backup needs renewal, a new one is minted in the background. See [Renewal](#renewal).

Refreshing happens on demand. Nothing in this framework refreshes on a schedule; on iOS the app refreshes in the background when the refresh token gets old (see [How the apps use it](#how-the-apps-use-it)).

### Expiration

| Token | Lifetime |
|---|---|
| Access token | 4 hours (4 minutes in staging) |
| Refresh token | 30 days |

A refresh with a refresh token the server no longer accepts fails with `OAuthClientError.invalidTokenRequest` or `.unknownAccount`. The client keeps the stored container; the caller decides what to do next.

### Sign-out and local removal

| | `logout()` | `removeLocalAccount(includingBackup:)` |
|---|---|---|
| Current token | Removed | Removed |
| Backup | Deleted | Deleted only when `includingBackup` is `true` |
| Sign-out cut-off | Recorded | Not recorded |
| Server | `/logout` is sent and not awaited; its result is ignored. It revokes every token issued from the same login, the backup included. | Not contacted. The tokens stay valid on the server. |

`logout()` throws the storage error when the current token can't be read or removed, after recording the cut-off and deleting the backup.

## Backup token

The backup is a second, independent token pair for the same account, kept in its own storage. If the current token is lost, for example because the keychain item is deleted or a refresh is rejected after a race between processes, the backup can mint a new current pair without asking the user to sign in again.

The backup is kept only when the client is created with `backupStorage`. In the apps, only the main iOS and macOS apps do this; the VPN extensions, the macOS VPN app and the macOS PIR agent don't.

### Renewal

After a successful refresh, the client mints a new backup in the background when:
- the backup is enabled,
- no renewal is running, and
- there is no backup, or the stored one has expired, belongs to another account, or its refresh token was issued more than 14 days ago.

The renewal spends the refresh token the refresh just used a second time, so the refresh itself isn't delayed. A failure to read the stored backup skips the renewal.

The new backup is stored only if, when the request returns, the session is unchanged, the stored current token belongs to the same account, and the backup is still enabled. Otherwise it is discarded silently. Success is reported as `backupRenewed`; a failed request or a failed write is reported as `backupRenewalFailed`, and the next refresh tries again.

### Restore

`restoreFromBackup(expectedExternalID:)` replaces the current token with one minted from the backup:

1. The backup must be enabled and configured, otherwise it throws `TokenBackupError.unavailable`.
2. The stored backup is validated. It must:
   - be readable (`.readFailed`), stored (`.unavailable`) and decodable (`.undecodable`),
   - belong to `expectedExternalID`, when given (`.accountMismatch`),
   - have been issued after the [sign-out cut-off](#sign-out-cut-off) (`.predatesSignOut`),
   - not have expired (`.expired`).

   A backup that can't be decoded or is rejected is deleted; one that is missing or can't be read is left alone.
3. The current token is read; a read failure is thrown and nothing is refreshed.
4. The backup's refresh token is forked into two pairs: the first becomes the new backup, the second the new current token.
5. Before anything is stored, the client checks the session is still the one the restore started from: no [session change](#sessions-and-concurrency) in this client, the backup still stored, and the current token readable and unchanged (one deleted by another process is fine). If not, it throws `TokenBackupError.sessionChanged`, stores nothing, and deletes the spent backup if it's still stored.
6. The new current token is stored, then the new backup. If the backup was disabled meanwhile, the spent backup is deleted instead.

If the fork fails part way:
- After one pair: that pair becomes the current token and the spent backup is deleted.
- On the first call: nothing is stored. After `invalidTokenRequest` or `unknownAccount` the backup is deleted; after any other error, such as a network failure, it's kept. The error is thrown.

Concurrent calls share one restore.

### Sign-out cut-off

`logout()` records a cut-off in `backupUserDefaults`. A backup whose refresh token was issued at or before it is never restored, even if deleting it failed or another process wrote it back.

The cut-off is the newest issue date among the current token's and the stored backup's refresh tokens. Those dates come from the auth server's clock, so a wrong device clock can't move it. When neither token is available, the previous cut-off is kept, unless reading the current token failed, in which case the current date is used.

### When the backup is deleted

- `logout()`.
- `removeLocalAccount(includingBackup: true)`.
- Storing a current token of another account: `activate`, `adopt`, `setCurrentTokenContainer` and account creation through `.createIfNeeded`. A backup of the same account is kept.
- A restore that finds the backup undecodable, of another account, issued before the cut-off or expired.
- A restore whose first refresh is rejected with `invalidTokenRequest` or `unknownAccount`.
- A restore that minted only one pair, or ran while the backup was disabled.
- A restore discarded because the session changed, if the spent backup is still stored.

### The authBackupToken flag

`isBackupEnabled` is checked every time a backup would be created, renewed or restored from, so turning the flag off takes effect without a restart. When it returns `false`:
- no backup is created, renewed or restored from, and `restoreFromBackup` throws `.unavailable`;
- a stored backup is still deleted in the cases above, so turning the flag back on never brings back a backup that should have been deleted;
- a renewal or restore that was running stores no new backup.

The apps wire it to the `authBackupToken` feature flag.

## Sessions and concurrency

The client counts session changes: sign-out, adoption, activation, account creation and storing a token directly. Work started before a change doesn't store its result after it:

- A **refresh** that finishes after a change discards its pair and returns the container stored at that point, or throws `missingTokenContainer` when none is stored.
- A **backup renewal** is discarded.
- A **restore** throws `TokenBackupError.sessionChanged`.

Refreshes and restores are each deduplicated: a second caller waits for the running task and gets its result.

## Error handling

### How the Auth API's responses are read

`OAuthRequest` declares a `successCode` and the `bodyErrorDecodableCodes`. `DefaultOAuthService` then:
- returns the response for `successCode`;
- decodes a `BodyError` for a status in `bodyErrorDecodableCodes` and throws `OAuthServiceError.authAPIError`, or `.missingResponseValue(.bodyError)` when it can't be decoded;
- throws `OAuthServiceError.invalidResponseCode(status)` for any other status.

| Request | Success | Body decoded on |
|---|---|---|
| `authorize`, `createAccount`, `login` | 302 | 400, 500 |
| `getAccessToken` | 200 | 400, 500 |
| `refreshAccessToken` | 200 | 400 only. A 500 is `invalidResponseCode`. |
| `logout`, `editAccount`, `confirmEditAccount` | 200 | 401, 500 |
| `jwks` | 200 | None |

`DefaultTokenRefresher.refresh` maps two body errors to client errors: `invalid_token_request` to `OAuthClientError.invalidTokenRequest(tokenStatus)` and `unknown_account` to `.unknownAccount`. Every other error is thrown as it is. A 401 or 403 from the token endpoint is therefore `invalidResponseCode`, not a rejection.

### Errors

```swift
public enum OAuthClientError: DDGError {
    case internalError(String)
    case missingTokenContainer
    case unauthenticated
    case invalidTokenRequest(OAuthRequest.TokenStatus?)
    case unknownAccount
}
```

| Error | Meaning |
|---|---|
| `OAuthClientError.missingTokenContainer` | No current token is stored. |
| `OAuthClientError.invalidTokenRequest` | The server rejected the refresh token. `TokenStatus` says why, when the response includes it. |
| `OAuthClientError.unknownAccount` | The server doesn't know the account. |
| `OAuthClientError.internalError` | A bug or unexpected state, such as failing to generate the PKCE challenge or a fork returning no pair. |
| `OAuthClientError.unauthenticated` | Not thrown by `DefaultOAuthClient`. |
| `OAuthServiceError` | The request couldn't be sent or its response couldn't be used: `authAPIError`, `apiServiceError`, `invalidRequest`, `invalidResponseCode`, `missingResponseValue`. |
| `TokenBackupError` | Why the backup can't be used: `unavailable`, `accountMismatch`, `predatesSignOut`, `expired`, `sessionChanged`, `readFailed`, `undecodable`. |
| `TokenForkError.incomplete` | Thrown by `TokenRefreshing.fork` with the pairs minted before the failure. `DefaultOAuthClient` never lets it escape. |

The client never signs anyone out on its own. Deciding what a rejection means for the session is up to the caller.

### Classifying a failed restore

`BackupRestoreFailure(error)` says whether a failed restore could succeed if tried again:

| Classification | Errors |
|---|---|
| `.temporary` | `URLError`, `APIRequestV2Error.urlSession`, a 5xx, 408 or 429 response, a backup that couldn't be read because the keychain is locked. |
| `.permanent` | Any other `TokenBackupError`, `invalidTokenRequest`, `unknownAccount`. |
| `.unknown` | Everything else, including other HTTP statuses and other keychain read failures. |

## Events

**Refresh events** (`refreshEventMapping`, `OAuthClientRefreshEvent`) report each step of a refresh under one `refreshID`: started (with its trigger), refreshing, refreshed, fetching and fetched JWKS, verifying the access and refresh tokens, saving, succeeded and failed. The apps turn them into the AuthV2 token refresh wide event. Backup renewals and restores report no refresh events.

**Backup events** (`backupEventMapping`, `OAuthClientBackupEvent`):
- `backupRenewed`
- `backupRenewalFailed(error)`
- `storageFailed(action, operation, error)` for every failed read, write or delete of the backup storage. `TokenBackupAction` is the client action (`renewal`, `restore`, `signOut`, `localSignOut`, `signIn`) and `TokenBackupStorageOperation` is `read`, `write` or `delete`.

## How the apps use it

`SubscriptionManager` (in `BrowserServicesKit/Subscription`) wraps the client and decides what a failure means for the session:

| `getTokens` failure | What `SubscriptionManager.getTokenContainer` does |
|---|---|
| `missingTokenContainer` | Restores from the backup when a recovery coordinator is set; otherwise throws `noTokenAvailable`. |
| `invalidTokenRequest` | Uses a newer token another process stored meanwhile, if there is one. Otherwise runs the recovery: backup restore first, then, for App Store subscriptions, the App Store restore. If the session changed during the recovery, keeps the new session. If the recovery fails, signs out locally and keeps the backup. |
| `unknownAccount` | Signs out locally and deletes the backup. |
| Anything else | Keeps the session and throws `errorRetrievingTokenContainer`. |

- The strategies live in `TokenRecovery/`: `TokenRecoveryCoordinator` runs `BackupTokenRecovery` and `AppStoreTokenRecovery` in order and stops at the first success.
- After a missing-token restore fails for a reason that isn't `.permanent`, `BackupTokenRecovery` skips further missing-token restores for 5 minutes.
- Both apps call `restoreMissingTokenIfPossible()` when they become active, so a lost token comes back without waiting for a request.
- On iOS, `SubscriptionTokenKeepAlive` refreshes the token in the background once its refresh token is 15 days old, behind the `authBackgroundTokenRefresh` flag, so a session the app doesn't use renews before it expires.
- Explicit sign-out (`signOut`) calls `logout()`. Automatic sign-outs call `removeLocalAccount(includingBackup:)` and never contact the server, so they don't revoke the backup.

## Public API

### Tokens
- `getTokens(policy:trigger:) async throws -> TokenContainer`, and `getTokens(policy:)` with the `.client` trigger.
- `currentTokenContainer() throws -> TokenContainer?`: the stored container, without refreshing it.
- `setCurrentTokenContainer(_:) throws`: stores a container, or removes it with `nil`, as a new session. Use with caution.
- `isUserAuthenticated: Bool`: whether a container can be read from storage.
- `decode(accessToken:refreshToken:refreshID:) async throws -> TokenContainer`: verifies two tokens and wraps them in a container, without storing it.

### Account
- `activate(withPlatformSignature:) async throws -> TokenContainer`: signs in with a purchase signature.
- `adopt(tokenContainer:) throws`: stores a container obtained elsewhere as a new session.

### Backup
- `restoreFromBackup(expectedExternalID:) async throws -> TokenContainer`: see [Restore](#restore).

### Sign-out
- `logout() async throws`: see [Sign-out and local removal](#sign-out-and-local-removal).
- `removeLocalAccount(includingBackup:) throws`: removes the current token locally, and the backup when asked.

## Security and other considerations

- Secure storage is the injected `AuthTokenStoring`'s job, not this framework's.
- Tokens are verified with the keys published at `/api/auth/v2/.well-known/jwks.json`, fetched each time a pair is decoded.
- Tokens are refreshed when they expire within 45 seconds.
- The backup is a credential like the current token: it's kept in the keychain, deleted at sign-out, and never restored when issued before the last sign-out.
- `/logout` revokes every token from the same login, the backup included, so only an explicit sign-out should call `logout()`.

## Testing and mocks

The `TestingSupport` folder of the `Networking` target holds the test helpers, behind `@_spi(Testing)`:

- `MockOAuthClient`, `MockOAuthService`, `MockTokenStorage` and `MockAPIService`, each configurable with a result or an error per method.
- `OAuthTokensFactory` builds token containers in different states: valid, expiring, expired, with entitlements, and Auth API errors.
- `MockURLProtocol` isolates code from the real API for integration tests.
- `APIMockResponseFactory` and `HTTPURLResponseExtension` provide ready-made responses, such as `HTTPURLResponse.ok` or `HTTPURLResponse.internalServerError`.

`DefaultTokenRefresher.setTestingDecodedTokenContainers(_:)` (debug builds only) makes `decode` return given containers instead of verifying real JWTs.

## Additional documentation

- [OAuth 2.0 protocol](https://auth0.com/intro-to-iam/what-is-oauth-2)
- [Auth API V2 Documentation](https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md)
- [Original Task with Tech Designs](https://app.asana.com/1/137249556945/project/72649045549333/task/1207591586576970?focus=true)
