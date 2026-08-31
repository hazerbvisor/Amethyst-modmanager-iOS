#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ModrinthModDetailViewController;

@protocol ModrinthModDetailViewControllerDelegate <NSObject>
- (void)modDetailViewController:(ModrinthModDetailViewController *)controller
    installVersion:(NSDictionary *)version
    project:(NSDictionary *)project
    includeDependencies:(BOOL)includeDependencies;
@end

@interface ModrinthModDetailViewController : UITableViewController
@property(nonatomic, weak) id<ModrinthModDetailViewControllerDelegate> delegate;

- (instancetype)initWithItem:(NSDictionary *)item
    minecraftVersion:(NSString *)minecraftVersion
    loader:(NSString *)loader
    installed:(BOOL)installed;
- (void)setInstalling:(BOOL)installing;
- (void)installationDidFinishWithError:(NSError * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
