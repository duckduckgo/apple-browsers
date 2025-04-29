# DuckPlayer Variants

## Overview
The DuckPlayer variant management system allows for different configurations of the video player feature through predefined variants. Each variant represents a specific combination of settings that define how the player behaves and appears to users.

## Available Variants

### Classic A Variant
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

### Native B Variant
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

### Native C Variant
Fully automated native experience for seamless playback.

**Characteristics:**
- Uses the native user interface
- Full SERP integration
- Automatic YouTube mode handling
- Streamlined playback experience

**Key Settings:**
- Native UI: Enabled
- SERP Integration: Enabled
- YouTube Mode: Automatic
- Autoplay: Enabled

## Implementation Details

### Variant Management
- Variants are managed through a dedicated variant setting in the Experimental section.
- Users can select a variant (`classicA`, `nativeB`, `nativeC`) from a dropdown menu.
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
