#import "LiquidGlassCompat.h"

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
