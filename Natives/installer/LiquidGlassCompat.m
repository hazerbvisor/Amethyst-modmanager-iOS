#import "LiquidGlassCompat.h"

static NSInteger const AmethystGlassCellBackgroundTag = 0xA6A56;

@interface AmethystAmbientBackgroundView : UIView
@property(nonatomic) CAGradientLayer *gradientLayer;
@end

@implementation AmethystAmbientBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.startPoint = CGPointMake(0.05, 0.0);
    self.gradientLayer.endPoint = CGPointMake(0.95, 1.0);
    self.gradientLayer.locations = @[@0.0, @0.48, @1.0];
    [self.layer addSublayer:self.gradientLayer];
    [self updateColors];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.bounds;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self updateColors];
        }
    }
}

- (void)updateColors {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIColor *base = UIColor.systemGroupedBackgroundColor;
    UIColor *indigo = [UIColor.systemIndigoColor colorWithAlphaComponent:dark ? 0.20 : 0.11];
    UIColor *purple = [UIColor.systemPurpleColor colorWithAlphaComponent:dark ? 0.15 : 0.08];
    UIColor *clear = [base colorWithAlphaComponent:0.0];
    self.backgroundColor = base;
    self.gradientLayer.colors = @[
        (id)[indigo resolvedColorWithTraitCollection:self.traitCollection].CGColor,
        (id)[purple resolvedColorWithTraitCollection:self.traitCollection].CGColor,
        (id)[clear resolvedColorWithTraitCollection:self.traitCollection].CGColor
    ];
}

@end

static void AmethystApplyModernCornerConfiguration(UIView *view, CGFloat radius) {
    Class radiusClass = NSClassFromString(@"UICornerRadius");
    Class configurationClass = NSClassFromString(@"UICornerConfiguration");
    SEL fixedRadiusSelector = NSSelectorFromString(@"fixedRadius:");
    SEL configurationSelector = NSSelectorFromString(@"configurationWithRadius:");
    SEL setter = NSSelectorFromString(@"setCornerConfiguration:");
    if (!radiusClass || !configurationClass ||
        ![radiusClass respondsToSelector:fixedRadiusSelector] ||
        ![configurationClass respondsToSelector:configurationSelector] ||
        ![view respondsToSelector:setter]) return;

    typedef id (*RadiusFactory)(id, SEL, CGFloat);
    typedef id (*ConfigurationFactory)(id, SEL, id);
    typedef void (*ObjectSetter)(id, SEL, id);
    RadiusFactory makeRadius = (RadiusFactory)[radiusClass methodForSelector:fixedRadiusSelector];
    ConfigurationFactory makeConfiguration =
        (ConfigurationFactory)[configurationClass methodForSelector:configurationSelector];
    id cornerRadius = makeRadius(radiusClass, fixedRadiusSelector, radius);
    id configuration = makeConfiguration(configurationClass, configurationSelector, cornerRadius);
    ObjectSetter setConfiguration = (ObjectSetter)[view methodForSelector:setter];
    setConfiguration(view, setter, configuration);
}

UIVisualEffectView *AmethystCreateGlassView(CGFloat cornerRadius,
    BOOL interactive, UIColor *tintColor) {
    UIVisualEffect *effect;
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass) {
        effect = [[glassClass alloc] init];
        SEL interactiveSetter = NSSelectorFromString(@"setInteractive:");
        if (interactive && [effect respondsToSelector:interactiveSetter]) {
            typedef void (*BoolSetter)(id, SEL, BOOL);
            BoolSetter setInteractive = (BoolSetter)[effect methodForSelector:interactiveSetter];
            setInteractive(effect, interactiveSetter, YES);
        }
        SEL tintSetter = NSSelectorFromString(@"setTintColor:");
        if (tintColor && [effect respondsToSelector:tintSetter]) {
            typedef void (*ObjectSetter)(id, SEL, id);
            ObjectSetter setTint = (ObjectSetter)[effect methodForSelector:tintSetter];
            setTint(effect, tintSetter, tintColor);
        }
    } else {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    }

    UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:effect];
    effectView.clipsToBounds = YES;
    effectView.layer.cornerRadius = cornerRadius;
    effectView.layer.cornerCurve = kCACornerCurveContinuous;
    if (!glassClass && tintColor) {
        effectView.backgroundColor = [tintColor colorWithAlphaComponent:0.18];
    }
    AmethystApplyModernCornerConfiguration(effectView, cornerRadius);
    return effectView;
}

BOOL AmethystSupportsNativeLiquidGlass(void) {
    return NSClassFromString(@"UIGlassEffect") != nil;
}

void AmethystApplyGlobalAppearance(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UINavigationBarAppearance *navigationAppearance = [UINavigationBarAppearance new];
        [navigationAppearance configureWithTransparentBackground];
        navigationAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        navigationAppearance.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.16];
        navigationAppearance.shadowColor = UIColor.clearColor;
        navigationAppearance.titleTextAttributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]
        };
        navigationAppearance.largeTitleTextAttributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold]
        };

        UINavigationBar *navigationBar = UINavigationBar.appearance;
        navigationBar.standardAppearance = navigationAppearance;
        navigationBar.compactAppearance = navigationAppearance;
        navigationBar.scrollEdgeAppearance = navigationAppearance;
        navigationBar.tintColor = UIColor.systemIndigoColor;

        UIToolbarAppearance *toolbarAppearance = [UIToolbarAppearance new];
        [toolbarAppearance configureWithTransparentBackground];
        toolbarAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        toolbarAppearance.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.16];
        toolbarAppearance.shadowColor = UIColor.clearColor;
        UIToolbar *toolbar = UIToolbar.appearance;
        toolbar.standardAppearance = toolbarAppearance;
        if (@available(iOS 15.0, *)) toolbar.scrollEdgeAppearance = toolbarAppearance;
        toolbar.tintColor = UIColor.systemIndigoColor;

        UISwitch.appearance.onTintColor = UIColor.systemPurpleColor;
        UIProgressView.appearance.progressTintColor = UIColor.systemPurpleColor;
        UISegmentedControl.appearance.selectedSegmentTintColor =
            [UIColor.systemIndigoColor colorWithAlphaComponent:0.28];
    });
}

void AmethystStyleTableView(UITableView *tableView) {
    tableView.backgroundColor = UIColor.clearColor;
    tableView.backgroundView = [[AmethystAmbientBackgroundView alloc] initWithFrame:tableView.bounds];
    tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.24];
    tableView.separatorInset = UIEdgeInsetsMake(0.0, 60.0, 0.0, 18.0);
    tableView.estimatedRowHeight = 58.0;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 18.0, 0.0);
    tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(8.0, 0.0, 18.0, 0.0);
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 18.0;
}

void AmethystStyleCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.layoutMargins = UIEdgeInsetsMake(12.0, 18.0, 12.0, 18.0);

    if (cell.backgroundView.tag != AmethystGlassCellBackgroundTag) {
        UIVisualEffectView *background = AmethystCreateGlassView(16.0, NO, nil);
        background.tag = AmethystGlassCellBackgroundTag;
        background.userInteractionEnabled = NO;
        cell.backgroundView = background;
    }
    if (cell.selectedBackgroundView.tag != AmethystGlassCellBackgroundTag) {
        UIVisualEffectView *selected = AmethystCreateGlassView(16.0, NO, UIColor.systemIndigoColor);
        selected.tag = AmethystGlassCellBackgroundTag;
        selected.userInteractionEnabled = NO;
        cell.selectedBackgroundView = selected;
    }
    cell.layer.cornerRadius = 16.0;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.clipsToBounds = YES;
}

void AmethystAnimateCellEntrance(UITableViewCell *cell, NSIndexPath *indexPath) {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, 10.0),
        CGAffineTransformMakeScale(0.985, 0.985));
    NSTimeInterval delay = MIN(indexPath.row, 8) * 0.025;
    [UIView animateWithDuration:0.42 delay:delay usingSpringWithDamping:0.86
        initialSpringVelocity:0.25 options:UIViewAnimationOptionAllowUserInteraction |
            UIViewAnimationOptionBeginFromCurrentState animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

void AmethystAnimateSelection(UIView *view) {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.10 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction |
        UIViewAnimationOptionBeginFromCurrentState animations:^{
        view.transform = CGAffineTransformMakeScale(0.985, 0.985);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.32 delay:0.0 usingSpringWithDamping:0.72
            initialSpringVelocity:0.45 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

void AmethystInstallGlassBackground(UIButton *button, CGFloat cornerRadius,
    BOOL interactive, UIColor *tintColor) {
    UIView *oldBackground = [button viewWithTag:0xA6A55];
    [oldBackground removeFromSuperview];

    UIVisualEffectView *background = AmethystCreateGlassView(cornerRadius, interactive, tintColor);
    background.tag = 0xA6A55;
    background.translatesAutoresizingMaskIntoConstraints = NO;
    background.userInteractionEnabled = NO;
    [button insertSubview:background atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:button.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:button.bottomAnchor]
    ]];
    button.backgroundColor = UIColor.clearColor;
    button.clipsToBounds = YES;
    button.layer.cornerRadius = cornerRadius;
    button.layer.cornerCurve = kCACornerCurveContinuous;
}
