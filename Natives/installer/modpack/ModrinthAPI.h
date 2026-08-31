#import <Foundation/Foundation.h>
#import "ModpackAPI.h"

@interface ModrinthAPI : ModpackAPI

- (NSArray<NSDictionary *> *)compatibleVersionsForProject:(NSString *)projectId
    minecraftVersion:(NSString *)minecraftVersion
    loader:(NSString *)loader
    includeChangelog:(BOOL)includeChangelog;

@end
