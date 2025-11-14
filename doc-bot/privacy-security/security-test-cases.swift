func testSensitiveDataNotLogged() {
    let password = "secret123"
    authenticator.login(password: password)
    
    XCTAssertFalse(logOutput.contains(password))
}

func testDataEncryption() {
    let sensitiveData = "user information"
    let encrypted = encryptor.encrypt(sensitiveData)
    
    XCTAssertNotEqual(encrypted, sensitiveData)
    XCTAssertEqual(encryptor.decrypt(encrypted), sensitiveData)
}

