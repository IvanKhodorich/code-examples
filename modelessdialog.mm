//
// LModelessDialog
// (c) NCH Software. All rights reserved.
//
#include <llib/ios/app.h>
#include <llib/ios/modelessdialog.h>

@implementation LTopOverlayView
- (id) initWithView:(UIView*) view delegate:(id<LIOSTouchOutsideViewDelegate>) _delegate
{
   // Place over parent window.
   self = [super initWithFrame:view.superview.window.frame];
   if (self != nil) {
      self.opaque = NO;
      self.backgroundColor = [UIColor clearColor];
      underneathView = view;
      delegate = _delegate;
   }
   return self;
}

- (nullable UIView*) hitTest:(CGPoint) ptLocal withEvent:(nullable UIEvent*) event
{
   // Don't handle events, only let know underneath view that touch is outside of its bounds.
   CGPoint ptUnderneathView = LView2View(ptLocal, self, underneathView);
   if (!CGRectContainsPoint(underneathView.bounds, ptUnderneathView)) {
      [delegate touchOutside];
   }
   return nil;
}
@end

@implementation LIOSDragTitleView
- (id) initWithTitle:(NSAttributedString*)nszTitle delegate:(id<LIOSDragViewDelegate>) _delegate;
{
   self = [super init];
   if (self != nil) {
      dragImage = [[UIImageView alloc] initWithImage:LUIImage(cICON_STD_MOVE_DRAG_DIALOG).get()];
      dragImage.userInteractionEnabled = YES;
      [self addSubview:dragImage];
      titleText = [[UITextField alloc] init];
      titleText.attributedText = nszTitle;
      titleText.userInteractionEnabled = NO;
      [self addSubview:titleText];
      delegate = _delegate;
      self.userInteractionEnabled = YES;
   }
   return self;
}

- (void) touchesMoved:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event
{
   UITouch* touch = [touches anyObject];
   [delegate viewDraggedFrom:[touch previousLocationInView:self] to:[touch locationInView:self]];
}

- (void) layoutSubviews
{
   CGSize sizeText = [titleText.attributedText size];
   const CGFloat dGapPt = 3.0;
   const CGFloat dDragImageSizePt = 24.0;
   // Text placed in the center of titlebar area. Icon placed at the left of text.
   const CGFloat dTitleXPt = (self.frame.size.width - sizeText.width) / 2.0;
   const CGFloat dTitleYPt = (self.frame.size.height - sizeText.height) / 2.0;
   const CGFloat dDragImageXPt = dTitleXPt - dDragImageSizePt - dGapPt;
   const CGFloat dDragImageYPt = (self.frame.size.height - dDragImageSizePt) / 2.0;
   
   dragImage.frame = CGRectMake(dDragImageXPt, dDragImageYPt, dDragImageSizePt, dDragImageSizePt);
   titleText.frame = CGRectMake(dTitleXPt, dTitleYPt, sizeText.width, sizeText.height);
}

- (void) dealloc
{
   [dragImage release];
   [titleText release];
   [super dealloc];
}
@end

@implementation LIOSShadowViewController
- (id) init
{
   self = [super init];
   if (self != nil) {
      [self.view setAutoresizingMask:UIViewAutoresizingNone];
   }
   return self;
}

- (void) moveTo:(CGPoint) ptScreen
{
   // Update the whole frame
   CGRect frame = self.view.frame;
   frame.origin = LScreen2View(ptScreen, self.parentViewController.view);
   self.view.frame = frame;
}

- (void) moveOn:(CGSize) size
{
   // Update the whole frame
   CGRect frame = self.view.frame;
   frame.origin.x += size.width;
   frame.origin.y += size.height;
   self.view.frame = frame;
}

- (void) resize:(CGSize) size
{
   // Update the whole frame
   CGRect frame = self.view.frame;
   frame.size = size;
   self.view.frame = frame;
   
   // Update shape layer that makes a shadow.
   if (shapeLayer != nil) [shapeLayer removeFromSuperlayer];
   shapeLayer = [CAShapeLayer layer];
   shapeLayer.path = [UIBezierPath bezierPathWithRoundedRect:self.view.bounds cornerRadius:13.0].CGPath;
   shapeLayer.shadowOpacity = 0.5;
   shapeLayer.shadowOffset = CGSizeMake(10.0, 10.0);
   shapeLayer.shadowRadius = 10.0;
   #ifdef BUILD_GUI_DARKTHEME
   const CGColorRef cgShadow = [LCOLOR_DARKTHEME_DKGRAY_SHADOW.GetNativeColor().GetUIColor() CGColor];
   #else
   const CGColorRef cgShadow = [LCOLORDKGRAY.GetNativeColor().GetUIColor() CGColor];
   #endif
   shapeLayer.shadowColor = cgShadow;
   shapeLayer.shadowPath = shapeLayer.path;
   shapeLayer.masksToBounds = NO;
   shapeLayer.backgroundColor = cgShadow;
   [self.view.layer insertSublayer:shapeLayer atIndex:0];
}

- (void) viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
   [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
   // The most easy case to be sure that modeless window is not outside of
   // screen bounds after rotation to place it in the center of screen
   // (modeless windows embedded to only full screen parent windows.).
   [self moveTo:CGPointMake((size.width - self.view.frame.size.width) / 2.0, (size.height - self.view.frame.size.height) / 2.0)];
}

@end

@implementation UIView(LIOSRoundedBorder)
- (void) addRoundedBorder
{
   self.layer.masksToBounds = YES;
   self.layer.cornerRadius = 13.0;
   self.layer.borderWidth = 0.5;
   #ifdef BUILD_GUI_DARKTHEME
   self.layer.borderColor = [LCOLOR_DARKTHEME_DKGRAY_SHADOW.GetNativeColor().GetUIColor() CGColor];
   #else
   self.layer.borderColor = [LCOLORDKGRAY.GetNativeColor().GetUIColor() CGColor];
   #endif
}

- (void) removeRoundedBorder
{
   self.layer.masksToBounds = NO; // Default value.
   self.layer.cornerRadius = 0.0;
   self.layer.borderWidth = 0.0;
}
@end

@implementation LIOSModelessDialogImpl
- (id) initWithDialog:(LDialog*) _pDialog
{
   self = [super init];
   if ((self != nil) && (_pDialog != nullptr)) {
      pDialog = _pDialog;
      contentView = pDialog->GetNavigationController().GetView();
      // Add a rounded border around view to looks similar to form sheet presentation.
      [contentView addRoundedBorder];
   
      // Add a shadow underneath of pDialog.
      shadowVievController = [[LIOSShadowViewController alloc] init];
      [shadowVievController.view addSubview:contentView];
      
      // Add pDialog to rootViewController (or another fullscreen viewcontroller)
      // as childViewController.
      LUIApplication* app = (LUIApplication*)[UIApplication sharedApplication];
      parentViewController = app.rootViewController; // Default value.
      UIViewController* visibleViewController = LGetVisibleViewController();
      if (visibleViewController != gpMainDialog->GetViewController().get()) {
         parentViewController = visibleViewController;
      }
      [parentViewController addChildViewController:shadowVievController];
      int iDialogWidthPixels = 0;
      int iDialogHeightPixels = 0;
      pDialog->GetDialogSize(iDialogWidthPixels, iDialogHeightPixels);
      if (pDialog->IsTitleBarVisible()) {
         // Add Navigation bar height if titlebar is visible.
         iDialogHeightPixels += pDialog->GetNavigationBarHeight();
      }
      [self resize:CGSizeMake(pDialog->GetLogicalPointsFromPixels(iDialogWidthPixels), pDialog->GetLogicalPointsFromPixels(iDialogHeightPixels))];
      [parentViewController.view addSubview:shadowVievController.view];
      [shadowVievController didMoveToParentViewController:parentViewController];
      
      shadowVievController.view.hidden = YES;

      // Create draggable title in childViewController which is on the top of stack.
      if (pDialog->IsTitleBarVisible()) {
         // Get title text with attrubutes
         NSString* nszTitle = LMacNSStringFromString(pDialog->GetCaption());
         LUINavigationBarRef NavigationBar = pDialog->GetNavigationController().GetNavigationBar();
         NSDictionary<NSAttributedStringKey, id>* titleTextAttributes = nil;
         if (LOSIsIOS13OrLater()) {
            // Silence compiler warning that titleTextAttributes is only available on 13.0 and higher (tested by LOSIsIOS13OrLater())
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wunguarded-availability-new"
            titleTextAttributes = NavigationBar.get().standardAppearance.titleTextAttributes;
            #pragma clang diagnostic pop
         } else {
            UIFont* font = [UIFont systemFontOfSize:MAC_DEFAULT_FONT_SIZE];
            #ifdef BUILD_GUI_DARKTHEME
            UIColor* crText = (pDialog->IsDarkThemeEnabled()) ? LCOLOR_DARKTHEME_TEXT_PRIMARY.GetNativeColor() : LCOLOR_LIGHTTHEME_TEXT_PRIMARY.GetNativeColor();
            #else
            UIColor* crText = LCOLOR_LIGHTTHEME_TEXT_PRIMARY.GetNativeColor();
            #endif
            titleTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys: font, NSFontAttributeName, crText, NSForegroundColorAttributeName, nil];
         }

         NSAttributedString* nszAttrTitle = [[[NSAttributedString alloc] initWithString:nszTitle attributes:titleTextAttributes] autorelease];
         dragView = [[[LIOSDragTitleView alloc] initWithTitle:nszAttrTitle delegate:self] autorelease];
         pDialog->SetCustomCaption(dragView);
      }
   }
   return self;
}

- (void) setAutoCloseOnFocusLost:(bool) autoCloseOnFocusLost
{
   if (autoCloseOnFocusLost == _autoCloseOnFocusLost) return;
   _autoCloseOnFocusLost = autoCloseOnFocusLost;
   if (_autoCloseOnFocusLost) {
      // Add auxiliary view for helping to intercepts touches.
      topOverlayView = [[[LTopOverlayView alloc] initWithView:shadowVievController.view delegate:self] autorelease];
      [parentViewController.view addSubview:topOverlayView];
   } else {
      if (topOverlayView != nil) {
         [topOverlayView removeFromSuperview];
         topOverlayView = nil;
      }
   }
}

- (void) show:(bool)bShow
{
   shadowVievController.view.hidden = !bShow;
}

- (void) close
{
   if (shadowVievController != nil) {
      // Remove border added on initialization and
      // return view back to original hierarchy.
      [contentView removeRoundedBorder];
      [contentView removeFromSuperview]; // Remove it from shadowVievController.
      pDialog->GetNavigationController().get().view = contentView; // Return it back to pDialog.
      
      [shadowVievController willMoveToParentViewController:nil];
      [shadowVievController.view removeFromSuperview];
      [parentViewController removeChildViewController:shadowVievController];
      [shadowVievController release];
      shadowVievController = nil;
      
      if (topOverlayView != nil) {
         [topOverlayView removeFromSuperview];
         topOverlayView = nil;
      }
      if (dragView != nil) {
         [dragView removeFromSuperview];
         dragView = nil;
      }
   }
}

- (void) move:(CGPoint) ptScreen
{
   [shadowVievController moveTo:ptScreen];
}

- (void) resize:(CGSize) size
{
   [shadowVievController resize:size];
   if (pDialog == nullptr) { // Just in case. Should not happen.
      LFDEBUG("pDialog is nullptr");
      return;
   }
   dragView.frame = CGRectMake(0.0, 0.0, size.width, pDialog->GetNavigationBarHeight());
}

- (void) dealloc
{
   if (shadowVievController != nil) [self close];
   [super dealloc];
}

// @protocol LIOSTouchOutsideViewDelegate
- (void) touchOutside
{
   if (pDialog != nullptr) pDialog->CloseCancel();
}

// @protocol LIOSDragViewDelegate
- (void) viewDraggedFrom:(CGPoint) ptPrev to:(CGPoint) ptNew
{
   LFTRACE();
   [shadowVievController moveOn:CGSizeMake(ptNew.x - ptPrev.x, ptNew.y - ptPrev.y)];
}

@end
