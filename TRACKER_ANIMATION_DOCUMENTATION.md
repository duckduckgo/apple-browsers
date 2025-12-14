# Tracker Animation Feature - Technical Documentation

## Overview

This document describes the implementation of the **Tracker Blocked Animation** feature for macOS, which displays visual feedback in the navigation bar when trackers are blocked or cookie popups are managed. The feature mirrors the iOS implementation while adapting to macOS UI patterns.

---

## Architecture

### High-Level Flow

```
Page Load → Tracker Detection → Animation Queue → Badge Notification → Shield Animation
                                      ↓
                              Cookie Management → Animation Queue → Badge Notification
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| `NavigationBarBadgeAnimator` | `NavigationBarBadgeAnimator.swift` | Central queue manager for all badge animations |
| `NavigationBarBadgeAnimationView` | `NavigationBarBadgeAnimationView.swift` | Container view that hosts animated badge notifications |
| `BadgeNotificationContainerView` | `BadgeNotification/BadgeNotificationContainerView.swift` | SwiftUI-backed notification view |
| `BadgeNotificationContentView` | `BadgeNotification/BadgeNotificationContentView.swift` | SwiftUI content with icon and text |
| `AddressBarButtonsViewController` | `AddressBarButtonsViewController.swift` | Orchestrates animations and handles delegate callbacks |

---

## Animation Priority Queue System

### The Problem It Solves

When a page loads, multiple notifications can be triggered:
1. **Tracker notifications** - When trackers are blocked
2. **Cookie notifications** - When cookie consent popups are managed

These events can occur simultaneously or in rapid succession. Without a queue system, animations would:
- Overlap and create visual chaos
- Get lost if triggered while another animation is playing
- Not respect priority (trackers should show before cookies, matching iOS behavior)

### Implementation

#### Priority Enum

```swift
enum AnimationPriority: Comparable {
    case high  // Tracker notifications (shown first)
    case low   // Cookie notifications (shown after trackers)

    static func < (lhs: AnimationPriority, rhs: AnimationPriority) -> Bool {
        switch (lhs, rhs) {
        case (.low, .high): return true
        default: return false
        }
    }
}
```

**Why this priority order?**
- Matches iOS behavior exactly
- Tracker blocking is the primary privacy feature, so it should be highlighted first
- Cookie management is secondary feedback

#### Queued Animation Structure

```swift
struct QueuedAnimation {
    let type: NavigationBarBadgeAnimationView.AnimationType
    let priority: AnimationPriority
    var selectedTab: Tab?                                    // For tab-specific cancellation
    let buttonsContainer: NSView                             // UI reference
    let notificationBadgeContainer: NavigationBarBadgeAnimationView
}
```

#### Queue Processing Logic

```swift
func enqueueAnimation(...) {
    // 1. Create queued animation
    let queuedAnimation = QueuedAnimation(...)

    // 2. Add to queue
    animationQueue.append(queuedAnimation)

    // 3. Sort by priority (high first)
    animationQueue.sort { $0.priority > $1.priority }

    // 4. Start processing if not already animating
    if !isAnimating {
        processNextAnimation()
    }
}

func processNextAnimation() {
    guard !isAnimating, !animationQueue.isEmpty else { return }

    let nextAnimation = animationQueue.removeFirst()
    currentAnimationType = nextAnimation.type
    // ... start animation
}
```

---

## Animation Sequence

### Complete Flow for Tracker Notification

```
1. showTrackerNotification(count: 5)
   ├── Sets autoProcessNextAnimation = false
   └── Calls showBadgeNotification(.trackersBlocked(count: 5))

2. showBadgeNotification(type)
   ├── Determines priority = .high (for trackers)
   └── Enqueues animation

3. enqueueAnimation()
   ├── Adds to queue
   ├── Sorts by priority
   └── Calls processNextAnimation() if not busy

4. processNextAnimation()
   ├── Removes first item from queue
   ├── Sets currentAnimationType
   └── Calls showNotification()

5. showNotification()
   ├── Fade out buttons container (0.25s)
   ├── Fade in notification badge (0.25s)
   ├── Play badge animation (expand → pause → retract)
   ├── Fade out notification badge (0.25s)
   ├── Fade in buttons container (0.25s)
   └── Calls delegate.didFinishAnimating(type:)

6. didFinishAnimating(type: .trackersBlocked)
   ├── If HTTPS site:
   │   ├── Play Lottie shield animation
   │   └── On completion: call processNextAnimation()
   └── If HTTP site:
       └── Immediately call processNextAnimation()

7. processNextAnimation()
   └── If cookie notification queued → show it
```

### Timing

| Phase | Duration |
|-------|----------|
| Fade out buttons | 0.25s |
| Fade in badge | 0.25s |
| Badge expand | ~0.3s |
| Badge visible pause | ~1.5s |
| Badge retract | ~0.3s |
| Fade out badge | 0.25s |
| Fade in buttons | 0.25s |
| Shield animation (HTTPS only) | ~1.0s |

**Total:** ~4 seconds for tracker notification on HTTPS sites

---

## Shield Animation Logic

### Why Shield Animation Exists

After showing a tracker blocked notification, we play a Lottie animation on the privacy shield icon to reinforce that protection is active. This provides:
- Visual continuity from badge → shield
- Reinforcement of the privacy protection feature
- A polished, intentional animation flow

### Auto-Process Control

The `shouldAutoProcessNextAnimation` flag controls queue processing:

```swift
// Before showing tracker notification
buttonsBadgeAnimator.setAutoProcessNextAnimation(false)
showBadgeNotification(.trackersBlocked(count: count))

// In didFinishAnimating delegate callback
if case .trackersBlocked = type {
    // Play shield animation first
    shieldAnimationView.play(...) { finished in
        // THEN process next animation (cookie, etc.)
        self.buttonsBadgeAnimator.processNextAnimation()
    }
}
```

**Why this design?**
- Tracker notification ends → Badge fades out
- Shield animation must play BEFORE next notification
- Cookie notification (if queued) shows AFTER shield completes
- Without this, cookie would immediately show after tracker badge, skipping shield

### HTTP vs HTTPS Handling

```swift
guard url.navigationalScheme != .http else {
    // HTTP sites: no shield animation, process next immediately
    buttonsBadgeAnimator.processNextAnimation()
    return
}
// HTTPS: play shield animation, then process next
```

**Rationale:** HTTP sites don't show the animated shield because they're not secure. The static icon is shown instead.

---

## Animation Types

### NavigationBarBadgeAnimationView.AnimationType

```swift
enum AnimationType {
    case cookiePopupManaged   // "Cookies Managed" text + cookie icon
    case cookiePopupHidden    // "Pop-up Hidden" text + cookie icon
    case trackersBlocked(count: Int)  // "X Trackers Blocked" + shield icon
}
```

### Visual Differences

| Type | Icon | Text | Priority |
|------|------|------|----------|
| `trackersBlocked(5)` | Shield icon | "5 Trackers Blocked" | High |
| `cookiePopupManaged` | Cookie icon (Lottie) | "Cookies Managed" | Low |
| `cookiePopupHidden` | Cookie icon (Lottie) | "Pop-up Hidden" | Low |

---

## Tab Switching and Cancellation

### Problem: Stale Animations

When user switches tabs:
- Animations for the previous tab should be cancelled
- Animations queued for different tabs should be removed
- Current tab's animations should continue

### Solution: handleTabSwitch

```swift
func handleTabSwitch(to tab: Tab) {
    // Cancel current animation if it's for a different tab
    if let currentTab = currentTab, currentTab !== tab {
        cancelPendingAnimations()
    }

    // Remove queued animations for different tabs
    animationQueue.removeAll { queuedAnimation in
        guard let queuedTab = queuedAnimation.selectedTab else { return false }
        return queuedTab !== tab
    }
}
```

### When It's Called

```swift
// In subscribeToSelectedTabViewModel()
tabCollectionViewModel.$selectedTabViewModel.sink { tabViewModel in
    // Stop visual animations but preserve current tab's queue
    stopAnimations(badgeAnimations: false)

    if let tab = tabViewModel?.tab {
        buttonsBadgeAnimator.handleTabSwitch(to: tab)
    } else {
        buttonsBadgeAnimator.cancelPendingAnimations()
    }
}
```

**Key insight:** `stopAnimations(badgeAnimations: false)` stops visual Lottie animations but does NOT clear the queue. The animator's `handleTabSwitch` intelligently preserves same-tab animations.

---

## Delegate Pattern

### NavigationBarBadgeAnimatorDelegate

```swift
protocol NavigationBarBadgeAnimatorDelegate: AnyObject {
    func didFinishAnimating(type: NavigationBarBadgeAnimationView.AnimationType)
}
```

**Why pass the type?**

Previously, the delegate callback was `didFinishAnimating()` with no parameters. The controller had to track `lastNotificationType` separately. This caused a bug:

```
1. Tracker notification enqueued → lastNotificationType = .trackersBlocked
2. Cookie notification enqueued (while tracker animating) → lastNotificationType = .cookiePopupManaged
3. Tracker finishes → didFinishAnimating() → type is .cookiePopupManaged (WRONG!)
4. Shield animation doesn't play because type != .trackersBlocked
```

**Fix:** Animator tracks `currentAnimationType` and passes it to the delegate:

```swift
let finishedType = self?.currentAnimationType
self?.isAnimating = false
self?.currentAnimationType = nil
if let finishedType = finishedType {
    self?.delegate?.didFinishAnimating(type: finishedType)
}
```

---

## Files Changed

### New Files

| File | Purpose |
|------|---------|
| `NavigationBarBadgeAnimator.swift` | Queue management (heavily modified from original) |
| `NavigationBarBadgeAnimationView.swift` | Animation container |
| `BadgeNotificationContainerView.swift` | Renamed from cookie-specific naming |
| `BadgeNotificationContentView.swift` | SwiftUI content view |
| `BadgeAnimationView.swift` | Text animation component |
| `BadgeIconAnimationModel.swift` | Icon animation state |
| `BadgeNotificationAnimationModel.swift` | Notification animation state |
| `NavigationBarBadgeAnimatorTests.swift` | Unit tests for queue logic |

### Modified Files

| File | Changes |
|------|---------|
| `AddressBarButtonsViewController.swift` | Added delegate implementation, queue integration, shield animation logic |
| `NavigationBarViewController.swift` | Cookie notification handling |
| `AutoconsentUserScript.swift` | Posts notifications for cookie management |
| `UserText.swift` | Added pluralization for tracker notifications |
| `Localizable.xcstrings` | Localization strings |

---

## Renaming History

Classes were renamed from cookie-specific to generic badge naming:

| Old Name | New Name |
|----------|----------|
| `CookieNotificationContainerView` | `BadgeNotificationContainerView` |
| `CookieNotificationContentView` | `BadgeNotificationContentView` |
| `CookieAnimationView` | `BadgeAnimationView` |
| `CookieIconAnimationModel` | `BadgeIconAnimationModel` |
| `NavigationBarCookieAnimationView` | `NavigationBarBadgeAnimationView` |
| `NavigationBarCookieAnimator` | `NavigationBarBadgeAnimator` |

**Rationale:** The same animation system is used for both cookie and tracker notifications.

---

## Queue State Management

### Properties

```swift
private(set) var isAnimating = false                    // Is animation currently playing?
private(set) var animationQueue: [QueuedAnimation] = [] // Pending animations
private(set) var currentAnimationPriority: AnimationPriority?  // Current animation's priority
private(set) var currentAnimationType: NavigationBarBadgeAnimationView.AnimationType? // Current type
private var currentTab: Tab?                            // Tab for current animation
private var shouldAutoProcessNextAnimation = true       // Auto-process control
```

### State Transitions

```
IDLE (isAnimating=false, queue=[])
  │
  ├─ enqueueAnimation() ─→ PROCESSING (isAnimating=true, queue may have more)
  │                              │
  │                              ├─ animation completes ─→ check queue
  │                              │                              │
  │                              │                              ├─ queue empty → IDLE
  │                              │                              └─ queue not empty → PROCESSING
  │                              │
  │                              └─ cancelPendingAnimations() → IDLE
  │
  └─ enqueueAnimation() while not animating ─→ PROCESSING
```

---

## Testing

### Unit Tests

`NavigationBarBadgeAnimatorTests.swift` covers:

- Queue management (FIFO within priorities, no interruption)
- Priority sorting (high before low)
- Cancel logic (clears queue and current animation)
- Tab switch behavior (preserves same-tab animations)
- Auto-process flag control
- Delegate assignment (weak reference)

### Manual Testing Checklist

1. **Tracker Notification**
   - Navigate to site with trackers
   - Verify "X Trackers Blocked" notification appears
   - Verify shield animation plays after (HTTPS only)
   - Verify pluralization ("1 Tracker" vs "5 Trackers")

2. **Cookie Notification**
   - Navigate to European site with cookie consent
   - Verify "Cookies Managed" or "Pop-up Hidden" appears
   - Verify animation completes fully

3. **Combined Flow**
   - Navigate to European site with trackers AND cookie consent
   - Verify: Tracker notification → Shield animation → Cookie notification
   - Order matters: trackers first, cookies second

4. **Tab Switching**
   - Start animation on Tab A
   - Switch to Tab B
   - Verify Tab A's animation cancels
   - Switch back to Tab A
   - Verify no stale animations

5. **Focus Address Bar**
   - Start animation
   - Click in address bar (focus)
   - Verify visual animation stops but queue is preserved

---

## Debugging Tips

### Common Issues

1. **Cookie notification not showing after tracker**
   - Check that `processNextAnimation()` is called after shield animation
   - Verify `shouldAutoProcessNextAnimation` is set to `false` before tracker
   - Check queue is not being cleared by tab switch or URL change

2. **Animation not playing**
   - Check `isAnimating` state
   - Verify queue is not empty
   - Check that animation views are in view hierarchy

3. **Wrong animation type in delegate**
   - Ensure `currentAnimationType` is captured BEFORE clearing it
   - Verify delegate callback passes the captured type

### Removed Debug Logging

Debug logging was added during development and has been removed. If you need to debug, you can temporarily add:

```swift
import os.log
private let badgeLog = Logger(subsystem: "badge-animation", category: "queue")

// Then use:
badgeLog.debug("message")
```

Filter in Console.app with: `subsystem:badge-animation`

---

## iOS Parity

This implementation matches iOS behavior:

| Feature | iOS | macOS |
|---------|-----|-------|
| Priority queue | Yes | Yes |
| Trackers before cookies | Yes | Yes |
| Shield animation after trackers | Yes | Yes (HTTPS only) |
| Tab switch cancellation | Yes | Yes |
| Pluralization | Yes | Yes |

### Differences

- macOS uses Lottie for shield animation; iOS uses different animation system
- macOS has address bar focus handling (no equivalent on iOS)
- macOS buttons container fade; iOS has different UI structure

---

## Summary

The tracker animation feature provides visual feedback for privacy protection actions. The priority queue system ensures animations play in the correct order (trackers → shield → cookies) without overlapping. Tab switching and URL changes intelligently cancel/preserve animations. The delegate pattern allows the controller to coordinate shield animations with the queue system.

**Key architectural decisions:**
1. **Priority queue with sorting** - Ensures correct order regardless of when events fire
2. **Auto-process control** - Allows shield animation to play before next notification
3. **Tab-aware cancellation** - Prevents stale animations on tab switch
4. **Type-passing delegate** - Prevents type tracking bugs in the controller
