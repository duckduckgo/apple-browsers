//
//  OSStatus+HumanReadableDescription.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
// AI Generated 🤖

import Foundation

public extension OSStatus {

    var humanReadableDescription: String {
        switch self {
        // Security Framework - General
        case errSecSuccess:
            return "Success"
        case errSecUnimplemented:
            return "Function or operation not implemented"
        case errSecParam:
            return "One or more parameters passed to the function were not valid"
        case errSecAllocate:
            return "Failed to allocate memory"
        case errSecNotAvailable:
            return "Keychain not available"
        case errSecReadOnly:
            return "Read only error"
        case errSecAuthFailed:
            return "Authorization/Authentication failed"
        case errSecNoSuchKeychain:
            return "The keychain does not exist"
        case errSecInvalidKeychain:
            return "The keychain is not valid"
        case errSecDuplicateKeychain:
            return "A keychain with the same name already exists"
        case errSecDuplicateCallback:
            return "More than one callback of the same name exists"
        case errSecInvalidCallback:
            return "The callback is not valid"

        // Keychain Item Errors
        case errSecDuplicateItem:
            return "The item already exists"
        case errSecItemNotFound:
            return "The item cannot be found"
        case errSecInteractionNotAllowed:
            return "Interaction with the Security Server is not allowed"
        case errSecNoDefaultKeychain:
            return "A default keychain does not exist"
        case errSecReadOnlyAttr:
            return "The attribute is read only"
        case errSecWrongSecVersion:
            return "The version is incorrect"
        case errSecKeySizeNotAllowed:
            return "The key size is not allowed"
        case errSecNoStorageModule:
            return "No storage module available"
        case errSecNoCertificateModule:
            return "No certificate module available"
        case errSecNoPolicyModule:
            return "No policy module available"
        case errSecInteractionRequired:
            return "User interaction is required"
        case errSecDataNotAvailable:
            return "The data is not available"
        case errSecDataNotModifiable:
            return "The data is not modifiable"
        case errSecCreateChainFailed:
            return "The attempt to create a certificate chain failed"
        case errSecInvalidPrefsDomain:
            return "The preference domain specified is invalid"
        case errSecInDarkWake:
            return "The user interface cannot be displayed because the system is in a dark wake state"

        // Access Control and Authentication
        case errSecUserCanceled:
            return "User cancelled the operation"
        case errSecMissingEntitlement:
            return "A required entitlement isn't present"
        case errSecRestrictedAPI:
            return "This API is restricted"
        case errSecNotTrusted:
            return "The certificate or key is not trusted"
        case errSecNoAccessForItem:
            return "The specified item has no access control"
        case errSecInvalidOwnerEdit:
            return "Invalid attempt to change the owner of this item"
        case errSecTrustNotAvailable:
            return "No trust results are available"
        case errSecUnsupportedFormat:
            return "The item you are trying to import has an unsupported format"
        case errSecUnknownFormat:
            return "The item you are trying to import has an unknown format"
        case errSecKeyIsSensitive:
            return "The key is sensitive and cannot be extracted"
        case errSecMultiplePrivKeys:
            return "An attempt was made to import multiple private keys"
        case errSecPassphraseRequired:
            return "Passphrase is required for import/export"
        case errSecInvalidPasswordRef:
            return "The password reference was invalid"
        case errSecInvalidTrustSettings:
            return "The Trust Settings Record was corrupted"
        case errSecNoTrustSettings:
            return "No Trust Settings were found"
        case errSecPkcs12VerifyFailure:
            return "MAC verification failed during PKCS12 import"
        case errSecNotSigner:
            return "A certificate was not signed by its proposed parent"
        case errSecServiceNotAvailable:
            return "The required service is not available"
        case errSecInsufficientClientID:
            return "The client ID is not correct"
        case errSecDeviceReset:
            return "A device reset has occurred"
        case errSecDeviceFailed:
            return "A device failure has occurred"
        case errSecAppleAddAppACLSubject:
            return "Adding an application ACL subject failed"
        case errSecApplePublicKeyIncomplete:
            return "The public key is incomplete"
        case errSecAppleSignatureMismatch:
            return "A signature mismatch has occurred"
        case errSecAppleInvalidKeyStartDate:
            return "The key start date is invalid"
        case errSecAppleInvalidKeyEndDate:
            return "The key end date is invalid"
        case errSecConversionError:
            return "A conversion error has occurred"
        case errSecAppleSSLv2Rollback:
            return "A SSLv2 rollback error has occurred"
        case errSecQuotaExceeded:
            return "The quota was exceeded"
        case errSecFileTooBig:
            return "The file is too big"
        case errSecInvalidDatabaseBlob:
            return "The database blob is invalid"
        case errSecInvalidKeyBlob:
            return "The key blob is invalid"
        case errSecIncompatibleDatabaseBlob:
            return "The database blob is incompatible"
        case errSecIncompatibleKeyBlob:
            return "The key blob is incompatible"
        case errSecHostNameMismatch:
            return "A host name mismatch has occurred"
        case errSecUnknownCriticalExtensionFlag:
            return "There is an unknown critical extension flag"
        case errSecNoBasicConstraints:
            return "No basic constraints were found"
        case errSecNoBasicConstraintsCA:
            return "No basic CA constraints were found"
        case errSecInvalidAuthorityKeyID:
            return "The authority key ID is invalid"
        case errSecInvalidSubjectKeyID:
            return "The subject key ID is invalid"
        case errSecInvalidKeyUsageForPolicy:
            return "The key usage is invalid for the specified policy"
        case errSecInvalidExtendedKeyUsage:
            return "The extended key usage is invalid"
        case errSecInvalidIDLinkage:
            return "The ID linkage is invalid"
        case errSecPathLengthConstraintExceeded:
            return "The path length constraint was exceeded"
        case errSecInvalidRoot:
            return "The root or anchor certificate is invalid"
        case errSecCRLExpired:
            return "The CRL has expired"
        case errSecCRLNotValidYet:
            return "The CRL is not yet valid"
        case errSecCRLNotFound:
            return "The CRL was not found"
        case errSecCRLServerDown:
            return "The CRL server is down"
        case errSecCRLBadURI:
            return "The CRL has a bad Uniform Resource Identifier"
        case errSecUnknownCertExtension:
            return "An unknown certificate extension was encountered"
        case errSecUnknownCRLExtension:
            return "An unknown CRL extension was encountered"
        case errSecCRLNotTrusted:
            return "The CRL is not trusted"
        case errSecCRLPolicyFailed:
            return "The CRL policy failed"
        case errSecIDPFailure:
            return "The issuing distribution point was not valid"
        case errSecSMIMEEmailAddressesNotFound:
            return "An email address mismatch was encountered"
        case errSecSMIMEBadExtendedKeyUsage:
            return "The appropriate extended key usage for SMIME was not found"
        case errSecSMIMEBadKeyUsage:
            return "The key usage is not compatible with SMIME"
        case errSecSMIMEKeyUsageNotCritical:
            return "The key usage extension is not marked as critical"
        case errSecSMIMENoEmailAddress:
            return "No email address was found in the certificate"
        case errSecSMIMESubjAltNameNotCritical:
            return "The subject alternative name extension is not marked as critical"
        case errSecSSLBadExtendedKeyUsage:
            return "The appropriate extended key usage for SSL was not found"
        case errSecOCSPBadResponse:
            return "The OCSP response was incorrect or could not be parsed"
        case errSecOCSPBadRequest:
            return "The OCSP request was incorrect or could not be parsed"
        case errSecOCSPUnavailable:
            return "OCSP service is unavailable"
        case errSecOCSPStatusUnrecognized:
            return "The OCSP server did not recognize this certificate"
        case errSecEndOfData:
            return "An end-of-data was detected"
        case errSecIncompleteCertRevocationCheck:
            return "An incomplete certificate revocation check occurred"
        case errSecNetworkFailure:
            return "A network failure occurred"
        case errSecOCSPNotTrustedToAnchor:
            return "The OCSP response was not trusted to a root or anchor certificate"
        case errSecRecordModified:
            return "The record was modified"
        case errSecOCSPSignatureError:
            return "The OCSP response had an invalid signature"
        case errSecOCSPNoSigner:
            return "The OCSP response had no signer"
        case errSecOCSPResponderMalformedReq:
            return "The OCSP responder was given a malformed request"
        case errSecOCSPResponderInternalError:
            return "The OCSP responder encountered an internal error"
        case errSecOCSPResponderTryLater:
            return "The OCSP responder is busy, try again later"
        case errSecOCSPResponderSignatureRequired:
            return "The OCSP responder requires a signature"
        case errSecOCSPResponderUnauthorized:
            return "The OCSP responder rejected this request as unauthorized"
        case errSecOCSPResponseNonceMismatch:
            return "The OCSP response nonce did not match the request"
        case errSecCodeSigningBadCertChainLength:
            return "Code signing encountered an incorrect certificate chain length"
        case errSecCodeSigningNoBasicConstraints:
            return "Code signing found no basic constraints"
        case errSecCodeSigningBadPathLengthConstraint:
            return "Code signing encountered an incorrect path length constraint"
        case errSecCodeSigningNoExtendedKeyUsage:
            return "Code signing found no extended key usage"
        case errSecCodeSigningDevelopment:
            return "Code signing indicated use of a development-only certificate"
        case errSecResourceSignBadCertChainLength:
            return "Resource signing has encountered an incorrect certificate chain length"
        case errSecResourceSignBadExtKeyUsage:
            return "Resource signing has encountered an error in the extended key usage"
        case errSecTrustSettingDeny:
            return "The trust setting for this policy was set to Deny"
        case errSecInvalidSubjectName:
            return "An invalid certificate subject name was encountered"
        case errSecUnknownQualifiedCertStatement:
            return "An unknown qualified certificate statement was encountered"
        case errSecMobileMeRequestQueued:
            return "The MobileMe request will be sent during the next connection"
        case errSecMobileMeRequestRedirected:
            return "The MobileMe request was redirected"
        case errSecMobileMeServerError:
            return "A MobileMe server error occurred"
        case errSecMobileMeServerNotAvailable:
            return "The MobileMe server is not available"
        case errSecMobileMeServerAlreadyExists:
            return "The MobileMe server reported that the item already exists"
        case errSecMobileMeServerServiceErr:
            return "A MobileMe service error has occurred"
        case errSecMobileMeRequestAlreadyPending:
            return "A MobileMe request is already pending"
        case errSecMobileMeNoRequestPending:
            return "MobileMe has no request pending"
        case errSecMobileMeCSRVerifyFailure:
            return "A MobileMe CSR verification failure has occurred"
        case errSecMobileMeFailedConsistencyCheck:
            return "MobileMe has found a failed consistency check"
        case errSecNotInitialized:
            return "A function was called without initializing CSSM"
        case errSecInvalidHandleUsage:
            return "The CSSM handle does not match with the service type"
        case errSecPVCReferentNotFound:
            return "A reference to the calling module was not found in the list of authorized callers"
        case errSecFunctionIntegrityFail:
            return "A function address was not within the verified module"
        case errSecInternalError:
            return "An internal error has occurred"
        case errSecMemoryError:
            return "A memory error has occurred"
        case errSecInvalidData:
            return "Invalid data was encountered"
        case errSecMDSError:
            return "A Module Directory Service error has occurred"
        case errSecInvalidPointer:
            return "An invalid pointer was encountered"
        case errSecSelfCheckFailed:
            return "Self-check has failed"
        case errSecFunctionFailed:
            return "A function has failed"
        case errSecModuleManifestVerifyFailed:
            return "A module manifest verification failure has occurred"
        case errSecInvalidGUID:
            return "An invalid GUID was encountered"
        case errSecInvalidHandle:
            return "An invalid handle was encountered"
        case errSecInvalidDBList:
            return "An invalid DB list was encountered"
        case errSecInvalidPassthroughID:
            return "An invalid passthrough ID was encountered"
        case errSecInvalidNetworkAddress:
            return "An invalid network address was encountered"
        case errSecCRLAlreadySigned:
            return "The certificate revocation list is already signed"
        case errSecInvalidNumberOfFields:
            return "An invalid number of fields were encountered"
        case errSecVerificationFailure:
            return "A verification failure occurred"
        case errSecUnknownTag:
            return "An unknown tag was encountered"
        case errSecInvalidSignature:
            return "An invalid signature was encountered"
        case errSecInvalidName:
            return "An invalid name was encountered"
        case errSecInvalidCertificateRef:
            return "An invalid certificate reference was encountered"
        case errSecInvalidCertificateGroup:
            return "An invalid certificate group was encountered"
        case errSecTagNotFound:
            return "The specified tag was not found"
        case errSecInvalidQuery:
            return "The specified query was not valid"
        case errSecInvalidValue:
            return "An invalid value was detected"
        case errSecCallbackFailed:
            return "A callback has failed"
        case errSecACLDeleteFailed:
            return "An ACL delete operation has failed"
        case errSecACLReplaceFailed:
            return "An ACL replace operation has failed"
        case errSecACLAddFailed:
            return "An ACL add operation has failed"
        case errSecACLChangeFailed:
            return "An ACL change operation has failed"
        case errSecInvalidAccessCredentials:
            return "Invalid access credentials were encountered"
        case errSecInvalidRecord:
            return "An invalid record was encountered"
        case errSecInvalidACL:
            return "An invalid ACL was encountered"
        case errSecInvalidSampleValue:
            return "An invalid sample value was encountered"
        case errSecIncompatibleVersion:
            return "An incompatible version was encountered"
        case errSecPrivilegeNotGranted:
            return "The privilege was not granted"
        case errSecInvalidScope:
            return "An invalid scope was encountered"
        case errSecPVCAlreadyConfigured:
            return "The PVC is already configured"
        case errSecInvalidPVC:
            return "An invalid PVC was encountered"
        case errSecEMMLoadFailed:
            return "The EMM load has failed"
        case errSecEMMUnloadFailed:
            return "The EMM unload has failed"
        case errSecAddinLoadFailed:
            return "The add-in load operation has failed"
        case errSecInvalidKeyRef:
            return "An invalid key was encountered"
        case errSecInvalidKeyHierarchy:
            return "An invalid key hierarchy was encountered"
        case errSecAddinUnloadFailed:
            return "The add-in unload operation has failed"
        case errSecLibraryReferenceNotFound:
            return "A library reference was not found"
        case errSecInvalidAddinFunctionTable:
            return "An invalid add-in function table was encountered"
        case errSecInvalidServiceMask:
            return "An invalid service mask was encountered"
        case errSecModuleNotLoaded:
            return "A module was not loaded"
        case errSecInvalidSubServiceID:
            return "An invalid subservice ID was encountered"
        case errSecInvalidContext:
            return "An invalid context was encountered"
        case errSecInvalidAlgorithm:
            return "An invalid algorithm was encountered"
        case errSecInvalidAttributeKey:
            return "A key attribute was not valid"
        case errSecMissingAttributeKey:
            return "A key attribute was missing"
        case errSecInvalidAttributeInitVector:
            return "An init vector attribute was not valid"
        case errSecMissingAttributeInitVector:
            return "An init vector attribute was missing"
        case errSecInvalidAttributeSalt:
            return "A salt attribute was not valid"
        case errSecMissingAttributeSalt:
            return "A salt attribute was missing"
        case errSecInvalidAttributePadding:
            return "A padding attribute was not valid"
        case errSecMissingAttributePadding:
            return "A padding attribute was missing"
        case errSecInvalidAttributeRandom:
            return "A random number attribute was not valid"
        case errSecMissingAttributeRandom:
            return "A random number attribute was missing"
        case errSecInvalidAttributeSeed:
            return "A seed attribute was not valid"
        case errSecMissingAttributeSeed:
            return "A seed attribute was missing"
        case errSecInvalidAttributePassphrase:
            return "A passphrase attribute was not valid"
        case errSecMissingAttributePassphrase:
            return "A passphrase attribute was missing"
        case errSecInvalidAttributeKeyLength:
            return "A key length attribute was not valid"
        case errSecMissingAttributeKeyLength:
            return "A key length attribute was missing"
        case errSecInvalidAttributeBlockSize:
            return "A block size attribute was not valid"
        case errSecMissingAttributeBlockSize:
            return "A block size attribute was missing"
        case errSecInvalidAttributeOutputSize:
            return "An output size attribute was not valid"
        case errSecMissingAttributeOutputSize:
            return "An output size attribute was missing"
        case errSecInvalidAttributeRounds:
            return "The number of rounds attribute was not valid"
        case errSecMissingAttributeRounds:
            return "The number of rounds attribute was missing"
        case errSecInvalidAlgorithmParms:
            return "An algorithm parameters attribute was not valid"
        case errSecMissingAlgorithmParms:
            return "An algorithm parameters attribute was missing"
        case errSecInvalidAttributeLabel:
            return "A label attribute was not valid"
        case errSecMissingAttributeLabel:
            return "A label attribute was missing"
        case errSecInvalidAttributeKeyType:
            return "A key type attribute was not valid"
        case errSecMissingAttributeKeyType:
            return "A key type attribute was missing"
        case errSecInvalidAttributeMode:
            return "A mode attribute was not valid"
        case errSecMissingAttributeMode:
            return "A mode attribute was missing"
        case errSecInvalidAttributeEffectiveBits:
            return "An effective bits attribute was not valid"
        case errSecMissingAttributeEffectiveBits:
            return "An effective bits attribute was missing"
        case errSecInvalidAttributeStartDate:
            return "A start date attribute was not valid"
        case errSecMissingAttributeStartDate:
            return "A start date attribute was missing"
        case errSecInvalidAttributeEndDate:
            return "An end date attribute was not valid"
        case errSecMissingAttributeEndDate:
            return "An end date attribute was missing"
        case errSecInvalidAttributeVersion:
            return "A version attribute was not valid"
        case errSecMissingAttributeVersion:
            return "A version attribute was missing"
        case errSecInvalidAttributePrime:
            return "A prime attribute was not valid"
        case errSecMissingAttributePrime:
            return "A prime attribute was missing"
        case errSecInvalidAttributeBase:
            return "A base attribute was not valid"
        case errSecMissingAttributeBase:
            return "A base attribute was missing"
        case errSecInvalidAttributeSubprime:
            return "A subprime attribute was not valid"
        case errSecMissingAttributeSubprime:
            return "A subprime attribute was missing"
        case errSecInvalidAttributeIterationCount:
            return "An iteration count attribute was not valid"
        case errSecMissingAttributeIterationCount:
            return "An iteration count attribute was missing"
        case errSecInvalidAttributeDLDBHandle:
            return "A database handle attribute was not valid"
        case errSecMissingAttributeDLDBHandle:
            return "A database handle attribute was missing"
        case errSecInvalidAttributeAccessCredentials:
            return "An access credentials attribute was not valid"
        case errSecMissingAttributeAccessCredentials:
            return "An access credentials attribute was missing"
        case errSecInvalidAttributePublicKeyFormat:
            return "A public key format attribute was not valid"
        case errSecMissingAttributePublicKeyFormat:
            return "A public key format attribute was missing"
        case errSecInvalidAttributePrivateKeyFormat:
            return "A private key format attribute was not valid"
        case errSecMissingAttributePrivateKeyFormat:
            return "A private key format attribute was missing"
        case errSecInvalidAttributeSymmetricKeyFormat:
            return "A symmetric key format attribute was not valid"
        case errSecMissingAttributeSymmetricKeyFormat:
            return "A symmetric key format attribute was missing"
        case errSecInvalidAttributeWrappedKeyFormat:
            return "A wrapped key format attribute was not valid"
        case errSecMissingAttributeWrappedKeyFormat:
            return "A wrapped key format attribute was missing"
        case errSecStagedOperationInProgress:
            return "A staged operation is in progress"
        case errSecStagedOperationNotStarted:
            return "A staged operation was not started"
        case errSecVerifyFailed:
            return "A cryptographic verification failure has occurred"
        case errSecQuerySizeUnknown:
            return "The query size is unknown"
        case errSecBlockSizeMismatch:
            return "A block size mismatch occurred"
        case errSecPublicKeyInconsistent:
            return "The public key was inconsistent"
        case errSecDeviceVerifyFailed:
            return "A device verification failure has occurred"
        case errSecInvalidLoginName:
            return "An invalid login name was detected"
        case errSecAlreadyLoggedIn:
            return "The user is already logged in"
        case errSecInvalidDigestAlgorithm:
            return "An invalid digest algorithm was detected"
        case errSecInvalidCRLGroup:
            return "An invalid CRL group was detected"
        case errSecCertificateCannotOperate:
            return "The certificate cannot operate"
        case errSecCertificateExpired:
            return "An expired certificate was detected"
        case errSecCertificateNotValidYet:
            return "The certificate is not yet valid"
        case errSecCertificateRevoked:
            return "The certificate was revoked"
        case errSecCertificateSuspended:
            return "The certificate was suspended"
        case errSecInsufficientCredentials:
            return "Insufficient credentials were detected"
        case errSecInvalidAction:
            return "The action was not valid"
        case errSecInvalidAuthority:
            return "The authority was not valid"
        case errSecVerifyActionFailed:
            return "A verify action has failed"
        case errSecInvalidCertAuthority:
            return "The certificate authority was not valid"
        case errSecInvalidCRLAuthority:
            return "The CRL authority was not valid"
        case errSecInvalidCRLEncoding:
            return "The CRL encoding was not valid"
        case errSecInvalidCRLType:
            return "The CRL type was not valid"
        case errSecInvalidCRL:
            return "The CRL was not valid"
        case errSecInvalidFormType:
            return "The form type was not valid"
        case errSecInvalidID:
            return "The ID was not valid"
        case errSecInvalidIdentifier:
            return "The identifier was not valid"
        case errSecInvalidIndex:
            return "The index was not valid"
        case errSecInvalidPolicyIdentifiers:
            return "The policy identifiers are not valid"
        case errSecInvalidTimeString:
            return "The time specified was not valid"
        case errSecInvalidReason:
            return "The trust policy reason was not valid"
        case errSecInvalidRequestInputs:
            return "The request inputs are not valid"
        case errSecInvalidResponseVector:
            return "The response vector was not valid"
        case errSecInvalidStopOnPolicy:
            return "The stop-on policy was not valid"
        case errSecInvalidTuple:
            return "The tuple was not valid"
        case errSecMultipleValuesUnsupported:
            return "Multiple values are not supported"
        case errSecNoDefaultAuthority:
            return "No default authority was detected"
        case errSecRejectedForm:
            return "The trust policy had a rejected form"
        case errSecRequestLost:
            return "The request was lost"
        case errSecRequestRejected:
            return "The request was rejected"
        case errSecUnsupportedAddressType:
            return "The address type is not supported"
        case errSecUnsupportedService:
            return "The service is not supported"
        case errSecInvalidTupleGroup:
            return "The tuple group was not valid"
        case errSecInvalidBaseACLs:
            return "The base ACLs are not valid"
        case errSecInvalidTupleCredentials:
            return "The tuple credentials are not valid"
        case errSecInvalidEncoding:
            return "The encoding was not valid"
        case errSecInvalidValidityPeriod:
            return "The validity period was not valid"
        case errSecInvalidRequestor:
            return "The requestor was not valid"
        case errSecRequestDescriptor:
            return "The request descriptor was not valid"
        case errSecInvalidBundleInfo:
            return "The bundle information was not valid"
        case errSecInvalidCRLIndex:
            return "The CRL index was not valid"
        case errSecNoFieldValues:
            return "No field values were detected"
        case errSecUnsupportedFieldFormat:
            return "The field format is not supported"
        case errSecUnsupportedIndexInfo:
            return "The index information is not supported"
        case errSecUnsupportedLocality:
            return "The locality is not supported"
        case errSecUnsupportedNumAttributes:
            return "The number of attributes is not supported"
        case errSecUnsupportedNumIndexes:
            return "The number of indexes is not supported"
        case errSecUnsupportedNumRecordTypes:
            return "The number of record types is not supported"
        case errSecFieldSpecifiedMultiple:
            return "Too many fields were specified"
        case errSecIncompatibleFieldFormat:
            return "The field format was incompatible"
        case errSecInvalidParsingModule:
            return "The parsing module was not valid"
        case errSecDatabaseLocked:
            return "The database is locked"
        case errSecDatastoreIsOpen:
            return "The data store is open"
        case errSecMissingValue:
            return "A missing value was detected"
        case errSecUnsupportedQueryLimits:
            return "The query limits are not supported"
        case errSecUnsupportedNumSelectionPreds:
            return "The number of selection predicates is not supported"
        case errSecUnsupportedOperator:
            return "The operator is not supported"
        case errSecInvalidDBLocation:
            return "The database location is not valid"
        case errSecInvalidAccessRequest:
            return "The access request is not valid"
        case errSecInvalidIndexInfo:
            return "The index information is not valid"
        case errSecInvalidNewOwner:
            return "The new owner is not valid"
        case errSecInvalidModifyMode:
            return "The modify mode is not valid"
        case errSecMissingRequiredExtension:
            return "A required certificate extension is missing"
        case errSecExtendedKeyUsageNotCritical:
            return "The extended key usage extension was not marked as critical"
        case errSecTimestampMissing:
            return "A timestamp was expected but was not found"
        case errSecTimestampInvalid:
            return "The timestamp was not valid"
        case errSecTimestampNotTrusted:
            return "The timestamp was not trusted"
        case errSecTimestampServiceNotAvailable:
            return "The timestamp service is not available"
        case errSecTimestampBadAlg:
            return "An unrecognized or unsupported Algorithm Identifier in timestamp"
        case errSecTimestampBadRequest:
            return "The timestamp transaction is not permitted or supported"
        case errSecTimestampBadDataFormat:
            return "The timestamp data submitted has the wrong format"
        case errSecTimestampTimeNotAvailable:
            return "The time source for the Timestamp Authority is not available"
        case errSecTimestampUnacceptedPolicy:
            return "The requested policy is not supported by the Timestamp Authority"
        case errSecTimestampUnacceptedExtension:
            return "The requested extension is not supported by the Timestamp Authority"
        case errSecTimestampAddInfoNotAvailable:
            return "The additional information requested is not available"
        case errSecTimestampSystemFailure:
            return "The timestamp request cannot be handled due to system failure"
        case errSecSigningTimeMissing:
            return "A signing time was expected but was not found"
        case errSecTimestampRejection:
            return "A timestamp transaction was rejected"
        case errSecTimestampWaiting:
            return "A timestamp transaction is waiting"
        case errSecTimestampRevocationWarning:
            return "A timestamp authority revocation warning was issued"
        case errSecTimestampRevocationNotification:
            return "A timestamp authority revocation notification was issued"

        // Common system errors
        case -1:
            return "Operation not permitted"
        case -2:
            return "No such file or directory"
        case -3:
            return "No such process"
        case -4:
            return "Interrupted system call"
        case -5:
            return "Input/output error"
        case -12:
            return "Cannot allocate memory"
        case -13:
            return "Permission denied"
        case -22:
            return "Invalid argument"
        case -128:
            return "User cancelled"

        default:
            return "Unknown error (\(self))"
        }
    }
}
