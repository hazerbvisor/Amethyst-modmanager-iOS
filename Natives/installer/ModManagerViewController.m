#import "AFNetworking.h"
#import "installer/LiquidGlassCompat.h"
#import "ModManagerViewController.h"
#import "installer/ModrinthModDetailViewController.h"
#import "UIKit+AFNetworking.h"
#import "installer/modpack/ModrinthAPI.h"
#import "LauncherPreferences.h"
#import "utils.h"

#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const AmethystDisabledModSuffix = @".disabled";

static NSURL *AmethystArtworkURL(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] == 0) return nil;
    NSURL *url = [NSURL URLWithString:value];
    if (!url) {
        NSString *encoded = [value stringByAddingPercentEncodingWithAllowedCharacters:
            NSCharacterSet.URLQueryAllowedCharacterSet];
        url = [NSURL URLWithString:encoded];
    }
    if (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString]) return nil;
    return url;
}

static NSString *AmethystContentSingular(AmethystContentType type) {
    switch (type) {
        case AmethystContentTypeResourcePack: return @"resource pack";
        case AmethystContentTypeShaderPack: return @"shader pack";
        default: return @"mod";
    }
}

static NSString *AmethystContentPlural(AmethystContentType type) {
    switch (type) {
        case AmethystContentTypeResourcePack: return @"Resource Packs";
        case AmethystContentTypeShaderPack: return @"Shaders";
        default: return @"Mods";
    }
}

static NSString *AmethystContentProjectType(AmethystContentType type) {
    switch (type) {
        case AmethystContentTypeResourcePack: return @"resourcepack";
        case AmethystContentTypeShaderPack: return @"shader";
        default: return @"mod";
    }
}

static NSString *AmethystContentDirectoryName(AmethystContentType type) {
    switch (type) {
        case AmethystContentTypeResourcePack: return @"resourcepacks";
        case AmethystContentTypeShaderPack: return @"shaderpacks";
        default: return @"mods";
    }
}

static NSString *AmethystContentExtension(AmethystContentType type) {
    return type == AmethystContentTypeMod ? @"jar" : @"zip";
}

static NSString *AmethystContentSymbol(AmethystContentType type) {
    switch (type) {
        case AmethystContentTypeResourcePack: return @"photo.stack";
        case AmethystContentTypeShaderPack: return @"sparkles";
        default: return @"shippingbox";
    }
}

static NSString *AmethystReadableFilterName(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"Other";
    NSString *readable = [value stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    readable = [readable stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    return readable.capitalizedString;
}

@interface ModrinthModBrowserViewController : UITableViewController<UISearchResultsUpdating>
- (instancetype)initWithProfile:(NSDictionary *)profile
    contentDirectory:(NSString *)contentDirectory
    contentType:(AmethystContentType)contentType;
@end

@interface ModManagerViewController ()<UIDocumentPickerDelegate>
@property(nonatomic) NSMutableDictionary *profile;
@property(nonatomic) NSString *modsDirectory;
@property(nonatomic) NSMutableArray<NSString *> *mods;
@property(nonatomic) AmethystContentType contentType;
@property(nonatomic) UIBarButtonItem *addButtonItem;
@property(nonatomic) UIBarButtonItem *deleteButtonItem;
@property(nonatomic) UILabel *managerCountLabel;
- (void)confirmDeleteAtIndexPath:(NSIndexPath *)indexPath sourceView:(UIView *)sourceView
    completion:(void (^)(BOOL deleted))completion;
@end

@implementation ModManagerViewController

- (void)buildManagerHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0,
        self.tableView.bounds.size.width, 142.0)];
    UIColor *accent = self.contentType == AmethystContentTypeMod
        ? UIColor.systemIndigoColor : UIColor.systemPurpleColor;
    UIVisualEffectView *glass = AmethystCreateGlassView(24.0, NO,
        [accent colorWithAlphaComponent:0.28]);
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:glass];

    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:
        AmethystContentSymbol(self.contentType)]];
    symbol.translatesAutoresizingMaskIntoConstraints = NO;
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.tintColor = accent;
    [glass.contentView addSubview:symbol];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = AmethystContentPlural(self.contentType);
    title.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    [glass.contentView addSubview:title];

    self.managerCountLabel = [UILabel new];
    self.managerCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.managerCountLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.managerCountLabel.textColor = UIColor.secondaryLabelColor;
    [glass.contentView addSubview:self.managerCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [glass.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
        [glass.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [glass.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [glass.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],
        [symbol.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:22.0],
        [symbol.centerYAnchor constraintEqualToAnchor:glass.contentView.centerYAnchor],
        [symbol.widthAnchor constraintEqualToConstant:48.0],
        [symbol.heightAnchor constraintEqualToConstant:48.0],
        [title.leadingAnchor constraintEqualToAnchor:symbol.trailingAnchor constant:17.0],
        [title.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-18.0],
        [title.centerYAnchor constraintEqualToAnchor:glass.contentView.centerYAnchor constant:-12.0],
        [self.managerCountLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.managerCountLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.managerCountLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0]
    ]];
    self.tableView.tableHeaderView = header;
}

- (instancetype)initWithProfile:(NSMutableDictionary *)profile {
    return [self initWithProfile:profile contentType:AmethystContentTypeMod];
}

- (instancetype)initWithProfile:(NSMutableDictionary *)profile contentType:(AmethystContentType)contentType {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.profile = profile;
        self.contentType = contentType;
        self.title = [NSString stringWithFormat:@"Manage %@", AmethystContentPlural(contentType)];

        NSString *relativeGameDirectory = profile[@"gameDir"];
        if (relativeGameDirectory.length == 0) relativeGameDirectory = @".";
        NSString *instanceRoot = [NSString stringWithFormat:@"%s/instances/%@",
            getenv("POJAV_HOME"), getPrefObject(@"general.game_directory")];
        NSString *gameDirectory = [[instanceRoot stringByAppendingPathComponent:relativeGameDirectory]
            stringByStandardizingPath];
        self.modsDirectory = [gameDirectory stringByAppendingPathComponent:
            AmethystContentDirectoryName(contentType)];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelection = NO;
    AmethystStyleTableView(self.tableView);
    [self buildManagerHeader];

    NSString *singular = AmethystContentSingular(self.contentType);
    NSString *extension = AmethystContentExtension(self.contentType).uppercaseString;
    UIAction *browse = [UIAction actionWithTitle:[NSString stringWithFormat:@"Browse %@ on Modrinth",
        AmethystContentPlural(self.contentType)]
        image:[UIImage systemImageNamed:@"magnifyingglass"] identifier:nil handler:^(__kindof UIAction *action) {
        ModrinthModBrowserViewController *browser = [[ModrinthModBrowserViewController alloc]
            initWithProfile:self.profile contentDirectory:self.modsDirectory contentType:self.contentType];
        [self.navigationController pushViewController:browser animated:YES];
    }];
    UIAction *importFile = [UIAction actionWithTitle:[NSString stringWithFormat:@"Import %@ from Files", extension]
        image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction *action) {
        [self actionImportJar];
    }];
    UIMenu *menu = [UIMenu menuWithTitle:[NSString stringWithFormat:@"Add %@", singular.capitalizedString]
        children:@[browse, importFile]];
    self.addButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:menu];
    self.deleteButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain
        target:self action:@selector(actionToggleDeleteMode)];
    self.deleteButtonItem.tintColor = UIColor.systemRedColor;
    self.deleteButtonItem.accessibilityLabel = @"Delete installed content";
    self.navigationItem.rightBarButtonItems = @[self.addButtonItem, self.deleteButtonItem];
}

- (void)updateDeleteButtonAppearance {
    BOOL editing = self.tableView.isEditing;
    self.deleteButtonItem.title = editing ? @"Done" : nil;
    self.deleteButtonItem.image = editing ? nil : [UIImage systemImageNamed:@"trash"];
    self.deleteButtonItem.style = editing ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
    self.deleteButtonItem.tintColor = editing ? self.view.tintColor : UIColor.systemRedColor;
    self.deleteButtonItem.accessibilityLabel = editing ? @"Finish deleting" : @"Delete installed content";
}

- (void)actionToggleDeleteMode {
    if (self.mods.count == 0) return;
    BOOL editing = !self.tableView.isEditing;
    [self.tableView setEditing:editing animated:YES];
    self.addButtonItem.enabled = !editing;
    [self updateDeleteButtonAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadMods];
}

- (void)reloadMods {
    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:self.modsDirectory
        withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        showDialog([NSString stringWithFormat:@"Unable to open %@ folder",
            AmethystContentSingular(self.contentType)], error.localizedDescription);
        self.mods = [NSMutableArray new];
        return;
    }

    NSArray<NSString *> *contents = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:self.modsDirectory error:&error];
    NSString *extension = [@"." stringByAppendingString:AmethystContentExtension(self.contentType)];
    BOOL supportsDisabledFiles = self.contentType == AmethystContentTypeMod;
    NSPredicate *jarPredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        NSString *lowercaseName = name.lowercaseString;
        return [lowercaseName hasSuffix:extension] ||
            (supportsDisabledFiles && [lowercaseName hasSuffix:[extension stringByAppendingString:AmethystDisabledModSuffix]]);
    }];
    self.mods = [[contents filteredArrayUsingPredicate:jarPredicate] mutableCopy] ?: [NSMutableArray new];
    [self.mods sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.managerCountLabel.text = [NSString stringWithFormat:@"%lu installed • Add or remove anytime",
        (unsigned long)self.mods.count];
    self.deleteButtonItem.enabled = self.mods.count > 0;
    if (self.mods.count == 0 && self.tableView.isEditing) {
        [self.tableView setEditing:NO animated:YES];
        self.addButtonItem.enabled = YES;
        [self updateDeleteButtonAppearance];
    }
    [self.tableView reloadData];
}

- (void)actionImportJar {
    UTType *jarType = self.contentType == AmethystContentTypeMod
        ? [UTType typeWithMIMEType:@"application/java-archive"] : UTTypeZIP;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[jarType] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    BOOL importedAnyJar = NO;
    NSError *firstError = nil;
    NSString *expectedExtension = AmethystContentExtension(self.contentType);
    for (NSURL *url in urls) {
        if (![url.pathExtension.lowercaseString isEqualToString:expectedExtension]) continue;
        BOOL accessed = [url startAccessingSecurityScopedResource];
        NSString *destination = [self.modsDirectory stringByAppendingPathComponent:url.lastPathComponent];
        NSString *stagedPath = [self.modsDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@".amethyst-import-%@", NSUUID.UUID.UUIDString]];
        NSError *error = nil;
        [NSFileManager.defaultManager copyItemAtURL:url
            toURL:[NSURL fileURLWithPath:stagedPath] error:&error];
        if (!error && [NSFileManager.defaultManager fileExistsAtPath:destination]) {
            [NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:destination]
                withItemAtURL:[NSURL fileURLWithPath:stagedPath] backupItemName:nil
                options:0 resultingItemURL:nil error:&error];
        } else if (!error) {
            [NSFileManager.defaultManager moveItemAtPath:stagedPath toPath:destination error:&error];
        }
        if (!error && self.contentType == AmethystContentTypeMod) {
            [NSFileManager.defaultManager removeItemAtPath:
                [destination stringByAppendingString:AmethystDisabledModSuffix] error:nil];
        }
        [NSFileManager.defaultManager removeItemAtPath:stagedPath error:nil];
        if (accessed) [url stopAccessingSecurityScopedResource];
        if (error) {
            if (!firstError) firstError = error;
        } else {
            importedAnyJar = YES;
        }
    }
    [self reloadMods];
    if (firstError) {
        showDialog(@"Import failed", firstError.localizedDescription);
    } else if (importedAnyJar) {
        NSString *singular = AmethystContentSingular(self.contentType);
        UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"Check compatibility"
            message:[NSString stringWithFormat:@"Imported %@ files cannot be verified automatically. Make sure each %@ supports this profile's Minecraft version.%@",
                expectedExtension.uppercaseString, singular,
                self.contentType == AmethystContentTypeMod ? @" Also check its mod loader." : @""]
            preferredStyle:UIAlertControllerStyleAlert];
        [warning addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:warning animated:YES completion:nil];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.mods.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.contentType == AmethystContentTypeMod) {
        return @"Modrinth installs are filtered for this profile. Imported JARs are not compatibility checked. Disabled mods remain in the profile but are not loaded by Minecraft.";
    }
    return [NSString stringWithFormat:@"Modrinth installs are filtered for this profile. Imported ZIPs are not compatibility checked. Enable installed %@ from Minecraft's %@ settings.",
        AmethystContentPlural(self.contentType).lowercaseString,
        self.contentType == AmethystContentTypeResourcePack ? @"Resource Packs" : @"Shader Packs"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ModCell"];
    cell.accessoryView = nil;
    cell.imageView.image = [UIImage systemImageNamed:AmethystContentSymbol(self.contentType)];

    if (self.mods.count == 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"No %@ installed",
            AmethystContentPlural(self.contentType).lowercaseString];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Tap + to browse Modrinth or import a %@.",
            AmethystContentExtension(self.contentType).uppercaseString];
        cell.textLabel.enabled = cell.detailTextLabel.enabled = NO;
        AmethystStyleCell(cell);
        return cell;
    }

    NSString *filename = self.mods[indexPath.row];
    BOOL canToggle = self.contentType == AmethystContentTypeMod;
    BOOL enabled = !canToggle || ![filename.lowercaseString hasSuffix:AmethystDisabledModSuffix];
    NSString *displayName = enabled ? filename : [filename substringToIndex:filename.length - AmethystDisabledModSuffix.length];
    cell.textLabel.text = displayName;
    cell.detailTextLabel.text = canToggle ? (enabled ? @"Enabled" : @"Disabled")
        : @"Installed • Enable from Minecraft settings";
    cell.textLabel.enabled = cell.detailTextLabel.enabled = YES;

    if (canToggle) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = enabled;
        toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(toggleMod:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    cell.textLabel.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.tintColor = self.contentType == AmethystContentTypeMod
        ? UIColor.systemIndigoColor : UIColor.systemPurpleColor;
    AmethystStyleCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    AmethystAnimateCellEntrance(cell, indexPath);
}

- (void)toggleMod:(UISwitch *)sender {
    if (self.contentType != AmethystContentTypeMod) return;
    if (sender.tag >= self.mods.count) return;
    NSString *filename = self.mods[sender.tag];
    NSString *newFilename = sender.isOn
        ? [filename substringToIndex:filename.length - AmethystDisabledModSuffix.length]
        : [filename stringByAppendingString:AmethystDisabledModSuffix];
    NSString *oldPath = [self.modsDirectory stringByAppendingPathComponent:filename];
    NSString *newPath = [self.modsDirectory stringByAppendingPathComponent:newFilename];
    NSError *error = nil;
    [NSFileManager.defaultManager moveItemAtPath:oldPath toPath:newPath error:&error];
    if (error) showDialog(@"Could not change mod state", error.localizedDescription);
    [self reloadMods];
}

- (void)removeRegistryEntriesForFilename:(NSString *)filename {
    NSString *registryPath = [self.modsDirectory stringByAppendingPathComponent:@".amethyst-modrinth.json"];
    NSData *data = [NSData dataWithContentsOfFile:registryPath];
    NSMutableDictionary *registry = data
        ? [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy]
        : nil;
    if (![registry isKindOfClass:NSMutableDictionary.class]) return;
    NSMutableArray<NSString *> *keysToRemove = [NSMutableArray new];
    [registry enumerateKeysAndObjectsUsingBlock:^(NSString *projectId, NSString *storedFilename, BOOL *stop) {
        if ([storedFilename.lastPathComponent isEqualToString:filename.lastPathComponent] ||
            [storedFilename.lastPathComponent isEqualToString:
                [filename stringByReplacingOccurrencesOfString:AmethystDisabledModSuffix withString:@""]]) {
            [keysToRemove addObject:projectId];
        }
    }];
    [registry removeObjectsForKeys:keysToRemove];
    NSData *updated = [NSJSONSerialization dataWithJSONObject:registry
        options:NSJSONWritingPrettyPrinted error:nil];
    [updated writeToFile:registryPath options:NSDataWritingAtomic error:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mods.count == 0) return nil;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self confirmDeleteAtIndexPath:indexPath sourceView:sourceView completion:completionHandler];
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.mods.count > 0 && indexPath.row < self.mods.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
    editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath]
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [self confirmDeleteAtIndexPath:indexPath sourceView:cell completion:nil];
}

- (void)confirmDeleteAtIndexPath:(NSIndexPath *)indexPath sourceView:(UIView *)sourceView
    completion:(void (^)(BOOL deleted))completion {
    if (indexPath.row >= self.mods.count) {
        if (completion) completion(NO);
        return;
    }
    NSString *filename = self.mods[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:
        [NSString stringWithFormat:@"Delete %@?", AmethystContentSingular(self.contentType)]
        message:filename preferredStyle:UIAlertControllerStyleActionSheet];
    alert.popoverPresentationController.sourceView = sourceView ?: self.view;
    alert.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : self.view.bounds;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *action) { if (completion) completion(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
        NSError *error = nil;
        [NSFileManager.defaultManager removeItemAtPath:
            [self.modsDirectory stringByAppendingPathComponent:filename] error:&error];
        if (error) showDialog(@"Delete failed", error.localizedDescription);
        else [self removeRegistryEntriesForFilename:filename];
        [self reloadMods];
        if (completion) completion(error == nil);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Modrinth browser

@interface AmethystModStoreCell : UITableViewCell
@property(nonatomic, strong) UIView *cardView;
@property(nonatomic, strong) UIImageView *modIconView;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *creatorLabel;
@property(nonatomic, strong) UILabel *summaryLabel;
@property(nonatomic, strong) UILabel *metadataLabel;
@property(nonatomic, strong) UIButton *getButton;
@property(nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property(nonatomic, copy) NSString *representedProjectId;
- (void)configureWithItem:(NSDictionary *)item installed:(BOOL)installed metadata:(NSString *)metadata;
- (void)setLoading:(BOOL)loading;
@end

@implementation AmethystModStoreCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    self.cardView = AmethystCreateGlassView(18.0, YES, nil);
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.cardView];
    UIView *cardContent = [(UIVisualEffectView *)self.cardView contentView];

    self.modIconView = [UIImageView new];
    self.modIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.modIconView.contentMode = UIViewContentModeScaleAspectFill;
    self.modIconView.clipsToBounds = YES;
    self.modIconView.layer.cornerRadius = 16.0;
    self.modIconView.layer.cornerCurve = kCACornerCurveContinuous;
    self.modIconView.backgroundColor = UIColor.tertiarySystemFillColor;
    [cardContent addSubview:self.modIconView];

    self.nameLabel = [UILabel new];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.nameLabel.adjustsFontForContentSizeCategory = YES;
    self.nameLabel.numberOfLines = 1;
    [cardContent addSubview:self.nameLabel];

    self.creatorLabel = [UILabel new];
    self.creatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.creatorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.creatorLabel.textColor = UIColor.secondaryLabelColor;
    self.creatorLabel.numberOfLines = 1;
    [cardContent addSubview:self.creatorLabel];

    self.summaryLabel = [UILabel new];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.summaryLabel.textColor = UIColor.secondaryLabelColor;
    self.summaryLabel.numberOfLines = 2;
    [cardContent addSubview:self.summaryLabel];

    self.metadataLabel = [UILabel new];
    self.metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metadataLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.metadataLabel.textColor = UIColor.tertiaryLabelColor;
    self.metadataLabel.numberOfLines = 1;
    [cardContent addSubview:self.metadataLabel];

    self.getButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.getButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.getButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [cardContent addSubview:self.getButton];
    AmethystInstallGlassBackground(self.getButton, 16.0, YES, nil);

    self.activityIndicator = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [cardContent addSubview:self.activityIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

        [self.modIconView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:14.0],
        [self.modIconView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
        [self.modIconView.widthAnchor constraintEqualToConstant:78.0],
        [self.modIconView.heightAnchor constraintEqualToConstant:78.0],

        [self.getButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-14.0],
        [self.getButton.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
        [self.getButton.widthAnchor constraintEqualToConstant:84.0],
        [self.getButton.heightAnchor constraintEqualToConstant:32.0],
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.getButton.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.getButton.centerYAnchor],

        [self.nameLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:12.0],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.modIconView.trailingAnchor constant:14.0],
        [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.getButton.leadingAnchor constant:-10.0],
        [self.creatorLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:1.0],
        [self.creatorLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.creatorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.getButton.leadingAnchor constant:-10.0],
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.creatorLabel.bottomAnchor constant:5.0],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.summaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.getButton.leadingAnchor constant:-10.0],
        [self.metadataLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.summaryLabel.bottomAnchor constant:3.0],
        [self.metadataLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.metadataLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.getButton.leadingAnchor constant:-10.0],
        [self.metadataLabel.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-10.0]
    ]];
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedProjectId = nil;
    [self.modIconView cancelImageDownloadTask];
    self.modIconView.image = [UIImage imageNamed:@"DefaultProfile"];
    [self setLoading:NO];
}

- (void)loadArtworkURLs:(NSArray<NSURL *> *)urls
    atIndex:(NSUInteger)index
    projectId:(NSString *)projectId
    placeholder:(UIImage *)placeholder {
    if (index >= urls.count || ![self.representedProjectId isEqualToString:projectId]) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:urls[index]
        cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:30.0];
    __weak typeof(self) weakSelf = self;
    [self.modIconView setImageWithURLRequest:request placeholderImage:placeholder
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if ([strongSelf.representedProjectId isEqualToString:projectId]) strongSelf.modIconView.image = image;
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf.representedProjectId isEqualToString:projectId]) return;
        [strongSelf loadArtworkURLs:urls atIndex:index + 1 projectId:projectId placeholder:placeholder];
    }];
}

- (void)configureWithItem:(NSDictionary *)item installed:(BOOL)installed metadata:(NSString *)metadata {
    self.nameLabel.text = item[@"title"];
    self.creatorLabel.text = [NSString stringWithFormat:@"By %@", item[@"author"] ?: @"Modrinth creator"];
    self.summaryLabel.text = item[@"description"];
    self.metadataLabel.text = metadata;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@",
        self.nameLabel.text ?: @"Mod", self.creatorLabel.text ?: @"", metadata ?: @""];

    [self.getButton setTitle:installed ? @"INSTALLED" : @"GET" forState:UIControlStateNormal];
    self.getButton.enabled = !installed;
    AmethystInstallGlassBackground(self.getButton, 16.0, !installed,
        installed ? UIColor.systemGrayColor : self.tintColor);
    [self.getButton setTitleColor:installed ? UIColor.tertiaryLabelColor : self.tintColor
        forState:UIControlStateNormal];

    UIImage *placeholder = [UIImage imageNamed:@"DefaultProfile"];
    self.modIconView.image = placeholder;
    self.representedProjectId = [item[@"id"] isKindOfClass:NSString.class]
        ? item[@"id"] : NSUUID.UUID.UUIDString;
    NSMutableArray<NSURL *> *artworkURLs = [NSMutableArray new];
    NSURL *iconURL = AmethystArtworkURL(item[@"imageUrl"]);
    NSURL *fallbackURL = AmethystArtworkURL(item[@"fallbackImageUrl"]);
    if (iconURL) [artworkURLs addObject:iconURL];
    if (fallbackURL && ![fallbackURL isEqual:iconURL]) [artworkURLs addObject:fallbackURL];
    [self loadArtworkURLs:artworkURLs atIndex:0 projectId:self.representedProjectId
        placeholder:placeholder];
}

- (void)setLoading:(BOOL)loading {
    self.getButton.hidden = loading;
    if (loading) [self.activityIndicator startAnimating];
    else [self.activityIndicator stopAnimating];
}

@end

@interface ModrinthModBrowserViewController ()<ModrinthModDetailViewControllerDelegate>
@property(nonatomic) NSDictionary *profile;
@property(nonatomic) NSString *modsDirectory;
@property(nonatomic) AmethystContentType contentType;
@property(nonatomic) NSString *minecraftVersion;
@property(nonatomic) NSString *loader;
@property(nonatomic) UISearchController *searchController;
@property(nonatomic) NSMutableArray *results;
@property(nonatomic) ModrinthAPI *api;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSInteger selectedSort;
@property(nonatomic) UISegmentedControl *sortControl;
@property(nonatomic) NSMutableSet<NSString *> *installedProjectIds;
@property(nonatomic) NSArray<NSDictionary *> *availableCategories;
@property(nonatomic) NSString *selectedCategory;
@property(nonatomic) NSString *selectedEnvironment;
@property(nonatomic) UIBarButtonItem *filterButton;
@end

@implementation ModrinthModBrowserViewController

- (instancetype)initWithProfile:(NSDictionary *)profile
    contentDirectory:(NSString *)contentDirectory
    contentType:(AmethystContentType)contentType {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.profile = profile;
        self.modsDirectory = contentDirectory;
        self.contentType = contentType;
        self.title = AmethystContentPlural(contentType);
        [self resolveCompatibility];
    }
    return self;
}

- (BOOL)hasResolvedCompatibility {
    return self.minecraftVersion.length > 0 &&
        (self.contentType != AmethystContentTypeMod || self.loader.length > 0);
}

- (NSString *)versionLoaderFilter {
    if (self.contentType == AmethystContentTypeMod) return self.loader ?: @"";
    if (self.contentType == AmethystContentTypeResourcePack) return @"minecraft";
    return @"";
}

- (void)resolveCompatibility {
    NSString *versionId = self.profile[@"lastVersionId"] ?: @"";
    NSString *lowercaseId = versionId.lowercaseString;
    if ([lowercaseId containsString:@"neoforge"]) self.loader = @"neoforge";
    else if ([lowercaseId containsString:@"forge"]) self.loader = @"forge";
    else if ([lowercaseId containsString:@"quilt"]) self.loader = @"quilt";
    else if ([lowercaseId containsString:@"fabric"]) self.loader = @"fabric";

    NSString *versionJSON = [NSString stringWithFormat:@"%s/versions/%@/%@.json",
        getenv("POJAV_GAME_DIR"), versionId, versionId];
    NSDictionary *metadata = parseJSONFromFile(versionJSON);
    self.minecraftVersion = metadata[@"inheritsFrom"];
    if (self.minecraftVersion.length == 0) {
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:@"(?:1\\.\\d+(?:\\.\\d+)?|2\\d\\.\\d+(?:\\.\\d+)?)"
            options:0 error:nil];
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:versionId
            options:0 range:NSMakeRange(0, versionId.length)];
        if (matches.count > 0) {
            self.minecraftVersion = [versionId substringWithRange:matches.lastObject.range];
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.api = [ModrinthAPI new];
    self.results = [NSMutableArray new];
    self.installedProjectIds = [NSMutableSet new];
    AmethystStyleTableView(self.tableView);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 130.0;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = [NSString stringWithFormat:@"Search %@",
        AmethystContentPlural(self.contentType).lowercaseString];
    self.searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
    self.filterButton = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
        style:UIBarButtonItemStylePlain target:nil action:nil];
    self.filterButton.accessibilityLabel = @"Filters";
    self.navigationItem.rightBarButtonItem = self.filterButton;
    [self installFallbackCategories];
    [self rebuildFilterMenu];
    [self buildStoreHeader];
    [self reloadInstalledProjects];
    [self loadAvailableCategories];

    if (![self hasResolvedCompatibility]) {
        self.searchController.searchBar.userInteractionEnabled = NO;
        self.results = nil;
        [self.tableView reloadData];
    } else {
        [self performSearchAppending:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadInstalledProjects];
    [self.tableView reloadData];
}

- (void)buildStoreHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 166.0)];

    UILabel *eyebrow = [UILabel new];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.text = @"MODRINTH STORE";
    eyebrow.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    eyebrow.textColor = self.view.tintColor;
    [header addSubview:eyebrow];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = [NSString stringWithFormat:@"Discover %@", AmethystContentPlural(self.contentType)];
    title.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold];
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.8;
    [header addSubview:title];

    UILabel *compatibility = [UILabel new];
    compatibility.translatesAutoresizingMaskIntoConstraints = NO;
    compatibility.text = self.contentType == AmethystContentTypeMod
        ? [NSString stringWithFormat:@"✓  Minecraft %@  •  %@",
            self.minecraftVersion ?: @"Unknown version", self.loader.capitalizedString ?: @"Unknown loader"]
        : [NSString stringWithFormat:@"✓  Minecraft %@", self.minecraftVersion ?: @"Unknown version"];
    compatibility.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    compatibility.textColor = UIColor.secondaryLabelColor;
    [header addSubview:compatibility];

    self.sortControl = [[UISegmentedControl alloc] initWithItems:@[@"Featured", @"Popular", @"Updated"]];
    self.sortControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.sortControl.selectedSegmentIndex = self.selectedSort;
    self.sortControl.enabled = [self hasResolvedCompatibility];
    [self.sortControl addTarget:self action:@selector(sortChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.sortControl];

    [NSLayoutConstraint activateConstraints:@[
        [eyebrow.topAnchor constraintEqualToAnchor:header.topAnchor constant:14.0],
        [eyebrow.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [eyebrow.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-20.0],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:3.0],
        [title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [compatibility.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0],
        [compatibility.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [compatibility.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.sortControl.topAnchor constraintEqualToAnchor:compatibility.bottomAnchor constant:14.0],
        [self.sortControl.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [self.sortControl.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.sortControl.heightAnchor constraintEqualToConstant:34.0]
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)installFallbackCategories {
    NSArray<NSString *> *names;
    if (self.contentType == AmethystContentTypeResourcePack) {
        names = @[@"8x-or-lower", @"16x", @"32x", @"64x", @"128x", @"audio",
            @"fonts", @"gui", @"models", @"realistic", @"themed", @"vanilla-like"];
    } else if (self.contentType == AmethystContentTypeShaderPack) {
        names = @[@"fantasy", @"realistic", @"semi-realistic", @"vanilla-like",
            @"potato", @"low", @"medium", @"high", @"screenshot"];
    } else {
        names = @[@"adventure", @"decoration", @"equipment", @"game-mechanics", @"library",
            @"magic", @"management", @"mobs", @"optimization", @"storage", @"technology",
            @"transportation", @"utility", @"worldgen"];
    }
    NSMutableArray *categories = [NSMutableArray new];
    for (NSString *name in names) {
        [categories addObject:@{@"name": name, @"header": @"Categories"}];
    }
    self.availableCategories = categories;
}

- (void)loadAvailableCategories {
    NSString *projectType = AmethystContentProjectType(self.contentType);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *response = [self.api getEndpoint:@"tag/category" params:nil];
        NSMutableArray<NSDictionary *> *categories = [NSMutableArray new];
        for (id value in response) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *category = value;
            if (![category[@"project_type"] isEqualToString:projectType] ||
                ![category[@"name"] isKindOfClass:NSString.class]) continue;
            [categories addObject:category];
        }
        [categories sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSString *leftHeader = [left[@"header"] isKindOfClass:NSString.class] ? left[@"header"] : @"";
            NSString *rightHeader = [right[@"header"] isKindOfClass:NSString.class] ? right[@"header"] : @"";
            NSComparisonResult headerResult = [leftHeader localizedCaseInsensitiveCompare:rightHeader];
            if (headerResult != NSOrderedSame) return headerResult;
            return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (categories.count > 0) self.availableCategories = categories;
            [self rebuildFilterMenu];
        });
    });
}

- (void)selectCategory:(NSString *)category {
    self.selectedCategory = category.length > 0 ? category : nil;
    [self rebuildFilterMenu];
    [self performSearchAppending:NO];
}

- (void)selectEnvironment:(NSString *)environment {
    self.selectedEnvironment = environment.length > 0 ? environment : nil;
    [self rebuildFilterMenu];
    [self performSearchAppending:NO];
}

- (void)clearFilters {
    self.selectedCategory = nil;
    self.selectedEnvironment = nil;
    [self rebuildFilterMenu];
    [self performSearchAppending:NO];
}

- (void)rebuildFilterMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *categoryActions = [NSMutableArray new];
    UIAction *allCategories = [UIAction actionWithTitle:@"All Categories"
        image:nil identifier:nil handler:^(UIAction *action) { [weakSelf selectCategory:nil]; }];
    allCategories.state = self.selectedCategory.length == 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
    [categoryActions addObject:allCategories];

    for (NSDictionary *category in self.availableCategories) {
        NSString *name = category[@"name"];
        NSString *header = [category[@"header"] isKindOfClass:NSString.class] ? category[@"header"] : nil;
        NSString *title = AmethystReadableFilterName(name);
        if (header.length > 0 && ![header isEqualToString:@"categories"]) {
            title = [NSString stringWithFormat:@"%@ · %@", AmethystReadableFilterName(header), title];
        }
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil
            handler:^(UIAction *action) { [weakSelf selectCategory:name]; }];
        action.state = [self.selectedCategory isEqualToString:name]
            ? UIMenuElementStateOn : UIMenuElementStateOff;
        [categoryActions addObject:action];
    }
    UIMenu *categories = [UIMenu menuWithTitle:@"Category" image:nil identifier:nil
        options:0 children:categoryActions];

    NSMutableArray<UIMenuElement *> *children = [NSMutableArray arrayWithObject:categories];
    if (self.contentType == AmethystContentTypeMod) {
        NSArray<NSDictionary *> *environmentOptions = @[
            @{@"title": @"All Client-Compatible", @"value": @""},
            @{@"title": @"Client Only", @"value": @"client_only"},
            @{@"title": @"Client & Server", @"value": @"client_and_server"}
        ];
        NSMutableArray<UIAction *> *environmentActions = [NSMutableArray new];
        for (NSDictionary *option in environmentOptions) {
            NSString *value = option[@"value"];
            UIAction *action = [UIAction actionWithTitle:option[@"title"] image:nil identifier:nil
                handler:^(UIAction *action) { [weakSelf selectEnvironment:value]; }];
            action.state = ((self.selectedEnvironment.length == 0 && value.length == 0) ||
                [self.selectedEnvironment isEqualToString:value]) ? UIMenuElementStateOn : UIMenuElementStateOff;
            [environmentActions addObject:action];
        }
        [children addObject:[UIMenu menuWithTitle:@"Environment" image:nil identifier:nil
            options:0 children:environmentActions]];
    }

    BOOL hasFilters = self.selectedCategory.length > 0 || self.selectedEnvironment.length > 0;
    if (hasFilters) {
        UIAction *clear = [UIAction actionWithTitle:@"Clear Filters"
            image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil
            handler:^(UIAction *action) { [weakSelf clearFilters]; }];
        [children addObject:clear];
    }
    self.filterButton.image = [UIImage systemImageNamed:hasFilters
        ? @"line.3.horizontal.decrease.circle.fill" : @"line.3.horizontal.decrease.circle"];
    self.filterButton.accessibilityValue = hasFilters ? @"Active" : @"None";
    self.filterButton.menu = [UIMenu menuWithTitle:@"Filter Results" children:children];
}

- (void)reloadInstalledProjects {
    NSString *registryPath = [self.modsDirectory stringByAppendingPathComponent:@".amethyst-modrinth.json"];
    NSData *data = [NSData dataWithContentsOfFile:registryPath];
    NSDictionary *registry = data
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
        : nil;
    [self.installedProjectIds removeAllObjects];
    if ([registry isKindOfClass:NSDictionary.class]) {
        [self.installedProjectIds addObjectsFromArray:registry.allKeys];
    }
}

- (NSString *)selectedSortIndex {
    return @[@"relevance", @"downloads", @"updated"][self.selectedSort];
}

- (void)sortChanged:(UISegmentedControl *)sender {
    self.selectedSort = sender.selectedSegmentIndex;
    [self performSearchAppending:NO];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runDelayedSearch) object:nil];
    [self performSelector:@selector(runDelayedSearch) withObject:nil afterDelay:0.45];
}

- (void)runDelayedSearch { [self performSearchAppending:NO]; }

- (void)performSearchAppending:(BOOL)append {
    if (self.loading || ![self hasResolvedCompatibility]) return;
    self.loading = YES;
    NSString *query = self.searchController.searchBar.text ?: @"";
    NSString *sortIndex = self.selectedSortIndex;
    NSString *category = self.selectedCategory ?: @"";
    NSString *environment = self.selectedEnvironment ?: @"";
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    UIBarButtonItem *spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    self.navigationItem.rightBarButtonItems = @[self.filterButton, spinnerItem];

    NSDictionary *filters = @{
        @"isModpack": @NO,
        @"projectType": AmethystContentProjectType(self.contentType),
        @"name": query,
        @"mcVersion": self.minecraftVersion,
        @"loader": self.contentType == AmethystContentTypeMod ? (self.loader ?: @"") : @"",
        @"category": category,
        @"environment": environment,
        @"index": sortIndex
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *result = [self.api searchModWithFilters:filters
            previousPageResult:append ? [self.results mutableCopy] : nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            self.navigationItem.rightBarButtonItems = @[self.filterButton];
            NSString *currentQuery = self.searchController.searchBar.text ?: @"";
            if (![query isEqualToString:currentQuery] ||
                ![sortIndex isEqualToString:self.selectedSortIndex] ||
                ![category isEqualToString:self.selectedCategory ?: @""] ||
                ![environment isEqualToString:self.selectedEnvironment ?: @""]) {
                [self performSearchAppending:NO];
                return;
            }
            if (result) self.results = result;
            else showDialog(@"Modrinth search failed", self.api.lastError.localizedDescription);
            [self.tableView reloadData];
        });
    });
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.searchController.searchBar.text.length > 0) return @"Search Results";
    if (self.selectedCategory.length > 0 || self.selectedEnvironment.length > 0) return @"Filtered Results";
    return @[@"Featured for You", @"Most Downloaded", @"Recently Updated"][self.selectedSort];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.results.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.results.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"EmptyResult"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"EmptyResult"];
        cell.backgroundColor = UIColor.clearColor;
        cell.imageView.image = [UIImage systemImageNamed:@"magnifyingglass"];
        cell.textLabel.text = [self hasResolvedCompatibility]
            ? [NSString stringWithFormat:@"No compatible %@ found",
                AmethystContentPlural(self.contentType).lowercaseString]
            : (self.contentType == AmethystContentTypeMod
                ? @"Select an installed Fabric, Quilt, Forge or NeoForge version in this profile first."
                : @"Select a Minecraft version in this profile first.");
        cell.detailTextLabel.text = [self hasResolvedCompatibility]
            ? @"Try another search, filter, or sort option."
            : @"Return to the profile and choose a compatible game version.";
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.userInteractionEnabled = NO;
        return cell;
    }

    AmethystModStoreCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModStoreCell"];
    if (!cell) cell = [[AmethystModStoreCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ModStoreCell"];
    NSDictionary *item = self.results[indexPath.row];
    BOOL installed = [self.installedProjectIds containsObject:item[@"id"]];
    [cell configureWithItem:item installed:installed metadata:[self metadataForItem:item]];
    [cell.getButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    cell.getButton.tag = indexPath.row;
    [cell.getButton addTarget:self action:@selector(getButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    if (!self.api.reachedLastPage && indexPath.row == self.results.count - 1) {
        [self performSearchAppending:YES];
    }
    return cell;
}

- (NSString *)metadataForItem:(NSDictionary *)item {
    unsigned long long downloads = [item[@"downloads"] unsignedLongLongValue];
    NSString *downloadText;
    if (downloads >= 1000000) downloadText = [NSString stringWithFormat:@"%.1fM", downloads / 1000000.0];
    else if (downloads >= 1000) downloadText = [NSString stringWithFormat:@"%.1fK", downloads / 1000.0];
    else downloadText = [NSString stringWithFormat:@"%llu", downloads];
    return [NSString stringWithFormat:@"↓ %@ downloads  •  %@",
        downloadText, self.contentType == AmethystContentTypeMod
            ? (self.loader.capitalizedString ?: @"Mod")
            : AmethystContentSingular(self.contentType).capitalizedString];
}

- (void)getButtonTapped:(UIButton *)sender {
    if (sender.tag >= self.results.count) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    AmethystModStoreCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    [self loadVersionsForItem:self.results[sender.tag] fromCell:cell];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.results.count == 0) return;
    NSDictionary *item = self.results[indexPath.row];
    ModrinthModDetailViewController *detail = [[ModrinthModDetailViewController alloc]
        initWithItem:item minecraftVersion:self.minecraftVersion loader:self.versionLoaderFilter
        installed:[self.installedProjectIds containsObject:item[@"id"]]];
    detail.delegate = self;
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)loadVersionsForItem:(NSMutableDictionary *)item fromCell:(UITableViewCell *)cell {
    if ([cell isKindOfClass:AmethystModStoreCell.class]) {
        [(AmethystModStoreCell *)cell setLoading:YES];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *versions = [self.api compatibleVersionsForProject:item[@"id"]
            minecraftVersion:self.minecraftVersion loader:self.versionLoaderFilter includeChangelog:NO];
        NSError *versionError = versions ? nil : self.api.lastError;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([cell isKindOfClass:AmethystModStoreCell.class]) {
                [(AmethystModStoreCell *)cell setLoading:NO];
            }
            if (!versions) {
                showDialog(@"Unable to load versions", versionError.localizedDescription ?:
                    @"Modrinth did not return this project's versions. Please try again.");
                return;
            }
            if (versions.count == 0) {
                showDialog(@"No compatible version", self.contentType == AmethystContentTypeMod
                    ? @"This project has no downloadable version for the selected Minecraft version and loader."
                    : @"This project has no downloadable version for the selected Minecraft version.");
                return;
            }
            [self presentVersions:versions forItem:item sourceView:cell];
        });
    });
}

- (void)presentVersions:(NSArray<NSDictionary *> *)versions
    forItem:(NSDictionary *)item sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item[@"title"]
        message:self.contentType == AmethystContentTypeMod
            ? [NSString stringWithFormat:@"Minecraft %@ • %@", self.minecraftVersion, self.loader.capitalizedString]
            : [NSString stringWithFormat:@"Minecraft %@", self.minecraftVersion]
        preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    NSUInteger count = MIN(versions.count, 12);
    for (NSUInteger index = 0; index < count; index++) {
        NSDictionary *version = versions[index];
        NSString *title = version[@"name"] ?: version[@"version_number"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                if (self.contentType == AmethystContentTypeMod) {
                    [self presentInstallOptionsForVersion:version project:item sourceView:sourceView];
                } else {
                    [self installVersion:version project:item includeDependencies:NO];
                }
            });
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentInstallOptionsForVersion:(NSDictionary *)version
    project:(NSDictionary *)project sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Install options"
        message:@"Required dependencies are recommended. Installing without them may prevent the mod from loading."
        preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Install with Dependencies"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self installVersion:version project:project includeDependencies:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Install Mod Only"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self installVersion:version project:project includeDependencies:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSDictionary *)primaryFileForVersion:(NSDictionary *)version {
    for (NSDictionary *file in version[@"files"]) {
        if ([file[@"primary"] boolValue]) return file;
    }
    return [version[@"files"] firstObject];
}

- (void)installVersion:(NSDictionary *)version project:(NSDictionary *)project
    includeDependencies:(BOOL)includeDependencies {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItems = @[
        self.filterButton, [[UIBarButtonItem alloc] initWithCustomView:spinner]
    ];
    self.navigationItem.prompt = [NSString stringWithFormat:@"Installing %@…", project[@"title"]];

    NSMutableSet *visited = [NSMutableSet new];
    [self installVersion:version visited:visited includeDependencies:includeDependencies completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationItem.rightBarButtonItems = @[self.filterButton];
            self.navigationItem.prompt = nil;
            if (error) {
                showDialog(@"Installation failed", error.localizedDescription);
            } else {
                NSString *projectId = project[@"id"];
                if (projectId.length > 0) [self.installedProjectIds addObject:projectId];
                [self.tableView reloadData];
                NSString *singular = AmethystContentSingular(self.contentType);
                UIAlertController *done = [UIAlertController alertControllerWithTitle:
                    [NSString stringWithFormat:@"%@ installed", singular.capitalizedString]
                    message:includeDependencies
                        ? [NSString stringWithFormat:@"%@ and its required dependencies were added to this profile.", project[@"title"]]
                        : [NSString stringWithFormat:@"%@ was added to this profile.%@", project[@"title"],
                            self.contentType == AmethystContentTypeMod
                                ? @" Dependencies were not installed." : @" Enable it from Minecraft settings."]
                    preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:done animated:YES completion:nil];
            }
        });
    }];
}

- (void)modDetailViewController:(ModrinthModDetailViewController *)controller
    installVersion:(NSDictionary *)version project:(NSDictionary *)project
    includeDependencies:(BOOL)includeDependencies {
    [controller setInstalling:YES];
    NSMutableSet *visited = [NSMutableSet new];
    [self installVersion:version visited:visited includeDependencies:includeDependencies
        completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error) {
                NSString *projectId = project[@"id"];
                if (projectId.length > 0) [self.installedProjectIds addObject:projectId];
                [self.tableView reloadData];
            }
            [controller installationDidFinishWithError:error];
        });
    }];
}

- (void)installVersion:(NSDictionary *)version visited:(NSMutableSet *)visited
    includeDependencies:(BOOL)includeDependencies completion:(void (^)(NSError *error))completion {
    NSString *versionId = version[@"id"];
    if (!versionId) {
        completion(nil);
        return;
    }
    @synchronized (visited) {
        if ([visited containsObject:versionId]) {
            completion(nil);
            return;
        }
        [visited addObject:versionId];
    }

    NSArray *requiredDependencies = includeDependencies
        ? [version[@"dependencies"] filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSDictionary *dependency, NSDictionary *bindings) {
                return [dependency[@"dependency_type"] isEqualToString:@"required"];
            }]]
        : @[];

    dispatch_group_t dependencyGroup = dispatch_group_create();
    __block NSError *dependencyError = nil;
    for (NSDictionary *dependency in requiredDependencies) {
        dispatch_group_enter(dependencyGroup);
        [self resolveDependency:dependency completion:^(NSDictionary *dependencyVersion, NSError *error) {
            if (error || !dependencyVersion) {
                @synchronized (visited) {
                    dependencyError = error ?: [NSError errorWithDomain:@"AmethystModManager" code:2
                        userInfo:@{NSLocalizedDescriptionKey: @"A required Modrinth dependency could not be resolved."}];
                }
                dispatch_group_leave(dependencyGroup);
                return;
            }
            [self installVersion:dependencyVersion visited:visited includeDependencies:YES completion:^(NSError *error) {
                if (error) {
                    @synchronized (visited) { dependencyError = error; }
                }
                dispatch_group_leave(dependencyGroup);
            }];
        }];
    }

    dispatch_group_notify(dependencyGroup, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (dependencyError) {
            completion(dependencyError);
            return;
        }
        [self downloadVersionFile:version completion:completion];
    });
}

- (void)resolveDependency:(NSDictionary *)dependency
    completion:(void (^)(NSDictionary *version, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *resolved;
        if ([dependency[@"version_id"] isKindOfClass:NSString.class]) {
            resolved = [self.api getEndpoint:[NSString stringWithFormat:@"version/%@", dependency[@"version_id"]] params:nil];
        } else if ([dependency[@"project_id"] isKindOfClass:NSString.class]) {
            NSArray *versions = [self.api compatibleVersionsForProject:dependency[@"project_id"]
                minecraftVersion:self.minecraftVersion loader:self.versionLoaderFilter includeChangelog:NO];
            resolved = versions.firstObject;
        }
        completion(resolved, resolved ? nil : self.api.lastError);
    });
}

- (void)downloadVersionFile:(NSDictionary *)version completion:(void (^)(NSError *error))completion {
    NSDictionary *file = [self primaryFileForVersion:version];
    NSURL *url = [NSURL URLWithString:file[@"url"]];
    NSString *filename = [file[@"filename"] lastPathComponent];
    NSString *expectedSuffix = [@"." stringByAppendingString:AmethystContentExtension(self.contentType)];
    if (!url || filename.length == 0 || ![filename.lowercaseString hasSuffix:expectedSuffix]) {
        completion([NSError errorWithDomain:@"AmethystModManager" code:3
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"Modrinth returned a version without a downloadable %@ file.",
                AmethystContentExtension(self.contentType).uppercaseString]}]);
        return;
    }

    NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithURL:url
        completionHandler:^(NSURL *temporaryURL, NSURLResponse *response, NSError *error) {
        if (error) { completion(error); return; }
        NSHTTPURLResponse *http = (id)response;
        if (http.statusCode < 200 || http.statusCode >= 300) {
            completion([NSError errorWithDomain:@"AmethystModManager" code:http.statusCode
                userInfo:@{NSLocalizedDescriptionKey: @"The content download server returned an error."}]);
            return;
        }
        NSString *expectedSHA512 = file[@"hashes"][@"sha512"];
        if (expectedSHA512.length > 0 && ![[self sha512ForFile:temporaryURL.path]
            isEqualToString:expectedSHA512.lowercaseString]) {
            completion([NSError errorWithDomain:@"AmethystModManager" code:4
                userInfo:@{NSLocalizedDescriptionKey: @"The downloaded file failed its SHA-512 integrity check."}]);
            return;
        }
        NSError *installError = nil;
        [self installDownloadedFile:temporaryURL.path filename:filename version:version error:&installError];
        completion(installError);
    }];
    [task resume];
}

- (BOOL)installDownloadedFile:(NSString *)downloadPath filename:(NSString *)filename
    version:(NSDictionary *)version error:(NSError **)error {
    NSError *operationError = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:self.modsDirectory
        withIntermediateDirectories:YES attributes:nil error:&operationError];
    if (operationError) {
        if (error) *error = operationError;
        return NO;
    }

    NSString *stagedPath = [self.modsDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@".amethyst-download-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager moveItemAtPath:downloadPath toPath:stagedPath error:&operationError];
    if (operationError) {
        if (error) *error = operationError;
        return NO;
    }

    @synchronized (self) {
        NSString *destination = [self.modsDirectory stringByAppendingPathComponent:filename];
        if ([NSFileManager.defaultManager fileExistsAtPath:destination]) {
            [NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:destination]
                withItemAtURL:[NSURL fileURLWithPath:stagedPath] backupItemName:nil
                options:0 resultingItemURL:nil error:&operationError];
        } else {
            [NSFileManager.defaultManager moveItemAtPath:stagedPath toPath:destination error:&operationError];
        }
        [NSFileManager.defaultManager removeItemAtPath:stagedPath error:nil];
        if (operationError) {
            if (error) *error = operationError;
            return NO;
        }

        if (self.contentType == AmethystContentTypeMod) {
            [NSFileManager.defaultManager removeItemAtPath:
                [destination stringByAppendingString:AmethystDisabledModSuffix] error:nil];
        }

        NSString *registryPath = [self.modsDirectory stringByAppendingPathComponent:@".amethyst-modrinth.json"];
        NSData *registryData = [NSData dataWithContentsOfFile:registryPath];
        NSMutableDictionary *registry = registryData
            ? [[NSJSONSerialization JSONObjectWithData:registryData options:NSJSONReadingMutableContainers error:nil] mutableCopy]
            : [NSMutableDictionary new];
        if (![registry isKindOfClass:NSMutableDictionary.class]) registry = [NSMutableDictionary new];

        NSString *projectId = version[@"project_id"];
        NSString *previousFilename = projectId.length > 0 ? registry[projectId] : nil;
        if (projectId.length > 0 && previousFilename.length > 0 &&
            ![previousFilename isEqualToString:filename]) {
            NSString *previousPath = [self.modsDirectory stringByAppendingPathComponent:previousFilename.lastPathComponent];
            [NSFileManager.defaultManager removeItemAtPath:previousPath error:nil];
            if (self.contentType == AmethystContentTypeMod) {
                [NSFileManager.defaultManager removeItemAtPath:
                    [previousPath stringByAppendingString:AmethystDisabledModSuffix] error:nil];
            }
        }
        if (projectId.length > 0) registry[projectId] = filename;

        NSData *updatedData = [NSJSONSerialization dataWithJSONObject:registry
            options:NSJSONWritingPrettyPrinted error:nil];
        [updatedData writeToFile:registryPath options:NSDataWritingAtomic error:nil];
    }
    return YES;
}

- (NSString *)sha512ForFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    unsigned char digest[CC_SHA512_DIGEST_LENGTH];
    CC_SHA512(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_SHA512_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA512_DIGEST_LENGTH; index++) {
        [hash appendFormat:@"%02x", digest[index]];
    }
    return hash;
}

@end
