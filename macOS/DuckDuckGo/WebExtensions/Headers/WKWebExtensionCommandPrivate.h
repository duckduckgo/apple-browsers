#import "WKWebExtensionCommand.h"

@interface WKWebExtensionCommand ()

@property (nonatomic, readonly, copy) NSString *_shortcut;
@property (nonatomic, readonly, copy) NSString *_userVisibleShortcut;

- (BOOL)_matchesEvent:(NSEvent *)event;

@end
