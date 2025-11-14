import os.log

✅ // GOOD: Use Logger extensions for different contexts
Logger.general.debug("Service state changed: \(newState)")
Logger.network.info("HTTP request completed: \(response.statusCode)")
Logger.ui.debug("View layout updated with \(items.count) items")

❌ // BAD: Using print() statements
print("Service state changed")  // Never use print()
print("DEBUG: \(someValue)")    // Use Logger.debug() instead

