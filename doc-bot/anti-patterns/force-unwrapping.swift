// ❌ AVOID - Force unwrapping
func processUser() {
    let user = getCurrentUser()!  // Will crash if no user
    let name = user.name!         // Will crash if no name
    displayName(name)
}

// ✅ CORRECT - Safe unwrapping
func processUser() {
    guard let user = getCurrentUser(),
          let name = user.name else {
        showErrorMessage("User information unavailable")
        return
    }
    displayName(name)
}

