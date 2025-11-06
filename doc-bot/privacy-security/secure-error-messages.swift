// Don't expose sensitive information in errors
// Bad
throw NetworkError.authenticationFailed(username: user.email)

// Good
throw NetworkError.authenticationFailed

// Log securely
Logger.log(.error, "Authentication failed for user", 
          parameters: ["userId": user.anonymizedId])

