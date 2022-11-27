// LIOSModelessDialogImpl helps to simulate modeless dialog behaviour on iOS.
// Any UIViewController presented as form sheet (not a full screen or it doesn't have sense)
// can be made modeless.
// Modeless in current implementation means:
//  - UIViewController becomes draggable over the parent window (parent view controller) area
//  - UIViewController can be autoclosed if touch outside of its area
//  - UIViewController pass all touch events to below placed parent view controller.
//

#pragma once

#include <llib/gui/dialog.h>

// Delegate that responds when touch outside view bounds happens.
@protocol LIOSTouchOutsideViewDelegate
- (void) touchOutside;
@end

// LTopOverlayView placed over parent window (current key window)
// and helps to intercepts touch events for autoclosing modeless dialog.
@interface LTopOverlayView : UIView {
   UIView* underneathView;
   id<LIOSTouchOutsideViewDelegate> delegate;
}
- (id) initWithView:(UIView*) view delegate:(id<LIOSTouchOutsideViewDelegate>)delegate;
@end

// Wrapper around UIViewController that should be presented as modeless window.
// It adds shadow underneath of modeless UIViewController.
@interface LIOSShadowViewController : UIViewController {
   CAShapeLayer* shapeLayer; // Updated every time view size changed.
}
@end

// Delegate that responds when LUIDragTitleView dragged.
@protocol LIOSDragViewDelegate
- (void) viewDraggedFrom:(CGPoint) prevPt to:(CGPoint) newPt;
@end

// Wrapper around drag icon and title. The whole view is draggable.
@interface LIOSDragTitleView : UIView {
   id<LIOSDragViewDelegate> delegate;
   UITextField* titleText;
   UIImageView* dragImage;
}
- (id) initWithTitle:(NSAttributedString*)nszTitle delegate:(id<LIOSDragViewDelegate>) delegate;
@end
   
// Helper class for presenting UIViewController as modeless window.
@interface LIOSModelessDialogImpl : NSObject<LIOSTouchOutsideViewDelegate, LIOSDragViewDelegate> {
   UIViewController* parentViewController;
   UIView* contentView;
   LDialog* pDialog;
   LIOSShadowViewController* shadowVievController;
   LTopOverlayView* topOverlayView;
   LIOSDragTitleView* dragView;
}
@property (nonatomic, assign) bool autoCloseOnFocusLost;

- (id) initWithDialog:(LDialog*) _pDialog;
- (void) show:(bool)bShow;
- (void) close;
- (void) move:(CGPoint) pt;
- (void) resize:(CGSize) size;
@end
