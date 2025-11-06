// Never store passwords in plain text
// Use AutofillCredentialProvider for password management
let credential = ASPasswordCredential(user: username, password: password)
ASCredentialIdentityStore.shared.saveCredentialIdentities([credential])

