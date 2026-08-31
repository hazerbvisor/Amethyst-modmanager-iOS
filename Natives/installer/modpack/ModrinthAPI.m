#import "MinecraftResourceDownloadTask.h"
#import "ModrinthAPI.h"
#import "PLProfiles.h"

static NSString *AmethystModrinthString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : nil;
}

static NSArray *AmethystModrinthArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static BOOL AmethystModrinthArrayContainsString(NSArray *values, NSString *target) {
    if (target.length == 0) return YES;
    for (id value in values) {
        if ([value isKindOfClass:NSString.class] &&
            [value caseInsensitiveCompare:target] == NSOrderedSame) return YES;
    }
    return NO;
}

@implementation ModrinthAPI

- (instancetype)init {
    return [super initWithURL:@"https://api.modrinth.com/v2"];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)modrinthSearchResult {
    int limit = 50;
    NSString *projectType = AmethystModrinthString(searchFilters[@"projectType"]);
    if (!projectType) projectType = searchFilters[@"isModpack"].boolValue ? @"modpack" : @"mod";

    NSMutableString *facetString = [NSMutableString new];
    [facetString appendString:@"["];
    [facetString appendFormat:@"[\"project_type:%@\"]", projectType];
    if (searchFilters[@"mcVersion"].length > 0) {
        [facetString appendFormat:@",[\"versions:%@\"]", searchFilters[@"mcVersion"]];
    }
    if (searchFilters[@"loader"].length > 0) {
        [facetString appendFormat:@",[\"categories:%@\"]", searchFilters[@"loader"]];
    }
    if (searchFilters[@"category"].length > 0) {
        [facetString appendFormat:@",[\"categories:%@\"]", searchFilters[@"category"]];
    }
    if ([projectType isEqualToString:@"mod"]) {
        NSString *environment = searchFilters[@"environment"];
        if ([environment isEqualToString:@"client_only"]) {
            [facetString appendString:
                @",[\"environment:client_only\",\"environment:client_only_server_optional\",\"environment:singleplayer_only\"]"];
        } else if ([environment isEqualToString:@"client_and_server"]) {
            [facetString appendString:
                @",[\"environment:client_and_server\",\"environment:client_or_server\",\"environment:client_or_server_prefers_both\"]"];
        } else {
            [facetString appendString:
                @",[\"environment:client_and_server\",\"environment:client_only\",\"environment:client_only_server_optional\",\"environment:singleplayer_only\",\"environment:client_or_server\",\"environment:client_or_server_prefers_both\"]"];
        }
    }
    [facetString appendString:@"]"];

    NSDictionary *params = @{
        @"facets": facetString,
        @"query": searchFilters[@"name"] ?: @"",
        @"limit": @(limit),
        @"index": searchFilters[@"index"] ?: @"relevance",
        @"offset": @(modrinthSearchResult.count)
    };
    NSDictionary *response = [self getEndpoint:@"search" params:params];
    if (!response) {
        return nil;
    }

    NSMutableArray *result = modrinthSearchResult ?: [NSMutableArray new];
    for (NSDictionary *hit in response[@"hits"]) {
        NSString *resultProjectType = AmethystModrinthString(hit[@"project_type"]) ?: projectType;
        BOOL isModpack = [resultProjectType isEqualToString:@"modpack"];
        NSArray *gallery = AmethystModrinthArray(hit[@"gallery"]);
        NSString *galleryArtwork = AmethystModrinthString(hit[@"featured_gallery"]);
        if (!galleryArtwork) {
            for (id image in gallery) {
                galleryArtwork = AmethystModrinthString(image);
                if (galleryArtwork) break;
            }
        }
        NSString *iconArtwork = AmethystModrinthString(hit[@"icon_url"]);
        NSArray *categories = AmethystModrinthArray(hit[@"display_categories"]);
        if (categories.count == 0) categories = AmethystModrinthArray(hit[@"categories"]);
        [result addObject:@{
            @"apiSource": @(1), // Constant MODRINTH
            @"isModpack": @(isModpack),
            @"projectType": resultProjectType,
            @"id": AmethystModrinthString(hit[@"project_id"]) ?: @"",
            @"title": AmethystModrinthString(hit[@"title"]) ?: @"Untitled project",
            @"description": AmethystModrinthString(hit[@"description"]) ?: @"",
            @"imageUrl": iconArtwork ?: @"",
            @"fallbackImageUrl": galleryArtwork ?: @"",
            @"author": AmethystModrinthString(hit[@"author"]) ?: @"Modrinth creator",
            @"downloads": [hit[@"downloads"] isKindOfClass:NSNumber.class] ? hit[@"downloads"] : @0,
            @"dateModified": AmethystModrinthString(hit[@"date_modified"]) ?: @"",
            @"categories": categories
        }.mutableCopy];
    }
    self.reachedLastPage = result.count >= [response[@"total_hits"] unsignedLongValue];
    return result;
}

- (NSArray<NSDictionary *> *)compatibleVersionsForProject:(NSString *)projectId
    minecraftVersion:(NSString *)minecraftVersion
    loader:(NSString *)loader
    includeChangelog:(BOOL)includeChangelog {
    if (projectId.length == 0) return nil;

    NSString *endpoint = [NSString stringWithFormat:@"project/%@/version", projectId];
    NSMutableDictionary *params = [@{
        @"include_changelog": includeChangelog ? @"true" : @"false"
    } mutableCopy];
    if (minecraftVersion.length > 0) {
        params[@"game_versions"] = [NSString stringWithFormat:@"[\"%@\"]", minecraftVersion];
    }
    if (loader.length > 0) {
        params[@"loaders"] = [NSString stringWithFormat:@"[\"%@\"]", loader];
    }

    NSArray *filteredResponse = [self getEndpoint:endpoint params:params];
    if ([filteredResponse isKindOfClass:NSArray.class] && filteredResponse.count > 0) {
        return filteredResponse;
    }

    // A project returned by a filtered search should normally have a matching
    // version. Retry without server-side filters, then validate the response
    // locally so a rejected query is not mislabeled as "no compatible version".
    NSArray *allVersions = [self getEndpoint:endpoint params:@{
        @"include_changelog": includeChangelog ? @"true" : @"false"
    }];
    if (![allVersions isKindOfClass:NSArray.class]) {
        return [filteredResponse isKindOfClass:NSArray.class] ? filteredResponse : nil;
    }

    NSMutableArray<NSDictionary *> *compatible = [NSMutableArray new];
    for (id value in allVersions) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *version = value;
        if (!AmethystModrinthArrayContainsString(AmethystModrinthArray(version[@"game_versions"]), minecraftVersion)) continue;
        if (!AmethystModrinthArrayContainsString(AmethystModrinthArray(version[@"loaders"]), loader)) continue;
        [compatible addObject:version];
    }
    return compatible;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    NSArray *response = [self getEndpoint:[NSString stringWithFormat:@"project/%@/version", item[@"id"]] params:nil];
    if (!response) {
        return;
    }
    NSArray<NSString *> *names = [response valueForKey:@"name"];
    NSMutableArray<NSString *> *mcNames = [NSMutableArray new];
    NSMutableArray<NSString *> *urls = [NSMutableArray new];
    NSMutableArray<NSString *> *hashes = [NSMutableArray new];
    NSMutableArray<NSString *> *sizes = [NSMutableArray new];
    [response enumerateObjectsUsingBlock:
  ^(NSDictionary *version, NSUInteger i, BOOL *stop) {
        NSDictionary *file = [[version[@"files"] filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"primary == YES"]] firstObject] ?: [version[@"files"] firstObject];
        [mcNames addObject:[version[@"game_versions"] firstObject] ?: @"Unknown"];
        [sizes addObject:file[@"size"] ?: @0];
        [urls addObject:file[@"url"] ?: @""];
        NSDictionary *hashesMap = file[@"hashes"];
        [hashes addObject:hashesMap[@"sha1"] ?: (id)[NSNull null]];
    }];
    item[@"versionNames"] = names;
    item[@"mcVersionNames"] = mcNames;
    item[@"versionSizes"] = sizes;
    item[@"versionUrls"] = urls;
    item[@"versionHashes"] = hashes;
    item[@"versionDetailsLoaded"] = @(YES);
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath {
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:packagePath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to open modpack package: %@", error.localizedDescription]];
        return;
    }

    NSData *indexData = [archive extractDataFromFile:@"modrinth.index.json" error:&error];
    NSDictionary* indexDict = [NSJSONSerialization JSONObjectWithData:indexData options:kNilOptions error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to parse modrinth.index.json: %@", error.localizedDescription]];
        return;
    }

    downloader.progress.totalUnitCount = [indexDict[@"files"] count];
    for (NSDictionary *indexFile in indexDict[@"files"]) {
/*
        if ([indexFile[@"downloads"] count] > 1) {
            [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Unhandled multiple files download %@", indexFile[@"downloads"]]];
            return;
        }
*/
        NSString *url = [indexFile[@"downloads"] firstObject];
        NSString *sha = indexFile[@"hashes"][@"sha1"];
        NSString *path = [destPath stringByAppendingPathComponent:indexFile[@"path"]];
        NSUInteger size = [indexFile[@"fileSize"] unsignedLongLongValue];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url size:size sha:sha altName:nil toPath:path];
        if (task) {
            [downloader.fileList addObject:indexFile[@"path"]];
            [task resume];
        } else if (!downloader.progress.cancelled) {
            downloader.progress.completedUnitCount++;
        } else {
            return; // cancelled
        }
    }

    [ModpackUtils archive:archive extractDirectory:@"overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract overrides from modpack package: %@", error.localizedDescription]];
        return;
    }

    [ModpackUtils archive:archive extractDirectory:@"client-overrides" toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:@"Failed to extract client-overrides from modpack package: %@", error.localizedDescription]];
        return;
    }

    // Delete package cache
    [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];

    // Download dependency client json (if available)
    NSDictionary<NSString *, NSString *> *depInfo = [ModpackUtils infoForDependencies:indexDict[@"dependencies"]];
    if (depInfo[@"json"]) {
        NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), depInfo[@"id"]];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:depInfo[@"json"] size:0 sha:nil altName:nil toPath:jsonPath];
        [task resume];
    }
    // TODO: automation for Forge

    // Create profile
    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
    PLProfiles.current.profiles[indexDict[@"name"]] = @{
        @"gameDir": [NSString stringWithFormat:@"./custom_gamedir/%@", destPath.lastPathComponent],
        @"name": indexDict[@"name"],
        @"lastVersionId": depInfo[@"id"],
        @"icon": [NSString stringWithFormat:@"data:image/png;base64,%@",
            [[NSData dataWithContentsOfFile:tmpIconPath]
            base64EncodedStringWithOptions:0]]
    }.mutableCopy;
    PLProfiles.current.selectedProfileName = indexDict[@"name"];
}

@end
