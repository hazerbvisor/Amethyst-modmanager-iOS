#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns native UIGlassEffect on iOS 26+, while remaining buildable with
/// older SDKs and falling back to UIKit material on earlier systems.
UIVisualEffectView *AmethystCreateGlassView(CGFloat cornerRadius,
    BOOL interactive, UIColor * _Nullable tintColor);

/// Places a non-intercepting glass layer behind a standard UIButton's content.
void AmethystInstallGlassBackground(UIButton *button, CGFloat cornerRadius,
    BOOL interactive, UIColor * _Nullable tintColor);

/// True when the running OS exposes Apple's native Liquid Glass effect.
BOOL AmethystSupportsNativeLiquidGlass(void);

/// Installs the shared Apple-inspired navigation, toolbar, and control appearance.
void AmethystApplyGlobalAppearance(void);

/// Applies the ambient glass canvas used by launcher list screens.
void AmethystStyleTableView(UITableView *tableView);

/// Gives standard UIKit cells a material card and a tinted selected state.
void AmethystStyleCell(UITableViewCell *cell);

/// Lightweight spring motion for rows entering the viewport and being selected.
void AmethystAnimateCellEntrance(UITableViewCell *cell, NSIndexPath *indexPath);
void AmethystAnimateSelection(UIView *view);

NS_ASSUME_NONNULL_END
