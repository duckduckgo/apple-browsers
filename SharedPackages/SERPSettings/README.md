# SERPSettings Package

Cross-platform SERP settings management for iOS and macOS.

## 📊 Architecture Diagrams

This package includes several visual diagrams to help understand the architecture:

### 1. **Main Architecture Diagram** (`ARCHITECTURE.mmd`)
Shows the overall package structure, dependencies, and platform integration.

### 2. **Message Flow Diagram** (`MESSAGE_FLOW.mmd`)
Illustrates the sequence of messages between WebView and native code.

### 3. **Class Diagram** (`CLASS_DIAGRAM.mmd`)
Displays class relationships, protocols, and implementations.

## 🖼️ How to View/Export Diagrams as Images

### Option 1: Mermaid Live Editor (Easiest)
1. Go to [https://mermaid.live](https://mermaid.live)
2. Copy the contents of any `.mmd` file
3. Paste into the editor
4. Click "Download PNG" or "Download SVG"

### Option 2: VS Code
1. Install extension: [Markdown Preview Mermaid Support](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid)
2. Open any `.mmd` file
3. Right-click → "Open Preview"
4. Use screenshot tool to capture

### Option 3: GitHub
1. Push the `.mmd` files to GitHub
2. View them directly on GitHub (auto-renders)
3. Use browser screenshot tools

### Option 4: Command Line (requires mermaid-cli)
```bash
# Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# Generate PNG
mmdc -i ARCHITECTURE.mmd -o architecture.png -b transparent

# Generate SVG
mmdc -i ARCHITECTURE.mmd -o architecture.svg

# Generate all diagrams
mmdc -i ARCHITECTURE.mmd -o architecture.png
mmdc -i MESSAGE_FLOW.mmd -o message-flow.png
mmdc -i CLASS_DIAGRAM.mmd -o class-diagram.png
```

### Option 5: Xcode/IntelliJ Plugins
- **Xcode**: Search for Mermaid preview plugins
- **IntelliJ**: Install "Mermaid" plugin from marketplace

## 📦 Package Overview

### Core Components

- **`SERPSettingsProviding`** - Protocol defining platform-specific behavior
- **`SERPSettingsUserScript`** - Shared UserScript integration
- **`SERPSettingsConstants`** - Shared constants
- **`SERPSettingsUserScriptMessages`** - Message type enumeration

### Dependencies

- **BrowserServicesKit**
  - Common
  - UserScript
  - Persistence  
  - PixelKit
- **AIChat**

### Platform Support

- iOS 15.0+
- macOS 11.4+

## 🚀 Usage

### iOS Integration

```swift
import SERPSettings

// 1. Implement SERPSettingsProviding
class iOSSERPSettings: SERPSettingsProviding {
    var isAIChatEnabled: Bool {
        // iOS-specific implementation
    }
    
    func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []
        if let ddgHost = URL.ddg.host {
            rules.append(.exact(hostname: ddgHost))
        }
        return rules
    }
    
    func isSERPSettingsFeatureOn() -> Bool {
        // Check iOS feature flags
    }
}

// 2. Implement delegate
class iOSSERPDelegate: SERPSettingsUserScriptDelegate {
    func serpSettingsUserScriptDidRequestToCloseTabAndOpenPrivacySettings(_ userScript: SERPSettingsUserScript) {
        // Navigate to privacy settings
    }
    
    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript) {
        // Navigate to AI features settings
    }
}

// 3. Create and configure UserScript
let settings = iOSSERPSettings()
let userScript = SERPSettingsUserScript(serpSettingsProviding: settings)
userScript.delegate = iOSSERPDelegate()
```

### macOS Integration

```swift
import SERPSettings

// 1. Implement SERPSettingsProviding
class macOSSERPSettings: SERPSettingsProviding {
    var isAIChatEnabled: Bool {
        // macOS-specific implementation
    }
    
    func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []
        if let ddgHost = URL.duckDuckGo.host {
            rules.append(.exact(hostname: ddgHost))
        }
        return rules
    }
    
    func isSERPSettingsFeatureOn() -> Bool {
        // Check macOS feature flags
    }
}

// 2. Implement delegate
class macOSSERPDelegate: SERPSettingsUserScriptDelegate {
    func serpSettingsUserScriptDidRequestToCloseTabAndOpenPrivacySettings(_ userScript: SERPSettingsUserScript) {
        // Open preferences window to privacy
    }
    
    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript) {
        // Open preferences window to AI features
    }
}

// 3. Create and configure UserScript
let settings = macOSSERPSettings()
let userScript = SERPSettingsUserScript(serpSettingsProviding: settings)
userScript.delegate = macOSSERPDelegate()
```

## 🧪 Testing

```swift
import XCTest
@testable import SERPSettings

class SERPSettingsTests: XCTestCase {
    // Test implementation
}
```

## 📝 Documentation

For detailed architecture information, see [ARCHITECTURE.md](ARCHITECTURE.md).

## 🔄 Message Types

### `openNativeSettings`
Opens platform-specific settings screen.

**Parameters:**
- `return`: `"privateSearch"` or `"aiFeatures"`
- `screen`: `"aiFeatures"` (alternative parameter)

### `getNativeSettings`
Retrieves current settings state.

**Returns:** Settings snapshot or `nil` if feature disabled

### `updateNativeSettings`
Updates settings from WebView.

**Parameters:** Settings object to update

### `nativeSettingsDidChange`
Pushed from native to WebView when settings change.

## 📄 License

Copyright © 2025 DuckDuckGo. All rights reserved.

Licensed under the Apache License, Version 2.0.


