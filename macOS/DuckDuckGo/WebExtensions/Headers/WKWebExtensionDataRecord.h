#import <Foundation/Foundation.h>
#import "WKWebExtensionDataType.h"

API_AVAILABLE(macos(15.3))
extern NSErrorDomain const WKWebExtensionDataRecordErrorDomain;

typedef NS_ERROR_ENUM(WKWebExtensionDataRecordErrorDomain, WKWebExtensionDataRecordError) {
    WKWebExtensionDataRecordErrorUnknown = 1,
    WKWebExtensionDataRecordErrorLocalStorageFailed,
    WKWebExtensionDataRecordErrorSessionStorageFailed,
    WKWebExtensionDataRecordErrorSynchronizedStorageFailed,
} API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionDataRecord : NSObject

@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSString *uniqueIdentifier;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionDataType> *containedDataTypes;
@property (nonatomic, readonly, copy) NSArray<NSError *> *errors;
@property (nonatomic, readonly) NSUInteger totalSizeInBytes;

- (NSUInteger)sizeInBytesOfTypes:(NSSet<WKWebExtensionDataType> *)dataTypes;

@end
