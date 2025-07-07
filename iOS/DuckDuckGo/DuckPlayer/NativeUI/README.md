# DuckPlayer Native

## Native UI Architecture Overview

The DuckPlayer Native UI provides video playback within the app, separate from the web view-based player. The architecture separates concerns into distinct components:

1.  **`DuckPlayerNativeUIPresenter`**:
    *   **Role**: Primary coordinator and state manager for the Native UI.
    *   **Responsibilities**:
        *   Manages presentation and lifecycle of player UI components.
        *   Coordinates between pill types (welcome, entry, re-entry), player view, and container views.
        *   Handles user interactions and navigation events.
        *   Manages visibility and state of UI components with constraint updates.
        *   Integrates with app navigation and browser features.
        *   Handles orientation changes and UI adaptations.
        *   Manages pixel firing for analytics and user interaction tracking.
        *   Controls toast notifications and dismiss count tracking.

2.  **`NativeDuckPlayerNavigationHandler`**:
    *   **Role**: Manages video playback navigation and browser integration.
    *   **Responsibilities**:
        *   Intercepts YouTube video URLs and navigation events.
        *   Determines whether to handle videos with native UI based on settings.
        *   Coordinates with main browser navigation.
        *   Manages video playback states and transitions.
        *   Handles back/forward navigation in browser history.
        *   Controls media playback in web view context.

3.  **`DuckPlayerState`**:
    *   **Role**: Maintains state for video playback tracking.
    *   **Properties**:
        *   `videoID`: Optional String storing the current video's identifier.
        *   `hasBeenShown`: Boolean flag tracking if the player has been displayed.
        *   `timestamp`: Optional TimeInterval for video playback position.
    *   **Functionality**:
        *   Provides a `reset()` method to clear all state values.
        *   Used by the presenter to maintain video playback context.
        *   Enables state restoration and video position tracking.

4.  **`YoutubeOembedService`**:
    *   **Role**: Handles YouTube video metadata retrieval.
    *   **Responsibilities**:
        *   Fetches video information using YouTube's oEmbed API.
        *   Provides video titles, thumbnails, and other metadata.
        *   Supports the native UI with video information.

5.  **`DuckPlayerDelayHandler`**:
    *   **Role**: Manages timing-related operations for the player.
    *   **Responsibilities**:
        *   Handles delayed actions and transitions.
        *   Controls timing for UI animations and state changes.
        *   Manages autoplay and interaction delays.

6.  **`DuckPlayerPixelFiring`**:
    *   **Role**: Provides protocol-based approach for analytics pixel firing.
    *   **Responsibilities**:
        *   Defines interface for firing DuckPlayer-related pixels with debouncing.
        *   Supports both regular and daily pixel firing.
        *   Handles pixel parameters and timing control.
        *   Implemented by `DuckPlayerPixelHandler` for actual pixel dispatch.

## UserScripts Directory

The Native UI includes JavaScript integration for communication between native Swift components and web-based video players:

### Core UserScript Components

*   **`DuckPlayerUserScript`**:
    *   **Role**: Base configuration and utilities for all UserScript components.
    *   **Responsibilities**:
        *   Defines common constants, page types, and event handlers.
        *   Provides page type detection (SERP, YouTube, YouTube NoCookie, etc.).
        *   Establishes messaging protocols between native and web components.
        *   Manages feature naming and identification across the system.

*   **`DuckPlayerUserScriptYouTube`**:
    *   **Role**: Handles JavaScript integration for YouTube pages.
    *   **Responsibilities**:
        *   Manages media control communication (play/pause states).
        *   Handles audio muting coordination between native and web players.
        *   Processes URL change events and page type transitions.
        *   Queues and synchronizes events until scripts are ready.
        *   Communicates timestamp updates from web video player.
        *   Processes YouTube-specific error handling and reporting.
        *   Supports domain-specific messaging policies for security.

*   **`DuckPlayerUserScriptPlayer`**:
    *   **Role**: Script handler for DuckPlayer's native video interface.
    *   **Responsibilities**:
        *   Facilitates communication with ContentScopeScripts in DuckPlayerWebView.
        *   Manages timestamp synchronization between web player and native UI.
        *   Handles initial setup and configuration for video playback.
        *   Processes video player errors and state changes.
        *   Provides localization support for web-based player components.

### UserScript Features

*   **Event Queuing System**: Queues events until scripts are ready to prevent race conditions.
*   **Domain Security**: Enforces strict message origin policies for YouTube and DuckDuckGo domains.
*   **Bidirectional Communication**: Enables data flow between native Swift and web JavaScript.
*   **State Synchronization**: Keeps video playback state consistent across native and web components.
*   **Error Handling**: Error reporting and handling for web-based video issues.
*   **Localization Support**: Provides locale information to web components for internationalization.

## Views Directory Components

### Core Views
*   **`DuckPlayerView`**: 
    *   Main player interface with video playback controls.
    *   Includes welcome message bubble with Dax branding.
    *   Supports landscape/portrait orientation handling.
    *   Features settings integration and YouTube navigation.

*   **`DuckPlayerContainer`**: 
    *   Manages the layout and presentation container for pills.
    *   Handles drag gestures and sheet presentation animations.
    *   Provides constraint-based positioning and responsive layout.

*   **`DuckPlayerWebView`**: 
    *   Native WebKit integration for video playback.
    *   Handles JavaScript messaging and video controls.
    *   Manages video loading states and error handling.

### Pill Components
The native UI features multiple pill types for different user interaction scenarios:

*   **`DuckPlayerWelcomePillView`** & **`DuckPlayerWelcomePillViewModel`**:
    *   First-time user experience with animated Lottie introduction.
    *   Features Dax branding and opt-in messaging.
    *   Presents initial DuckPlayer value proposition.

*   **`DuckPlayerEntryPillView`** & **`DuckPlayerEntryPillViewModel`**:
    *   Standard entry point for returning users on new videos.
    *   Clean, minimal design with play button and branding.
    *   Handles video initiation from YouTube pages.

*   **`DuckPlayerMiniPillView`** & **`DuckPlayerMiniPillViewModel`**:
    *   Re-entry pill for videos previously watched in DuckPlayer.
    *   Shows video thumbnail and "Resume in DuckPlayer" messaging.
    *   Provides context about continuing viewing experience.

### Modal Components
*   **`DuckPlayerPrimingModalView`** & **`DuckPlayerPrimingModalViewModel`**:
    *   Full-screen introduction modal for new users.
    *   Features animated Lottie content and educational messaging.
    *   Provides primary call-to-action for DuckPlayer adoption.

### Supporting Components
*   **`DuckPlayerToastView`**: 
    *   System for displaying temporary notifications.
    *   Configurable positioning (top/bottom) and timing.
    *   Used for settings reminders and user guidance.

*   **`BubbleView`**: 
    *   Reusable component for speech bubble-style UI elements.
    *   Configurable arrow positioning and styling.
    *   Used in welcome messages and contextual hints.

*   **`DuckPlayerViewUtils`**: 
    *   Utility functions for view calculations and helpers.
    *   Supports consistent spacing, sizing, and layout patterns.

### ViewModels
*   **`DuckPlayerViewModel`**: 
    *   State management for video player behavior.
    *   Integrated pixel firing for user interaction analytics.
    *   Orientation handling and landscape mode support.
    *   YouTube navigation and settings integration.

## Architecture Features

### Pill Type Management
The presenter manages three distinct pill types based on user state:
- **Welcome**: For first-time users (priming modal not yet presented)
- **Entry**: For returning users viewing new videos  
- **Re-entry**: For users returning to previously watched videos

### JavaScript Integration
- **Native-Web Bridge**: Communication between Swift and JavaScript components
- **Event Synchronization**: Coordinated state management across native and web players
- **Domain Security**: Strict origin policies for secure cross-domain messaging
- **Script Readiness**: Event queuing system to handle timing dependencies

### Pixel Analytics Integration
- Protocol-based pixel firing with `DuckPlayerPixelFiring`
- Debounced pixel events to prevent spam
- Daily and regular pixel tracking capabilities
- User interaction analytics

### Toast Notification System
- Non-intrusive user messaging system
- Configurable display duration and positioning
- Integration with settings deep-linking
- User guidance and feature education

### State Management
- Video state tracking across sessions
- Timestamp preservation for video continuation
- User interaction history and preferences
- Dismiss count tracking for user experience optimization

## Features
*   SwiftUI-based reactive UI components with animations.
*   Multi-modal user experience (pills, modals, full player).
*   Responsive layout adapting to device orientation and user preferences.
*   Smooth animations and transitions with spring physics.
*   Integration with native video playback and browser navigation.
*   Analytics and user behavior tracking.
*   Accessibility support and design system integration.
*   Lottie animation support for user onboarding.
*   JavaScript bridge for web-native integration.
*   Cross-domain security with strict message origin policies.

# DuckPlayer Variants

## Overview
The DuckPlayer variant management system allows for different configurations of the video player feature through predefined variants. Each variant represents a specific combination of settings that define how the player behaves and appears to users.

## Available Variants

### Classic
The traditional DuckPlayer experience

**Characteristics:**
- Uses classic (non-native) user interface
- Always asks for user preference when playing videos
- Opens videos in new tabs by default
- Prioritizes user choice over automation

**Key Settings:**
- Native UI: Disabled
- Player Mode: Always Ask
- New Tab Behavior: Enabled

### Native (Opt-in)
A native experience with balanced automation.

**Characteristics:**
- Uses the native user interface with welcome pill system
- Integrates with SERP (Search Engine Results Page)
- Provides user choice for YouTube mode with priming modal
- Enables automatic playback features with user guidance

**Key Settings:**
- Native UI: Enabled
- SERP Integration: Enabled
- YouTube Mode: Ask user preference
- Autoplay: Enabled
- Priming Modal: Enabled for new users

### Native (Opt-out)
Fully automated native experience for streamlined playback.

**Characteristics:**
- Uses the native user interface with streamlined pill system
- Full SERP integration
- Automatic YouTube mode handling
- Streamlined playback experience
- Re-entry experience with video thumbnails

**Key Settings:**
- Native UI: Enabled
- SERP Integration: Enabled
- YouTube Mode: Automatic
- Autoplay: Enabled
- Pills: Entry and Re-entry types

## Implementation Details

### Variant Management
- Variants are managed through a dedicated variant setting in the Experimental section.
- Users can select a variant (`Web`, `Opt-in`, `Opt-out`) from a dropdown menu.
- Selecting a variant automatically applies its predefined configuration set (Native UI, SERP Integration, YouTube Mode, Autoplay, New Tab Behavior, etc.).
- The system supports runtime variant switching, but requires closing open tabs for changes to fully take effect in existing sessions.
- Pill presentation logic adapts based on variant selection and user interaction history.

### Settings Integration
The variant system implicitly controls the following DuckPlayer settings based on the selected variant:
- Native UI preferences and pill type selection
- SERP integration configuration
- YouTube mode settings (ask vs automatic)
- Autoplay behavior and user onboarding
- Tab management preferences (Open in New Tab)
- Player Mode (Always Ask / Enabled)
- Priming modal and welcome experience settings
