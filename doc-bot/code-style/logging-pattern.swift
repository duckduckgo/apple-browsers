import os

// ✅ CORRECT: Unified logging
private let logger = Logger(subsystem: "com.duckduckgo.browser", category: "FeatureManager")

func performAction() {
    logger.debug("Starting action with parameter: \(parameter, privacy: .public)")
    
    // Perform action...
    
    if success {
        logger.info("Action completed successfully")
    } else {
        logger.error("Action failed: \(error.localizedDescription, privacy: .public)")
    }
}

