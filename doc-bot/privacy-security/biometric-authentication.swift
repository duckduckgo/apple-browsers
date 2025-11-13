// Use LocalAuthentication for sensitive operations
let context = LAContext()
context.evaluatePolicy(.deviceOwnerAuthentication, 
                      localizedReason: "Authenticate to access your passwords") { success, error in
    if success {
        // Grant access
    } else {
        // Handle authentication failure
    }
}

