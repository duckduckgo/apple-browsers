# DuckPlayer Native

## Native UI Architecture Overview

The DuckPlayer Native UI architecture is designed to provide a seamless, integrated video playback experience within the app, distinct from the traditional web view-based player. It follows a structured approach, separating concerns into distinct components:

1.  **`DuckPlayerNativeUIPresenter`**:
    *   **Role**: Acts as the primary coordinator and state manager for the Native UI.
    *   **Responsibilities**:
        *   Manages the presentation and lifecycle of the player UI components.
        *   Coordinates between the entry pill, player view, and container views.
        *   Handles user interactions and navigation events.
        *   Manages the visibility and state of UI components.
        *   Integrates with the app's navigation and browser features.
        *   Handles orientation changes and UI adaptations.

2.  **`NativeDuckPlayerNavigationHandler`**:
    *   **Role**: Manages video playback navigation and integration with the browser.
    *   **Responsibilities**:
        *   Intercepts YouTube video URLs and navigation events.
        *   Determines whether to handle videos with native UI based on settings.
        *   Coordinates with the main browser navigation.
        *   Manages video playback states and transitions.
        *   Handles back/forward navigation in browser history.
        *   Controls media playback in the web view context.

3.  **`DuckPlayerState`**:
    *   **Role**: Maintains the essential state for video playback tracking.
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
        *   Supports the native UI with rich video information.

5.  **`DuckPlayerDelayHandler`**:
    *   **Role**: Manages timing-related operations for the player.
    *   **Responsibilities**:
        *   Handles delayed actions and transitions.
        *   Controls timing for UI animations and state changes.
        *   Manages autoplay and interaction delays.

6.  **Views Directory**:
    *   **Components**:
        *   `DuckPlayerView`: Main player interface with video playback controls.
        *   `DuckPlayerContainer`: Manages the layout and presentation container.
        *   `DuckPlayerViewModel`: Handles video player state and behavior.
        *   `DuckPlayerEntryPillViewModel`: Controls the entry pill UI component.
    *   **Features**:
        *   SwiftUI-based reactive UI components.
        *   Responsive layout adapting to device orientation.
        *   Smooth animations and transitions.
        *   Integration with native video playback.


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
An enhanced native experience with balanced automation.

**Characteristics:**
- Uses the native user interface
- Integrates with SERP (Search Engine Results Page)
- Provides user choice for YouTube mode
- Enables automatic playback features

**Key Settings:**
- Native UI: Enabled
- SERP Integration: Enabled
- YouTube Mode: Ask user preference
- Autoplay: Enabled

### Native (Opt-out)
Fully automated native experience for seamless playback.

**Characteristics:**
- Uses the native user interface
- Full SERP integration
- Automatic YouTube mode handling
- Streamlined playback experience
- The first time DuckPlayer is used, a welcome message is presented

**Key Settings:**
- Native UI: Enabled
- SERP Integration: Enabled
- YouTube Mode: Automatic
- Autoplay: Enabled

## Implementation Details

### Variant Management
- Variants are managed through a dedicated variant setting in the Experimental section.
- Users can select a variant (`Web`, `Opt-in`, `Opt-out`) from a dropdown menu.
- Selecting a variant automatically applies its predefined configuration set (Native UI, SERP Integration, YouTube Mode, Autoplay, New Tab Behavior, etc.).
- The system supports runtime variant switching, but requires closing open tabs for changes to fully take effect in existing sessions.

### Settings Integration
The variant system implicitly controls the following DuckPlayer settings based on the selected variant:
- Native UI preferences
- SERP integration configuration
- YouTube mode settings
- Autoplay behavior
- Tab management preferences (Open in New Tab)
- Player Mode (Always Ask / Enabled)
