#import "WKWebExtensionControllerConfiguration.h"

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionControllerConfiguration ()

+ (instancetype)_temporaryConfiguration;

@property (nonatomic, readonly, getter=_isTemporary) BOOL _temporary;

@property (nonatomic, nullable, copy, setter=_setStorageDirectoryPath:) NSString *_storageDirectoryPath;

@end
