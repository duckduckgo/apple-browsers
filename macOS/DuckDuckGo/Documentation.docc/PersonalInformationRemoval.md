# Personal Information Removal

Automated scanning and removal of personal information from data broker sites through a background agent.

## Overview

Personal Information Removal (PIR) is a Privacy Pro subscription feature that automatically finds and removes a user's personal information from data broker websites. A background agent scans data broker sites for user profiles, submits opt-out requests, and monitors for re-appearances.

**Privacy Pro required**: this feature requires an active Privacy Pro subscription and handles sensitive user information (names, addresses, birthdates) with secure storage and a privacy-first design.

### Naming

"Personal Information Removal" (PIR) is the **user-facing** feature name and is used in UI, settings, and prose throughout this document. The **code identifiers** still use the original "DataBrokerProtection" / "DBP" naming — `DataBrokerProtectionAgentManager`, `DBPUICommunicator`, the `dataBrokerProtection` tab case, and so on. Both names refer to the same feature; expect to see the code names when grepping the codebase.

## Architecture

### Process Layout

PIR splits across two processes that communicate via XPC:

- **DuckDuckGo.app (main browser)** — preferences pane for setup and status, a special browser tab for the detailed dashboard, status bar menu for quick access, and the IPC client that talks to the agent.
- **DataBrokerProtection background agent** — a persistent login item that runs the background scheduler, job queue, web operations (scan/opt-out), and the secure database.

### Key Components

- ``DataBrokerProtectionAgentManager`` (DataBrokerProtection-macOS package) — orchestrates the background agent lifecycle, manages scheduling, operations, and the IPC server, and coordinates database, authentication, and notifications.
- ``DataBrokerProtectionIPCClient`` (DataBrokerProtection-macOS package) — IPC client in the main browser app. Communicates with the background agent via XPC.
- ``DataBrokerProtectionIPCServer`` (DataBrokerProtection-macOS package) — the IPC server **protocol**. The concrete implementation is ``DefaultDataBrokerProtectionIPCServer``, which runs in the background agent, receives commands from the main app, and sends back progress updates.
- ``BrokerProfileJob`` (DataBrokerProtectionCore package) — core operation unit for scan and opt-out tasks, including timeout, cancellation, and error reporting.
- ``DataBrokerProtectionDataManager`` (DataBrokerProtection-macOS package) — manages data flow between agent, database, and UI; coordinates profile storage and retrieval; handles VPN bypass settings.

## Core Operations

### Scanning

Scans find a user's personal information on data broker websites.

The agent queues a scan job for each broker × profile-query combination, navigates to the broker with the user's search parameters, extracts matching profiles, compares them against previously found profiles, schedules opt-out jobs for new matches, and records results and timing metrics.

There are two scan types: **scheduled scans** run automatically based on per-broker refresh rates, and **manual scans** can be triggered by the user from the dashboard. Scans respect broker-specific timing requirements — some brokers require waiting periods between operations.

### Opt-Out

Opt-out removes the user's information from a data broker site.

The agent validates preconditions (profile not already removed, eligible for opt-out), navigates to the broker's opt-out page, fills out the form, submits the request, handles email confirmation if required, records the attempt, and verifies removal on subsequent scans.

Edge cases include parent opt-outs (some brokers perform opt-outs through parent company sites), manual exclusions (users can mark profiles as "This isn't me" to skip opt-outs), and reappearances (profiles may reappear after removal, triggering new opt-outs).

### Email Confirmation

Some brokers require email confirmation: the broker sends a confirmation email, the agent monitors for the link, the user clicks it (from the email or dashboard), and the agent completes the opt-out.

## Data Storage

User profile information (names, addresses, birthdates) is stored in an encrypted secure vault — ``DataBrokerProtectionSecureVault`` in the DataBrokerProtectionCore package — with key management via the macOS Keychain. The PIR vault is isolated from the browser's main secure vault.

Persistent storage holds:

- **Broker definitions** — data broker metadata and opt-out procedures (JSON-based).
- **Profile queries** — user's search parameters (name variations, addresses).
- **Extracted profiles** — found matches on broker sites with timestamps.
- **Opt-out jobs** — scheduled and completed opt-out operations.
- **History events** — timeline of scans, opt-outs, and profile changes.

## Integration Points

### Preferences

Settings → Privacy Pro → Personal Information Removal provides the setup flow, status indicator, a link to the detailed dashboard, and FAQ access.

### Browser Tab Integration

PIR uses a dedicated tab content case (`.dataBrokerProtection` in ``TabContent``) to display the web-based dashboard inside a browser tab. The UI is a React-based hosted web application with a JavaScript ↔ Swift messaging bridge. From it the user manages profiles, views found profiles and opt-out status, triggers manual scans, and marks profiles as incorrect.

Bidirectional messaging between the web UI and native agent goes through ``DBPUICommunicator``.

### Status Bar Menu

A macOS menu bar item provides quick access — status indicator (active/scanning/idle), quick link to the dashboard, and agent version for debugging.

### Background Scheduling

Automated operations run on configured schedules: the initial scan after profile setup, scheduled opt-outs, periodic re-scans for reappearing profiles (broker-specific intervals), and monitoring for pending email confirmations. Scheduling respects broker-specific timing requirements and avoids excessive requests.

## VPN Bypass

PIR operations can bypass the VPN tunnel, because some data broker sites block or rate-limit VPN traffic.

``VPNBypassService`` (DataBrokerProtection-macOS package) implements the ``VPNBypassServiceProvider`` protocol from DataBrokerProtectionCore and coordinates with the VPN to exclude PIR traffic from the tunnel on a per-operation basis. Users can toggle VPN bypass in PIR settings.

## Authentication and Entitlements

PIR requires an active Privacy Pro subscription with the PIR entitlement.

- ``DataBrokerProtectionAuthenticationManaging`` (DataBrokerProtectionCore package) — verifies subscription status, provides access tokens for backend services, and monitors entitlement changes.
- ``DataBrokerProtectionEntitlementMonitoring`` (DataBrokerProtectionCore package) — tracks subscription state changes, disables features when subscription lapses, and handles renewals.

PIR talks to backend services for broker definition updates, opt-out email confirmation handling, and automated captcha solving for opt-out forms.

## Notifications

User notifications cover the events that need attention — first scan complete (with found profiles count), successful opt-out confirmations, profile reappearances, and email confirmations the user needs to action. Notifications are throttled to avoid spam and respect user preferences.

## Package Architecture

**DataBrokerProtectionCore** (shared package) holds the cross-platform business logic: scan/opt-out operation execution, broker/profile/job models, the content capture framework used for web automation, secure storage (database and vault), and authentication/entitlement management.

**DataBrokerProtection-macOS** (local package) holds macOS-specific integration: background agent lifecycle and scheduling, XPC IPC between app and agent, native SwiftUI preferences views, web UI hosting and the communication bridge, status bar menu, and VPN bypass integration.

## Common Tasks

### Testing PIR Operations

Internal builds expose a debug menu with custom JSON broker definitions, forced opt-outs for testing, real-time log monitoring, and a database browser.

### Monitoring Operations

The web dashboard shows detailed scan and opt-out status. Console.app can be filtered to the "PIR" subsystem for live logs. The database can be queried directly for operations, extracted profiles, and history events.

### Troubleshooting

- **Agent not running** — check login item status and permissions.
- **Operations stalled** — check for network issues and VPN bypass status.
- **Email confirmations pending** — user action may be required.
- **Subscription issues** — verify Privacy Pro subscription status.

## Privacy and Security

PIR follows data minimization — only information necessary for operations is stored, extracted profiles are deleted after successful removal, and temporary data is cleared after operations complete.

User profile data is encrypted at rest in the secure vault. Communication with backend services is encrypted, and sensitive user information is not logged.

Users control which name variations and addresses are scanned, can mark profiles as incorrect to prevent opt-outs, can pause or disable PIR at any time, and can delete all stored data.

## Related Topics

- <doc:VPNNetworkProtection> — VPN bypass integration
- <doc:Preferences> — Settings UI integration
- <doc:TabManagement> — Dashboard tab integration
