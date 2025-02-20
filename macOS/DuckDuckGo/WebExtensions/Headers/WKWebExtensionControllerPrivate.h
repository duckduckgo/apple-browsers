#import "WKWebExtensionController.h"

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionController ()

@property (nonatomic, getter=_inTestingMode, setter=_setTestingMode:) BOOL _testingMode;

@end
