#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns native UIGlassEffect on iOS 26+, while remaining buildable with
/// older SDKs and falling back to UIKit material on earlier systems.
UIVisualEffectView *AmethystCreateGlassView(CGFloat cornerRadius,
    BOOL interactive, UIColor * _Nullable tintColor);

/// Places a non-intercepting glass layer behind a standard UIButton's content.
void AmethystInstallGlassBackground(UIButton *button, CGFloat cornerRadius,
    BOOL interactive, UIColor * _Nullable tintColor);

NS_ASSUME_NONNULL_END
