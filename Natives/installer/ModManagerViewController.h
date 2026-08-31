#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, AmethystContentType) {
    AmethystContentTypeMod,
    AmethystContentTypeResourcePack,
    AmethystContentTypeShaderPack
};

@interface ModManagerViewController : UITableViewController

- (instancetype)initWithProfile:(NSMutableDictionary *)profile;
- (instancetype)initWithProfile:(NSMutableDictionary *)profile contentType:(AmethystContentType)contentType;

@end
