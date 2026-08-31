#import "ModrinthModDetailViewController.h"

#import "LiquidGlassCompat.h"
#import "UIKit+AFNetworking.h"
#import "installer/modpack/ModrinthAPI.h"

#import <math.h>

static NSString *AmethystCompactNumber(NSNumber *number) {
    if (![number respondsToSelector:@selector(unsignedLongLongValue)]) return @"0";
    unsigned long long value = number.unsignedLongLongValue;
    if (value >= 1000000) return [NSString stringWithFormat:@"%.1fM", value / 1000000.0];
    if (value >= 1000) return [NSString stringWithFormat:@"%.1fK", value / 1000.0];
    return [NSString stringWithFormat:@"%llu", value];
}

static NSString *AmethystPlainTextFromMarkdown(NSString *markdown) {
    if (![markdown isKindOfClass:NSString.class] || markdown.length == 0) return @"No description was provided.";
    NSMutableString *text = markdown.mutableCopy;
    NSArray<NSArray<NSString *> *> *rules = @[
        @[@"!\\[([^\\]]*)\\]\\([^\\)]*\\)", @"$1"],
        @[@"\\[([^\\]]+)\\]\\([^\\)]*\\)", @"$1"],
        @[@"(?m)^#{1,6}\\s*", @""],
        @[@"[*_`]{1,3}", @""],
        @[@"<[^>]+>", @""]
    ];
    for (NSArray<NSString *> *rule in rules) {
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:rule[0]
            options:0 error:nil];
        [expression replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length)
            withTemplate:rule[1]];
    }
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *AmethystReadableValue(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"Unknown";
    return [[value stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
}

static NSURL *AmethystDetailArtworkURL(id value) {
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

static void AmethystAppendArtworkURL(NSMutableArray<NSURL *> *urls, id value) {
    NSURL *url = AmethystDetailArtworkURL(value);
    if (url && ![urls containsObject:url]) [urls addObject:url];
}

@interface ModrinthModDetailViewController ()
@property(nonatomic, strong) NSDictionary *item;
@property(nonatomic, strong) NSDictionary *project;
@property(nonatomic, strong) NSArray<NSDictionary *> *versions;
@property(nonatomic, copy) NSString *minecraftVersion;
@property(nonatomic, copy) NSString *loader;
@property(nonatomic, strong) ModrinthAPI *api;
@property(nonatomic, strong) NSError *versionsError;
@property(nonatomic) BOOL installed;
@property(nonatomic) BOOL installing;
@property(nonatomic, copy) NSString *artworkLoadToken;

@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *summaryLabel;
@property(nonatomic, strong) UILabel *statsLabel;
@property(nonatomic, strong) UIButton *downloadButton;
@property(nonatomic, strong) UIActivityIndicatorView *downloadSpinner;
@property(nonatomic, strong) UISegmentedControl *tabs;
@property(nonatomic, strong) UISwitch *dependencySwitch;
@end

@implementation ModrinthModDetailViewController

- (instancetype)initWithItem:(NSDictionary *)item
    minecraftVersion:(NSString *)minecraftVersion
    loader:(NSString *)loader
    installed:(BOOL)installed {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.item = item;
        self.minecraftVersion = minecraftVersion;
        self.loader = loader;
        self.installed = installed;
        self.title = item[@"title"] ?: @"Mod Details";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.api = [ModrinthAPI new];
    self.versions = @[];
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110.0;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self buildHeroHeader];
    [self loadProjectDetails];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (header && fabs(header.frame.size.width - self.tableView.bounds.size.width) > 0.5) {
        CGRect frame = header.frame;
        frame.size.width = self.tableView.bounds.size.width;
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
}

- (void)buildHeroHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 286.0)];
    UIVisualEffectView *glass = AmethystCreateGlassView(28.0, YES, nil);
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:glass];
    UIView *content = glass.contentView;

    self.iconView = [UIImageView new];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFill;
    self.iconView.clipsToBounds = YES;
    self.iconView.layer.cornerRadius = 22.0;
    self.iconView.layer.cornerCurve = kCACornerCurveContinuous;
    self.iconView.backgroundColor = UIColor.tertiarySystemFillColor;
    [content addSubview:self.iconView];

    self.nameLabel = [UILabel new];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.text = self.item[@"title"];
    [content addSubview:self.nameLabel];

    self.summaryLabel = [UILabel new];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.summaryLabel.textColor = UIColor.secondaryLabelColor;
    self.summaryLabel.numberOfLines = 2;
    self.summaryLabel.text = self.item[@"description"];
    [content addSubview:self.summaryLabel];

    self.statsLabel = [UILabel new];
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statsLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.statsLabel.textColor = UIColor.secondaryLabelColor;
    [content addSubview:self.statsLabel];

    self.downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.downloadButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    self.downloadButton.tintColor = UIColor.whiteColor;
    [self.downloadButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.downloadButton setImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"] forState:UIControlStateNormal];
    self.downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, -5, 0, 5);
    [self.downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:self.downloadButton];
    AmethystInstallGlassBackground(self.downloadButton, 21.0, YES, UIColor.systemGreenColor);

    self.downloadSpinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.downloadSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.downloadSpinner.hidesWhenStopped = YES;
    [self.downloadButton addSubview:self.downloadSpinner];

    self.tabs = [[UISegmentedControl alloc]
        initWithItems:@[@"Description", @"Gallery", @"Changelog", @"Versions"]];
    self.tabs.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabs.selectedSegmentIndex = 0;
    [self.tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:self.tabs];

    [NSLayoutConstraint activateConstraints:@[
        [glass.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
        [glass.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [glass.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [glass.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8.0],

        [self.iconView.topAnchor constraintEqualToAnchor:content.topAnchor constant:18.0],
        [self.iconView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18.0],
        [self.iconView.widthAnchor constraintEqualToConstant:104.0],
        [self.iconView.heightAnchor constraintEqualToConstant:104.0],

        [self.nameLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:18.0],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:16.0],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18.0],
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:3.0],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [self.statsLabel.topAnchor constraintEqualToAnchor:self.summaryLabel.bottomAnchor constant:7.0],
        [self.statsLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.statsLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [self.downloadButton.topAnchor constraintEqualToAnchor:self.statsLabel.bottomAnchor constant:9.0],
        [self.downloadButton.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.downloadButton.widthAnchor constraintEqualToConstant:148.0],
        [self.downloadButton.heightAnchor constraintEqualToConstant:42.0],
        [self.downloadSpinner.centerXAnchor constraintEqualToAnchor:self.downloadButton.centerXAnchor],
        [self.downloadSpinner.centerYAnchor constraintEqualToAnchor:self.downloadButton.centerYAnchor],

        [self.tabs.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18.0],
        [self.tabs.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18.0],
        [self.tabs.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16.0],
        [self.tabs.heightAnchor constraintEqualToConstant:36.0]
    ]];

    self.tableView.tableHeaderView = header;
    [self updateHero];
}

- (void)loadArtworkURLs:(NSArray<NSURL *> *)urls
    atIndex:(NSUInteger)index
    token:(NSString *)token
    placeholder:(UIImage *)placeholder {
    if (index >= urls.count || ![self.artworkLoadToken isEqualToString:token]) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:urls[index]
        cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:30.0];
    __weak typeof(self) weakSelf = self;
    [self.iconView setImageWithURLRequest:request placeholderImage:placeholder
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if ([strongSelf.artworkLoadToken isEqualToString:token]) strongSelf.iconView.image = image;
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf.artworkLoadToken isEqualToString:token]) return;
        [strongSelf loadArtworkURLs:urls atIndex:index + 1 token:token placeholder:placeholder];
    }];
}

- (void)loadArtworkURLs:(NSArray<NSURL *> *)urls {
    [self.iconView cancelImageDownloadTask];
    UIImage *placeholder = [UIImage imageNamed:@"DefaultProfile"];
    self.iconView.image = placeholder;
    self.artworkLoadToken = NSUUID.UUID.UUIDString;
    [self loadArtworkURLs:urls atIndex:0 token:self.artworkLoadToken placeholder:placeholder];
}

- (void)updateHero {
    NSDictionary *project = self.project ?: self.item;
    self.nameLabel.text = project[@"title"] ?: self.item[@"title"];
    self.summaryLabel.text = project[@"description"] ?: self.item[@"description"];
    NSNumber *downloads = project[@"downloads"] ?: self.item[@"downloads"] ?: @0;
    NSNumber *followers = project[@"followers"] ?: @0;
    NSArray *categories = project[@"categories"] ?: self.item[@"categories"];
    NSString *category = categories.firstObject ?: @"Mod";
    self.statsLabel.text = [NSString stringWithFormat:@"↓ %@ downloads  •  ♡ %@ followers  •  %@",
        AmethystCompactNumber(downloads), AmethystCompactNumber(followers), AmethystReadableValue(category)];
    [self.downloadButton setTitle:self.installed ? @"  REINSTALL" : @"  GET" forState:UIControlStateNormal];

    NSMutableArray<NSURL *> *artworkURLs = [NSMutableArray new];
    AmethystAppendArtworkURL(artworkURLs, project[@"icon_url"]);
    AmethystAppendArtworkURL(artworkURLs, project[@"raw_icon_url"]);
    AmethystAppendArtworkURL(artworkURLs, self.item[@"imageUrl"]);
    NSArray *gallery = [project[@"gallery"] isKindOfClass:NSArray.class] ? project[@"gallery"] : @[];
    for (id value in gallery) {
        if ([value isKindOfClass:NSDictionary.class] && [value[@"featured"] boolValue]) {
            AmethystAppendArtworkURL(artworkURLs, value[@"url"]);
        }
    }
    for (id value in gallery) {
        if ([value isKindOfClass:NSDictionary.class]) AmethystAppendArtworkURL(artworkURLs, value[@"url"]);
    }
    AmethystAppendArtworkURL(artworkURLs, self.item[@"fallbackImageUrl"]);
    [self loadArtworkURLs:artworkURLs];
}

- (void)loadProjectDetails {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    NSString *projectId = self.item[@"id"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *project = [self.api getEndpoint:[NSString stringWithFormat:@"project/%@", projectId]
            params:nil];
        NSError *projectError = project ? nil : self.api.lastError;
        NSArray *versions = [self.api compatibleVersionsForProject:projectId
            minecraftVersion:self.minecraftVersion loader:self.loader includeChangelog:YES];
        NSError *versionError = versions ? nil : self.api.lastError;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationItem.rightBarButtonItem = nil;
            if (project) self.project = project;
            if (versions) self.versions = versions;
            self.versionsError = versionError;
            [self updateHero];
            [self.tableView reloadData];
            if (!project && !versions) [self showMessageWithTitle:@"Unable to load details"
                message:versionError.localizedDescription ?: projectError.localizedDescription ?:
                    @"Modrinth did not return this project."];
        });
    });
}

- (void)tabChanged:(UISegmentedControl *)sender {
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 1) return 4;
    switch (self.tabs.selectedSegmentIndex) {
        case 1: return MAX([self.project[@"gallery"] count], 1);
        case 2: return MAX(MIN(self.versions.count, 20), 1);
        case 3: return MAX(self.versions.count, 1);
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"Compatibility";
    return @[@"About This Mod", @"Gallery", @"Latest Changes", @"Available Versions"]
        [self.tabs.selectedSegmentIndex];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"Dependency installation can be changed before downloading. Disabling it may prevent the mod from launching.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) return [self compatibilityCellForRow:indexPath.row];
    switch (self.tabs.selectedSegmentIndex) {
        case 1: return [self galleryCellForRow:indexPath.row];
        case 2: return [self changelogCellForRow:indexPath.row];
        case 3: return [self versionCellForRow:indexPath.row];
        default: return [self descriptionCell];
    }
}

- (UITableViewCell *)descriptionCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *body = [UILabel new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    body.textColor = UIColor.secondaryLabelColor;
    body.numberOfLines = 0;
    body.text = AmethystPlainTextFromMarkdown(self.project[@"body"] ?: self.item[@"description"]);
    [cell.contentView addSubview:body];
    [NSLayoutConstraint activateConstraints:@[
        [body.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14.0],
        [body.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [body.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
        [body.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14.0]
    ]];
    return cell;
}

- (UITableViewCell *)galleryCellForRow:(NSInteger)row {
    NSArray *gallery = self.project[@"gallery"];
    if (gallery.count == 0) return [self emptyCellWithTitle:@"No gallery images"
        detail:@"This project has not uploaded any screenshots."];
    NSDictionary *image = gallery[row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIImageView *imageView = [UIImageView new];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 18.0;
    imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.backgroundColor = UIColor.tertiarySystemFillColor;
    NSURL *galleryURL = AmethystDetailArtworkURL(image[@"url"]);
    if (galleryURL) [imageView setImageWithURL:galleryURL placeholderImage:nil];
    [cell.contentView addSubview:imageView];
    [NSLayoutConstraint activateConstraints:@[
        [imageView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
        [imageView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
        [imageView.heightAnchor constraintEqualToConstant:230.0]
    ]];
    return cell;
}

- (UITableViewCell *)changelogCellForRow:(NSInteger)row {
    if (self.versions.count == 0) return [self emptyCellWithTitle:
        self.versionsError ? @"Unable to load changelog" : @"No changelog available"
        detail:self.versionsError.localizedDescription ?:
            @"No compatible versions were returned for this profile."];
    NSDictionary *version = self.versions[row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = version[@"name"] ?: version[@"version_number"] ?: @"Version";
    cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    NSString *changelog = AmethystPlainTextFromMarkdown(version[@"changelog"]);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@",
        [self displayDate:version[@"date_published"]], changelog];
    cell.detailTextLabel.numberOfLines = 4;
    return cell;
}

- (UITableViewCell *)versionCellForRow:(NSInteger)row {
    if (self.versions.count == 0) return [self emptyCellWithTitle:
        self.versionsError ? @"Unable to load versions" : @"No compatible versions"
        detail:self.versionsError.localizedDescription ?:
            [NSString stringWithFormat:@"Nothing matches Minecraft %@ and %@.",
                self.minecraftVersion, self.loader.capitalizedString]];
    NSDictionary *version = self.versions[row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = version[@"name"] ?: version[@"version_number"] ?: @"Version";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %@  •  %@",
        version[@"version_number"] ?: @"Unknown",
        AmethystReadableValue(version[@"version_type"]),
        [self displayDate:version[@"date_published"]]];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 74, 34);
    button.tag = row;
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [button setTitle:@"GET" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(versionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    AmethystInstallGlassBackground(button, 17.0, YES, nil);
    cell.accessoryView = button;
    return cell;
}

- (UITableViewCell *)compatibilityCellForRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray *gameVersions = self.project[@"game_versions"];
    NSArray *loaders = self.project[@"loaders"];
    NSArray *environments = self.project[@"environment"];
    switch (row) {
        case 0:
            cell.imageView.image = [UIImage systemImageNamed:@"gamecontroller"];
            cell.textLabel.text = @"Minecraft";
            cell.detailTextLabel.text = gameVersions.count > 0
                ? [self compactList:gameVersions fallback:self.minecraftVersion] : self.minecraftVersion;
            break;
        case 1:
            cell.imageView.image = [UIImage systemImageNamed:@"shippingbox"];
            cell.textLabel.text = @"Platforms";
            cell.detailTextLabel.text = loaders.count > 0
                ? [self compactList:loaders fallback:self.loader] : self.loader.capitalizedString;
            break;
        case 2:
            cell.imageView.image = [UIImage systemImageNamed:@"desktopcomputer"];
            cell.textLabel.text = @"Environment";
            cell.detailTextLabel.text = environments.count > 0
                ? AmethystReadableValue(environments.firstObject) : @"Client";
            break;
        default:
            cell.imageView.image = [UIImage systemImageNamed:@"square.stack.3d.up"];
            cell.textLabel.text = @"Install required dependencies";
            if (!self.dependencySwitch) {
                self.dependencySwitch = [UISwitch new];
                self.dependencySwitch.on = YES;
            }
            self.dependencySwitch.enabled = !self.installing;
            cell.accessoryView = self.dependencySwitch;
            break;
    }
    return cell;
}

- (UITableViewCell *)emptyCellWithTitle:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
    return cell;
}

- (NSString *)compactList:(NSArray<NSString *> *)values fallback:(NSString *)fallback {
    if (values.count == 0) return fallback ?: @"Unknown";
    NSUInteger shown = MIN(values.count, 4);
    NSArray *visible = [values subarrayWithRange:NSMakeRange(0, shown)];
    NSMutableArray<NSString *> *readable = [NSMutableArray new];
    for (id value in visible) {
        if ([value isKindOfClass:NSString.class]) [readable addObject:AmethystReadableValue(value)];
    }
    NSString *result = [readable componentsJoinedByString:@", "];
    if (result.length == 0) result = fallback ?: @"Unknown";
    if (values.count > shown) result = [result stringByAppendingFormat:@" +%lu", (unsigned long)(values.count - shown)];
    return result;
}

- (NSString *)displayDate:(NSString *)date {
    if (![date isKindOfClass:NSString.class] || date.length < 10) return @"Unknown date";
    return [date substringToIndex:10];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && self.tabs.selectedSegmentIndex == 3 && indexPath.row < self.versions.count) {
        [self requestInstallVersion:self.versions[indexPath.row]];
    }
}

- (void)downloadTapped {
    if (self.versionsError) {
        [self showMessageWithTitle:@"Unable to load versions"
            message:self.versionsError.localizedDescription ?:
                @"Modrinth did not return this project's versions. Please try again."];
        return;
    }
    if (self.versions.count == 0) {
        [self showMessageWithTitle:@"No compatible version"
            message:@"This mod has no downloadable version for the selected Minecraft version and loader."];
        return;
    }
    [self requestInstallVersion:self.versions.firstObject];
}

- (void)versionButtonTapped:(UIButton *)sender {
    if (sender.tag < self.versions.count) [self requestInstallVersion:self.versions[sender.tag]];
}

- (void)requestInstallVersion:(NSDictionary *)version {
    if (self.installing) return;
    NSDictionary *project = self.item;
    if (self.project) {
        NSMutableDictionary *merged = self.item.mutableCopy;
        [merged addEntriesFromDictionary:self.project];
        merged[@"id"] = self.item[@"id"];
        project = merged;
    }
    [self.delegate modDetailViewController:self installVersion:version project:project
        includeDependencies:self.dependencySwitch ? self.dependencySwitch.isOn : YES];
}

- (void)setInstalling:(BOOL)installing {
    _installing = installing;
    self.downloadButton.enabled = !installing;
    self.dependencySwitch.enabled = !installing;
    self.downloadButton.imageView.hidden = installing;
    self.downloadButton.titleLabel.hidden = installing;
    if (installing) [self.downloadSpinner startAnimating];
    else {
        [self.downloadSpinner stopAnimating];
        self.downloadButton.imageView.hidden = NO;
        self.downloadButton.titleLabel.hidden = NO;
    }
}

- (void)installationDidFinishWithError:(NSError *)error {
    [self setInstalling:NO];
    if (error) {
        [self showMessageWithTitle:@"Installation failed" message:error.localizedDescription];
    } else {
        self.installed = YES;
        [self updateHero];
        [self showMessageWithTitle:@"Mod installed"
            message:@"The selected mod version was added to this profile."];
    }
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
