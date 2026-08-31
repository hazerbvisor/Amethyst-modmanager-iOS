#import "AFNetworking.h"
#import "ModManagerViewController.h"
#import "UIKit+AFNetworking.h"
#import "installer/modpack/ModrinthAPI.h"
#import "LauncherPreferences.h"
#import "utils.h"

#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const AmethystDisabledModSuffix = @".disabled";

@interface ModrinthModBrowserViewController : UITableViewController<UISearchResultsUpdating>
- (instancetype)initWithProfile:(NSDictionary *)profile modsDirectory:(NSString *)modsDirectory;
@end

@interface ModManagerViewController ()<UIDocumentPickerDelegate>
@property(nonatomic) NSMutableDictionary *profile;
@property(nonatomic) NSString *modsDirectory;
@property(nonatomic) NSMutableArray<NSString *> *mods;
@end

@implementation ModManagerViewController

- (instancetype)initWithProfile:(NSMutableDictionary *)profile {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.profile = profile;
        self.title = @"Manage Mods";

        NSString *relativeGameDirectory = profile[@"gameDir"];
        if (relativeGameDirectory.length == 0) relativeGameDirectory = @".";
        NSString *instanceRoot = [NSString stringWithFormat:@"%s/instances/%@",
            getenv("POJAV_HOME"), getPrefObject(@"general.game_directory")];
        NSString *gameDirectory = [[instanceRoot stringByAppendingPathComponent:relativeGameDirectory]
            stringByStandardizingPath];
        self.modsDirectory = [gameDirectory stringByAppendingPathComponent:@"mods"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelection = NO;

    UIAction *browse = [UIAction actionWithTitle:@"Browse Modrinth"
        image:[UIImage systemImageNamed:@"magnifyingglass"] identifier:nil handler:^(__kindof UIAction *action) {
        ModrinthModBrowserViewController *browser = [[ModrinthModBrowserViewController alloc]
            initWithProfile:self.profile modsDirectory:self.modsDirectory];
        [self.navigationController pushViewController:browser animated:YES];
    }];
    UIAction *importJar = [UIAction actionWithTitle:@"Import JAR from Files"
        image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(__kindof UIAction *action) {
        [self actionImportJar];
    }];
    UIMenu *menu = [UIMenu menuWithTitle:@"Add Mod" children:@[browse, importJar]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:menu];
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
        showDialog(@"Unable to open mods folder", error.localizedDescription);
        self.mods = [NSMutableArray new];
        return;
    }

    NSArray<NSString *> *contents = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:self.modsDirectory error:&error];
    NSPredicate *jarPredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        NSString *lowercaseName = name.lowercaseString;
        return [lowercaseName hasSuffix:@".jar"] || [lowercaseName hasSuffix:@".jar.disabled"];
    }];
    self.mods = [[contents filteredArrayUsingPredicate:jarPredicate] mutableCopy] ?: [NSMutableArray new];
    [self.mods sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.tableView reloadData];
}

- (void)actionImportJar {
    UTType *jarType = [UTType typeWithFilenameExtension:@"jar"] ?: [UTType data];
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
    for (NSURL *url in urls) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"jar"]) continue;
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
        if (!error) {
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
        UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"Check compatibility"
            message:@"Imported JARs cannot be verified automatically. Make sure each mod matches this profile's Minecraft version and mod loader."
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
    return @"Modrinth installs are filtered for this profile. Imported JARs are not compatibility checked. Disabled mods remain in the profile but are not loaded by Minecraft.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ModCell"];
    cell.accessoryView = nil;
    cell.imageView.image = [UIImage systemImageNamed:@"shippingbox"];

    if (self.mods.count == 0) {
        cell.textLabel.text = @"No mods installed";
        cell.detailTextLabel.text = @"Tap + to browse Modrinth or import a JAR.";
        cell.textLabel.enabled = cell.detailTextLabel.enabled = NO;
        return cell;
    }

    NSString *filename = self.mods[indexPath.row];
    BOOL enabled = ![filename.lowercaseString hasSuffix:AmethystDisabledModSuffix];
    NSString *displayName = enabled ? filename : [filename substringToIndex:filename.length - AmethystDisabledModSuffix.length];
    cell.textLabel.text = displayName;
    cell.detailTextLabel.text = enabled ? @"Enabled" : @"Disabled";
    cell.textLabel.enabled = cell.detailTextLabel.enabled = YES;

    UISwitch *toggle = [UISwitch new];
    toggle.on = enabled;
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(toggleMod:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)toggleMod:(UISwitch *)sender {
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

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mods.count == 0) return nil;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *filename = self.mods[indexPath.row];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete mod?"
            message:filename preferredStyle:UIAlertControllerStyleActionSheet];
        alert.popoverPresentationController.sourceView = sourceView;
        alert.popoverPresentationController.sourceRect = sourceView.bounds;
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
            handler:^(UIAlertAction *action) { completionHandler(NO); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive
            handler:^(UIAlertAction *action) {
            NSError *error = nil;
            [NSFileManager.defaultManager removeItemAtPath:
                [self.modsDirectory stringByAppendingPathComponent:filename] error:&error];
            if (error) showDialog(@"Delete failed", error.localizedDescription);
            [self reloadMods];
            completionHandler(error == nil);
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

@end

#pragma mark - Modrinth browser

@interface ModrinthModBrowserViewController ()
@property(nonatomic) NSDictionary *profile;
@property(nonatomic) NSString *modsDirectory;
@property(nonatomic) NSString *minecraftVersion;
@property(nonatomic) NSString *loader;
@property(nonatomic) UISearchController *searchController;
@property(nonatomic) NSMutableArray *results;
@property(nonatomic) ModrinthAPI *api;
@property(nonatomic) BOOL loading;
@end

@implementation ModrinthModBrowserViewController

- (instancetype)initWithProfile:(NSDictionary *)profile modsDirectory:(NSString *)modsDirectory {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.profile = profile;
        self.modsDirectory = modsDirectory;
        self.title = @"Browse Modrinth";
        [self resolveCompatibility];
    }
    return self;
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
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.prompt = [NSString stringWithFormat:@"%@ • %@",
        self.minecraftVersion ?: @"Unknown Minecraft version", self.loader.capitalizedString ?: @"Unknown loader"];

    if (self.minecraftVersion.length == 0 || self.loader.length == 0) {
        self.searchController.searchBar.userInteractionEnabled = NO;
        self.results = nil;
        [self.tableView reloadData];
    } else {
        [self performSearchAppending:NO];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runDelayedSearch) object:nil];
    [self performSelector:@selector(runDelayedSearch) withObject:nil afterDelay:0.45];
}

- (void)runDelayedSearch { [self performSearchAppending:NO]; }

- (void)performSearchAppending:(BOOL)append {
    if (self.loading) return;
    self.loading = YES;
    NSString *query = self.searchController.searchBar.text ?: @"";
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    NSDictionary *filters = @{
        @"isModpack": @NO,
        @"name": query,
        @"mcVersion": self.minecraftVersion,
        @"loader": self.loader
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *result = [self.api searchModWithFilters:filters
            previousPageResult:append ? [self.results mutableCopy] : nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            self.navigationItem.rightBarButtonItem = nil;
            NSString *currentQuery = self.searchController.searchBar.text ?: @"";
            if (![query isEqualToString:currentQuery]) {
                [self performSearchAppending:NO];
                return;
            }
            if (result) self.results = result;
            else showDialog(@"Modrinth search failed", self.api.lastError.localizedDescription);
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.results.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchResult"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SearchResult"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [UIImage imageNamed:@"DefaultProfile"];

    if (self.results.count == 0) {
        cell.textLabel.text = (self.minecraftVersion.length && self.loader.length)
            ? @"No compatible mods found"
            : @"Select an installed Fabric, Quilt, Forge or NeoForge version in this profile first.";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.userInteractionEnabled = NO;
        return cell;
    }

    cell.userInteractionEnabled = YES;
    NSDictionary *item = self.results[indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"description"];
    NSURL *imageURL = [NSURL URLWithString:item[@"imageUrl"]];
    if (imageURL) {
        [cell.imageView setImageWithURL:imageURL placeholderImage:[UIImage imageNamed:@"DefaultProfile"]];
    }
    if (!self.api.reachedLastPage && indexPath.row == self.results.count - 1) {
        [self performSearchAppending:YES];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.results.count == 0) return;
    NSMutableDictionary *item = self.results[indexPath.row];
    [self loadVersionsForItem:item fromCell:[tableView cellForRowAtIndexPath:indexPath]];
}

- (void)loadVersionsForItem:(NSMutableDictionary *)item fromCell:(UITableViewCell *)cell {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    cell.accessoryView = spinner;
    [spinner startAnimating];
    NSDictionary *params = @{
        @"game_versions": [NSString stringWithFormat:@"[\"%@\"]", self.minecraftVersion],
        @"loaders": [NSString stringWithFormat:@"[\"%@\"]", self.loader]
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *versions = [self.api getEndpoint:[NSString stringWithFormat:@"project/%@/version", item[@"id"]]
            params:params];
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if (versions.count == 0) {
                showDialog(@"No compatible version", @"This project has no downloadable version for the selected Minecraft version and loader.");
                return;
            }
            [self presentVersions:versions forItem:item sourceView:cell];
        });
    });
}

- (void)presentVersions:(NSArray<NSDictionary *> *)versions
    forItem:(NSDictionary *)item sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item[@"title"]
        message:[NSString stringWithFormat:@"Minecraft %@ • %@", self.minecraftVersion, self.loader.capitalizedString]
        preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    NSUInteger count = MIN(versions.count, 12);
    for (NSUInteger index = 0; index < count; index++) {
        NSDictionary *version = versions[index];
        NSString *title = version[@"name"] ?: version[@"version_number"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self installVersion:version project:item];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSDictionary *)primaryFileForVersion:(NSDictionary *)version {
    for (NSDictionary *file in version[@"files"]) {
        if ([file[@"primary"] boolValue]) return file;
    }
    return [version[@"files"] firstObject];
}

- (void)installVersion:(NSDictionary *)version project:(NSDictionary *)project {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    self.navigationItem.prompt = [NSString stringWithFormat:@"Installing %@…", project[@"title"]];

    NSMutableSet *visited = [NSMutableSet new];
    [self installVersion:version visited:visited completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationItem.rightBarButtonItem = nil;
            self.navigationItem.prompt = [NSString stringWithFormat:@"%@ • %@",
                self.minecraftVersion, self.loader.capitalizedString];
            if (error) {
                showDialog(@"Installation failed", error.localizedDescription);
            } else {
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Mod installed"
                    message:[NSString stringWithFormat:@"%@ and its required dependencies were added to this profile.", project[@"title"]]
                    preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:done animated:YES completion:nil];
            }
        });
    }];
}

- (void)installVersion:(NSDictionary *)version visited:(NSMutableSet *)visited
    completion:(void (^)(NSError *error))completion {
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

    NSArray *requiredDependencies = [version[@"dependencies"] filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSDictionary *dependency, NSDictionary *bindings) {
            return [dependency[@"dependency_type"] isEqualToString:@"required"];
        }]];

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
            [self installVersion:dependencyVersion visited:visited completion:^(NSError *error) {
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
            NSDictionary *params = @{
                @"game_versions": [NSString stringWithFormat:@"[\"%@\"]", self.minecraftVersion],
                @"loaders": [NSString stringWithFormat:@"[\"%@\"]", self.loader]
            };
            NSArray *versions = [self.api getEndpoint:
                [NSString stringWithFormat:@"project/%@/version", dependency[@"project_id"]] params:params];
            resolved = versions.firstObject;
        }
        completion(resolved, resolved ? nil : self.api.lastError);
    });
}

- (void)downloadVersionFile:(NSDictionary *)version completion:(void (^)(NSError *error))completion {
    NSDictionary *file = [self primaryFileForVersion:version];
    NSURL *url = [NSURL URLWithString:file[@"url"]];
    NSString *filename = [file[@"filename"] lastPathComponent];
    if (!url || filename.length == 0 || ![filename.lowercaseString hasSuffix:@".jar"]) {
        completion([NSError errorWithDomain:@"AmethystModManager" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Modrinth returned a version without a downloadable JAR."}]);
        return;
    }

    NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithURL:url
        completionHandler:^(NSURL *temporaryURL, NSURLResponse *response, NSError *error) {
        if (error) { completion(error); return; }
        NSHTTPURLResponse *http = (id)response;
        if (http.statusCode < 200 || http.statusCode >= 300) {
            completion([NSError errorWithDomain:@"AmethystModManager" code:http.statusCode
                userInfo:@{NSLocalizedDescriptionKey: @"The mod download server returned an error."}]);
            return;
        }
        NSString *expectedSHA512 = file[@"hashes"][@"sha512"];
        if (expectedSHA512.length > 0 && ![[self sha512ForFile:temporaryURL.path]
            isEqualToString:expectedSHA512.lowercaseString]) {
            completion([NSError errorWithDomain:@"AmethystModManager" code:4
                userInfo:@{NSLocalizedDescriptionKey: @"The downloaded JAR failed its SHA-512 integrity check."}]);
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
    NSError *localError = nil;
    NSError **outError = error ?: &localError;
    [NSFileManager.defaultManager createDirectoryAtPath:self.modsDirectory
        withIntermediateDirectories:YES attributes:nil error:outError];
    if (*outError) return NO;

    NSString *stagedPath = [self.modsDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@".amethyst-download-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager moveItemAtPath:downloadPath toPath:stagedPath error:outError];
    if (*outError) return NO;

    @synchronized (self) {
        NSString *destination = [self.modsDirectory stringByAppendingPathComponent:filename];
        if ([NSFileManager.defaultManager fileExistsAtPath:destination]) {
            [NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:destination]
                withItemAtURL:[NSURL fileURLWithPath:stagedPath] backupItemName:nil
                options:0 resultingItemURL:nil error:outError];
        } else {
            [NSFileManager.defaultManager moveItemAtPath:stagedPath toPath:destination error:outError];
        }
        [NSFileManager.defaultManager removeItemAtPath:stagedPath error:nil];
        if (*outError) return NO;

        [NSFileManager.defaultManager removeItemAtPath:
            [destination stringByAppendingString:AmethystDisabledModSuffix] error:nil];

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
            [NSFileManager.defaultManager removeItemAtPath:
                [previousPath stringByAppendingString:AmethystDisabledModSuffix] error:nil];
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
