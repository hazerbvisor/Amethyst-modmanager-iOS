#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefGameDirViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "LauncherProfileEditorViewController.h"
#import "LauncherProfilesViewController.h"
//#import "NSFileManager+NRFileManager.h"
#import "PLProfiles.h"
#import "installer/LiquidGlassCompat.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#import "UIKit+AFNetworking.h"
#pragma clang diagnostic pop
#import "UIKit+hook.h"
#import "installer/FabricInstallViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "installer/ModpackInstallViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

typedef NS_ENUM(NSUInteger, LauncherProfilesTableSection) {
    kInstances,
    kProfiles
};

@interface LauncherProfilesViewController () //<UIContextMenuInteractionDelegate>

@property(nonatomic) UIBarButtonItem *createButtonItem;
@property(nonatomic) UILabel *profileCountLabel;
@end

@implementation LauncherProfilesViewController

- (id)init {
    self = [super init];
    self.title = localize(@"Profiles", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuProfiles";
}

- (void)buildProfileHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0,
        self.tableView.bounds.size.width, 154.0)];
    UIVisualEffectView *glass = AmethystCreateGlassView(26.0, NO,
        [UIColor.systemPurpleColor colorWithAlphaComponent:0.30]);
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:glass];

    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:
        @"square.stack.3d.up.fill"]];
    symbol.translatesAutoresizingMaskIntoConstraints = NO;
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.tintColor = UIColor.systemPurpleColor;
    [glass.contentView addSubview:symbol];

    UILabel *eyebrow = [UILabel new];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.text = @"YOUR MINECRAFT";
    eyebrow.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    eyebrow.textColor = UIColor.systemPurpleColor;
    [glass.contentView addSubview:eyebrow];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Ready to play?";
    title.font = [UIFont systemFontOfSize:29.0 weight:UIFontWeightBold];
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.8;
    [glass.contentView addSubview:title];

    self.profileCountLabel = [UILabel new];
    self.profileCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileCountLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.profileCountLabel.textColor = UIColor.secondaryLabelColor;
    [glass.contentView addSubview:self.profileCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [glass.topAnchor constraintEqualToAnchor:header.topAnchor constant:10.0],
        [glass.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [glass.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [glass.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],
        [symbol.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:22.0],
        [symbol.centerYAnchor constraintEqualToAnchor:glass.contentView.centerYAnchor],
        [symbol.widthAnchor constraintEqualToConstant:54.0],
        [symbol.heightAnchor constraintEqualToConstant:54.0],
        [eyebrow.leadingAnchor constraintEqualToAnchor:symbol.trailingAnchor constant:18.0],
        [eyebrow.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:22.0],
        [title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-18.0],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:4.0],
        [self.profileCountLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.profileCountLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.profileCountLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5.0]
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIMenu *createMenu = [UIMenu menuWithTitle:localize(@"profile.title.create", nil) image:nil identifier:nil
    options:UIMenuOptionsDisplayInline
    children:@[
        [UIAction
            actionWithTitle:@"Vanilla" image:nil
            identifier:@"vanilla" handler:^(UIAction *action) {
                [self actionEditProfile:@{
                    @"name": @"",
                    @"lastVersionId": @"latest-release"}];
            }],
#if 0 // TODO
        [UIAction
            actionWithTitle:@"OptiFine" image:nil
            identifier:@"optifine" handler:createHandler],
#endif
        [UIAction
            actionWithTitle:@"Fabric/Quilt" image:nil
            identifier:@"fabric_or_quilt" handler:^(UIAction *action) {
                [self actionCreateFabricProfile];
            }],
        [UIAction
            actionWithTitle:@"Forge" image:nil
            identifier:@"forge" handler:^(UIAction *action) {
                [self actionCreateForgeProfile];
            }],
        [UIAction
            actionWithTitle:@"Modpack" image:nil
            identifier:@"modpack" handler:^(UIAction *action) {
                [self actionCreateModpackProfile];
            }]
    ]];
    self.createButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:createMenu];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    AmethystStyleTableView(self.tableView);
    [self buildProfileHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Put navigation buttons back in place
    self.navigationItem.rightBarButtonItems = @[[sidebarViewController drawAccountButton], self.createButtonItem];

    // Pickup changes made in the profile editor and switching instance
    [PLProfiles updateCurrent];
    NSUInteger count = PLProfiles.current.profiles.count;
    self.profileCountLabel.text = [NSString stringWithFormat:@"%lu profile%@ available",
        (unsigned long)count, count == 1 ? @"" : @"s"];
    [self.tableView reloadData];
    [self.navigationController performSelector:@selector(reloadProfileList)];
}

- (void)actionTogglePrefIsolation:(UISwitch *)sender {
    if (!sender.isOn) {
        setPrefBool(@"internal.isolated", NO);
    }
    toggleIsolatedPref(sender.isOn);
}

- (void)actionCreateFabricProfile {
    FabricInstallViewController *vc = [FabricInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateForgeProfile {
    ForgeInstallViewController *vc = [ForgeInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateModpackProfile {
    ModpackInstallViewController *vc = [ModpackInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionEditProfile:(NSDictionary *)profile {
    LauncherProfileEditorViewController *vc = [LauncherProfileEditorViewController new];
    vc.profile = profile.mutableCopy;
    [self presentNavigatedViewController:vc];
}

- (void)presentNavigatedViewController:(UIViewController *)vc {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    //nav.navigationBar.prefersLargeTitles = YES;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return localize(@"profile.section.instance", nil);
        case 1: return localize(@"profile.section.profiles", nil);
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return [PLProfiles.current.profiles count];
    }
    return 0;
}

- (void)setupInstanceCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    cell.userInteractionEnabled = !getenv("DEMO_LOCK");
    if (row == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder"];
        cell.textLabel.text = localize(@"preference.title.game_directory", nil);
        cell.detailTextLabel.text = getenv("DEMO_LOCK") ? @".demo" : getPrefObject(@"general.game_directory");
        cell.imageView.tintColor = UIColor.systemBlueColor;
    } else {
        NSString *imageName;
        if (@available(iOS 15.0, *)) {
            imageName = @"folder.badge.gearshape";
        } else {
            imageName = @"folder.badge.gear";
        }
        cell.imageView.image = [UIImage systemImageNamed:imageName];
        cell.imageView.tintColor = UIColor.systemIndigoColor;
        cell.textLabel.text = localize(@"profile.title.separate_preference", nil);
        cell.detailTextLabel.text = localize(@"profile.detail.separate_preference", nil);
        UISwitch *view = [UISwitch new];
        [view setOn:getPrefBool(@"internal.isolated") animated:NO];
        [view addTarget:self action:@selector(actionTogglePrefIsolation:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = view;
    }
}

- (void)setupProfileCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    NSMutableDictionary *profile = PLProfiles.current.profiles.allValues[row];

    cell.textLabel.text = profile[@"name"];
    cell.detailTextLabel.text = profile[@"lastVersionId"];
    cell.imageView.layer.magnificationFilter = kCAFilterNearest;
    cell.imageView.layer.cornerRadius = 12.0;
    cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
    cell.imageView.clipsToBounds = YES;

    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(40, 40)];
    [cell.imageView setImageWithURL:[NSURL URLWithString:profile[@"icon"]] placeholderImage:fallbackImage];
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *cellID = indexPath.section == kInstances ? @"InstanceCell" : @"ProfileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        if (indexPath.section == kProfiles) {
            cell.imageView.frame = CGRectMake(0, 0, 40, 40);
            cell.imageView.isSizeFixed = YES;
        }
    } else {
        cell.imageView.image = nil;
        cell.userInteractionEnabled = YES;
        cell.accessoryView = nil;
    }

    if (indexPath.section == kInstances) {
        [self setupInstanceCell:cell atRow:indexPath.row];
    } else {
        [self setupProfileCell:cell atRow:indexPath.row];
    }

    cell.textLabel.enabled = cell.detailTextLabel.enabled = cell.userInteractionEnabled;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    AmethystStyleCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    AmethystAnimateCellEntrance(cell, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    AmethystAnimateSelection(cell);
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == kInstances) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[LauncherPrefGameDirViewController new] animated:YES];
        }
        return;
    }

    [self actionEditProfile:PLProfiles.current.profiles.allValues[indexPath.row]];
}

#pragma mark Context Menu configuration

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *title = localize(@"preference.title.confirm", nil);
    // reusing the delete runtime message
    NSString *message = [NSString stringWithFormat:localize(@"preference.title.confirm.delete_runtime", nil), cell.textLabel.text];
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    confirmAlert.popoverPresentationController.sourceView = cell;
    confirmAlert.popoverPresentationController.sourceRect = cell.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [PLProfiles.current.profiles removeObjectForKey:cell.textLabel.text];
        if ([PLProfiles.current.selectedProfileName isEqualToString:cell.textLabel.text]) {
            // The one being deleted is the selected one, switch to the random one now
            PLProfiles.current.selectedProfileName = PLProfiles.current.profiles.allKeys[0];
            [self.navigationController performSelector:@selector(reloadProfileList)];
        } else {
            [PLProfiles.current save];
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmAlert addAction:cancel];
    [confirmAlert addAction:ok];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kInstances || PLProfiles.current.profiles.count==1) {
        return UITableViewCellEditingStyleNone;
    }
    return UITableViewCellEditingStyleDelete;
}

@end
