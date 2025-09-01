---
alwaysApply: false
title: "Maestro Test Device Selection (iPhone/iPad)"
description: "Documentation for Maestro test device selection feature that allows tests to run on iPhone or iPad based on tags"
keywords: ["maestro", "testing", "ui-tests", "ipad", "iphone", "simulator", "device-selection", "tags"]
---

# Maestro Test Device Selection (iPhone/iPad)

## Overview
Maestro tests can run on either iPhone or iPad simulators based on tags in the test YAML files. This allows you to test iPad-specific UI layouts and features while maintaining a single test suite.

## How It Works
- **Default**: Tests run on iPhone 16 with iOS 18.2
- **iPad Tests**: Add `ipad` tag to run on iPad 10th generation with iOS 18.2

## Usage

### For Individual iPad Tests
Add the `ipad` tag to your test file:

```yaml
appId: com.duckduckgo.mobile.ios
tags:
    - ipad
    - your-other-tags
name: Your iPad Test

---
# Your test steps here
```

### Running Tests
The same commands work as before:
```bash
# Run a single test (device selected based on tags)
./run_ui_tests.sh path/to/test.yaml

# Run all tests in a folder (each test runs on appropriate device)
./run_ui_tests.sh path/to/tests/
```

## Implementation Details

### Setup Phase (`setup_ui_tests.sh`)
1. Creates both iPhone and iPad simulators upfront
2. Boots and configures both simulators with English locale
3. Installs the app on both devices
4. Saves both simulator UUIDs for test execution

### Test Execution (`run_ui_tests.sh`)
1. Opens Simulator app if not already running
2. Checks each test file for the `ipad` tag using grep
3. Boots the required simulator if it's not already running
4. Uses the pre-created simulator based on the tag
5. Reinstalls the app before each test for clean state
6. Reports which device type was used in test results

## Simulator Specifications
- **iPhone**: iPhone 16, iOS 18.2  
- **iPad**: iPad (10th generation), iOS 18.2

Both simulators are configured with:
- Language: English (en)
- Locale: en_US
- Name suffix: "(maestro)" for easy identification

## Example Test Structure
```yaml
appId: com.duckduckgo.mobile.ios
tags:
    - ipad
    - duckplayer
name: DuckPlayer iPad Layout Test

---
# This test will automatically run on iPad simulator

- runFlow: 
    file: ../shared/setup.yaml

# Test iPad-specific UI elements
- assertVisible: "Split View"  # Example iPad-specific element
```

## Technical Implementation

### Tag Detection Function
The script uses awk to detect the 'ipad' tag:
```bash
check_for_ipad_tag() {
    local test_file=$1
    
    # Check if the test has an 'ipad' tag
    if awk '/^tags:/{flag=1} flag && /^[^-]/{exit} flag && /- ipad/{found=1; exit} END{exit !found}' "$test_file" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}
```

### Pre-created Simulators
Both simulators are created during setup for better performance:
```bash
# In setup_ui_tests.sh
create_or_get_simulator() {
    local device_name=$1
    local device_type=$2
    local simulator_name="$device_name $target_os (maestro)"
    # Creates simulator if it doesn't exist
    # Returns simulator UUID
}

# Creates both simulators
iphone_uuid=$(create_or_get_simulator "iPhone-16" "iPhone-16")
ipad_uuid=$(create_or_get_simulator "iPad-10th-generation" "iPad-10th-generation")
```

### Simulator UUID Storage
UUIDs are saved to files for test execution:
- iPhone UUID: `DerivedData/device_uuid.txt`
- iPad UUID: `DerivedData/device_uuid_ipad.txt`

## Benefits
- **Single Test Suite**: Maintain one set of tests for both device types
- **Automatic Selection**: No need to manually switch simulators
- **Efficient Testing**: Only creates simulators when needed
- **Clear Indication**: Test output shows which device type is being used

## Future Enhancements
- Support for additional iPad models
- Different iOS versions per device type
- Landscape/portrait orientation configuration
- Device-specific timeout adjustments