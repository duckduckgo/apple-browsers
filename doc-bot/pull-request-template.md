---
title: "Pull Request Template & Requirements"
description: "Guidelines for creating pull requests using the project template, ensuring all required information is provided"
keywords: ["pull request", "pr", "template", "PR template", "code review", "quality assurance", "testing", "engineering expectations"]
alwaysApply: false
---

# Pull Request Template & Requirements

## Overview
When creating pull requests, ALWAYS use the project's PR template and ensure all sections are properly filled out. This ensures code quality, proper review, and adherence to engineering standards.

## Required Information Checklist

### Before Opening a PR
```markdown
✅ Task/Issue URL - Link to the issue/task being addressed
✅ Tech Design URL - Link to technical design document (if applicable)
✅ CC - People who should be notified about this PR
✅ Description - Clear explanation of what was changed and why
✅ Testing Steps - Detailed steps for reviewer to test the changes
✅ Impact and Risks - Assessment of potential impact and mitigation strategies
✅ Quality Considerations - Edge cases, performance, monitoring, documentation
✅ Notes to Reviewer - Specific areas for reviewer focus
```

## Template Section Guidelines

### Task/Issue URL
```markdown
# ✅ REQUIRED - Always provide
Task/Issue URL: https://github.com/duckduckgo/browser/issues/123

# ❌ NEVER leave empty
Task/Issue URL: 
```

### Tech Design URL
```markdown
# ✅ REQUIRED for significant changes
Tech Design URL: https://docs.google.com/document/d/xyz

# ✅ ACCEPTABLE for minor changes
Tech Design URL: N/A - Minor bug fix
```

### CC (Carbon Copy)
```markdown
# ✅ REQUIRED - Include relevant stakeholders
CC: @username1, @username2, @team-name

# ✅ ACCEPTABLE if no specific people need notification
CC: N/A
```

### Description
```markdown
# ✅ REQUIRED - Comprehensive description
### Description
This PR implements the new subscription flow for iOS users. The changes include:
- New SubscriptionFlowViewModel with proper dependency injection
- Integration with BrowserServicesKit for subscription management
- SwiftUI views following the design system guidelines
- Comprehensive unit tests with >90% coverage

The implementation follows MVVM architecture and uses the AppDependencyProvider pattern.

# ❌ INSUFFICIENT - Too brief
### Description
Fixed subscription bug
```

### Testing Steps
```markdown
# ✅ REQUIRED - Detailed testing instructions
### Testing Steps
1. Open the iOS app in simulator
2. Navigate to Settings → Privacy Pro
3. Tap "Subscribe" button
4. Verify subscription flow opens correctly
5. Complete mock purchase flow
6. Verify subscription status updates in settings
7. Test with different device orientations (iPhone/iPad)
8. Verify analytics events are fired correctly

# ❌ INSUFFICIENT - Too vague
### Testing Steps
1. Test the subscription flow
2. Make sure it works
```

### Impact and Risks
```markdown
# ✅ REQUIRED - Proper risk assessment
### Impact and Risks
**Impact Level: Medium** - Could disrupt subscription purchase flow

#### What could go wrong?
- Purchase flow could fail silently, preventing users from subscribing
- Analytics events might not fire, affecting conversion tracking
- UI could break on different screen sizes

**Mitigation:**
- Comprehensive unit tests covering all purchase scenarios
- Manual testing on multiple device types
- Rollback plan: Feature flag to disable new flow
- Monitoring: Added analytics to track conversion funnel

# ❌ INSUFFICIENT - No risk assessment
### Impact and Risks
Should be fine.
```

## Impact Level Guidelines

### High Impact
```markdown
# Use for changes that could:
- Affect user privacy or security
- Cause data loss
- Break core functionality (browsing, search, content blocking)
- Affect subscription billing
- Impact performance significantly

Impact Level: High - Changes core content blocking logic
```

### Medium Impact
```markdown
# Use for changes that could:
- Disrupt specific features
- Affect user flows
- Change UI significantly
- Impact analytics/tracking

Impact Level: Medium - Updates subscription purchase flow
```

### Low Impact
```markdown
# Use for changes that:
- Fix minor bugs
- Make small UI adjustments
- Improve existing features
- Add non-critical features

Impact Level: Low - Minor UI color adjustment
```

### None Impact
```markdown
# Use for:
- Internal tooling changes
- Documentation updates
- Code refactoring without behavior changes
- Test improvements

Impact Level: None - Documentation update
```

## Quality Considerations Requirements

### Edge Cases
```markdown
# ✅ REQUIRED - Document edge cases considered
### Quality Considerations
**Edge Cases:**
- User with existing subscription attempts new purchase
- Network connectivity issues during purchase
- App backgrounded during purchase flow
- Multiple rapid taps on purchase button
- Device rotation during flow
```

### Performance Impact
```markdown
# ✅ REQUIRED for performance-affecting changes
**Performance:**
- Subscription check now cached for 5 minutes to reduce API calls
- Async operations properly handled to avoid blocking UI
- Memory usage tested with Instruments - no leaks detected
```

### Monitoring and Analytics
```markdown
# ✅ REQUIRED for user-facing changes
**Monitoring:**
- Added pixel events for subscription funnel tracking
- Error logging for failed purchase attempts
- Performance metrics for flow completion time
```

### Documentation Updates
```markdown
# ✅ REQUIRED when applicable
**Documentation:**
- Updated subscription architecture doc-bot rules
- Added code comments for complex subscription logic
- Updated README with new feature flag information
```

### Privacy and Security
```markdown
# ✅ REQUIRED for privacy/security changes
**Privacy/Security:**
- Subscription tokens stored securely in Keychain
- No PII logged in analytics events
- Purchase information handled according to privacy policy
```

## Agent PR Creation Protocol

### When User Requests PR Creation
```markdown
# ✅ REQUIRED - Ask for missing information
BEFORE creating PR, verify user has provided:

1. Issue/Task URL or description
2. What changes were made
3. How to test the changes
4. Impact assessment
5. Any special considerations

# If information is missing, ask specific questions:
- "What issue or task does this PR address?"
- "What specific changes did you make?"
- "How should I test these changes?"
- "What's the potential impact if something goes wrong?"
- "Are there any edge cases or performance considerations?"
```

### PR Creation Template
```markdown
When creating PR, use this structure:

Task/Issue URL: [USER_PROVIDED_URL]
Tech Design URL: [USER_PROVIDED_URL or "N/A"]
CC: [USER_PROVIDED_STAKEHOLDERS or "N/A"]

### Description
[USER_PROVIDED_DESCRIPTION]

### Testing Steps
[USER_PROVIDED_TESTING_STEPS]

### Impact and Risks
**Impact Level: [ASSESSED_LEVEL]**

#### What could go wrong?
[USER_PROVIDED_RISKS_OR_ASSESSED_RISKS]

### Quality Considerations
[USER_PROVIDED_QUALITY_CONSIDERATIONS]

### Notes to Reviewer
[USER_PROVIDED_NOTES]
```

## Common Scenarios and Examples

### Bug Fix PR
```markdown
Task/Issue URL: https://github.com/duckduckgo/browser/issues/456
Tech Design URL: N/A - Bug fix
CC: @ios-team

### Description
Fixed crash in subscription flow when user cancels purchase midway through.

Root cause: Force unwrapping of optional purchase result in SubscriptionFlowViewModel.
Solution: Added proper optional handling and error states.

### Testing Steps
1. Start subscription purchase flow
2. Cancel at payment sheet
3. Verify app doesn't crash
4. Verify UI shows appropriate error state
5. Verify user can retry purchase

### Impact and Risks
**Impact Level: High** - Prevents app crashes during subscription flow

#### What could go wrong?
- Error state might not display correctly
- User might be stuck in invalid state

**Mitigation:**
- Added comprehensive error handling
- Fallback to main subscription screen
- Analytics to track cancellation patterns

### Quality Considerations
**Edge Cases:**
- Multiple rapid cancellations
- Network loss during cancellation
- App backgrounded during cancellation

**Testing:**
- Unit tests for all cancellation scenarios
- Manual testing on multiple devices
```

### Feature Addition PR
```markdown
Task/Issue URL: https://github.com/duckduckgo/browser/issues/789
Tech Design URL: https://docs.google.com/document/d/feature-design
CC: @design-team, @product-team

### Description
Added free trial support for subscription purchases.

Changes include:
- New SubscriptionTrialManager with eligibility checking
- Updated UI to show trial information
- Server-side eligibility validation
- Analytics for trial conversion tracking

### Testing Steps
1. Open subscription flow as new user
2. Verify trial offer is displayed
3. Complete trial purchase
4. Verify subscription status shows trial
5. Test with existing subscriber (no trial shown)
6. Test with user who already used trial (no trial shown)

### Impact and Risks
**Impact Level: Medium** - New feature affecting purchase flow

#### What could go wrong?
- Trial eligibility check could fail
- User might not understand trial terms
- Analytics might not track conversions properly

**Mitigation:**
- Fallback to regular purchase if trial check fails
- Clear UI messaging about trial terms
- Comprehensive analytics implementation

### Quality Considerations
**Edge Cases:**
- Server eligibility check timeout
- User account state changes during flow
- Cross-platform trial synchronization

**Performance:**
- Eligibility check cached for user session
- Async operations don't block UI

**Documentation:**
- Updated subscription architecture guide
- Added trial feature flag documentation
```

This template ensures comprehensive PR information and maintains code quality standards. 