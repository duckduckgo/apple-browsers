// Use Keychain for sensitive data
let keychainService = KeychainService()
try keychainService.store(password, for: account)

// Use encrypted Core Data for sensitive persistent data
let container = NSPersistentContainer(name: "SecureData")
container.persistentStoreDescriptions.forEach { storeDescription in
    storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    storeDescription.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
}

