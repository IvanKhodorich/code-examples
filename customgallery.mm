#include <llib/mobile/mediapicker.h>
#include <llib/ios/asset.h>
#include <llib/ios/alert.h>
#include <llib/ios/dynamicisl.h>
#include <llib/ios/interwinmsg.h>
#include <llib/ios/uibarbuttonitem.h>
#include <llib/ios/uicollectionview.h>
#include <llib/ios/customgallery.h>
#include <llib/gen/thread.h>
#include <llib/gui/dialog.h>
#include <lxa/lxa.h>

#ifndef cICON_GALLERY_SELECTION
#error "Please add this to your lxa file: <include file="../llib/include/llib/resources/ios/gallery.lxi"/>"
#endif

#define ISL_CUSTOM_GALLERY_CELL_ID @"cgCell"
#define ISL_CUSTOM_GALLERY_CELL_VIDEO_TAG        3
#define ISL_CUSTOM_GALLERY_CELL_SELECTION_TAG    4
#define ISL_CUSTOM_GALLERY_CELL_LABEL_HEIGHT     20 // Default height of label
#define ISL_CUSTOM_GALLERY_CELL_GAP_MIN          2  // Min and max space between cells in a row.
#define ISL_CUSTOM_GALLERY_CELL_GAP_MAX          10

#define NAVIGATION_BAR_ID 1000
#define ALBUM_GALLERY_CONTROL_ID 1001
#define PHOTO_GALLERY_CONTROL_ID 1002

#define ALBUM_SELECTED_MESSAGE_ID 100
#define PHOTO_SELECTED_MESSAGE_ID 101
#define BACK_BUTTON_PRESSED_ID    102

// ** LGalleryViewImpl

@interface LGalleryViewImpl : LUICollectionViewImpl {
   LGalleryThumbnailCallback* pBase;
}
@end

@implementation LGalleryViewImpl

- (id)initWithDataSource:(LUICollectionViewDataSource*)_pDataSource baseClass:(LGalleryThumbnailCallback*)_pBase andScrollDirection:(UICollectionViewScrollDirection)scrollDirection
{
   if (_pDataSource == nullptr) return nil;

   if ((self = [super initWithDataSource:_pDataSource andScrollDirection:scrollDirection]) != nil) {
      pBase = _pBase;
      UICollectionViewFlowLayout* flowLayout = (UICollectionViewFlowLayout*)self.collectionViewLayout;
      if (flowLayout == nil) {
         // Just in case. It should be created in parent class.
         flowLayout = [[[UICollectionViewFlowLayout alloc] init] autorelease];
         self.collectionViewLayout = flowLayout;
         [flowLayout setScrollDirection:scrollDirection];
      }
      [flowLayout setItemSize:CGSizeMake(ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT, ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT)];
      flowLayout.minimumLineSpacing = ISL_CUSTOM_GALLERY_CELL_GAP_MIN;
      flowLayout.minimumInteritemSpacing = ISL_CUSTOM_GALLERY_CELL_GAP_MIN;
   }
   [self registerClass:[LUICollectionViewCellImpl class] forCellWithReuseIdentifier:ISL_CUSTOM_GALLERY_CELL_ID];
   return self;
}

// UICollectionViewDataSource override

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
   int iSection = int(indexPath.section);
   if (iSection != 0) return nil;
   
   LUICollectionViewCellImpl* cell = [collectionView dequeueReusableCellWithReuseIdentifier:ISL_CUSTOM_GALLERY_CELL_ID forIndexPath:indexPath];
   if (cell == nil) return nil;

   LISLItemListable* islItem = pDataSource->GetItem(indexPath.row);
   if (islItem == nullptr) {
      LFDEBUG("Invalid indexPath");
      return nil;
   }
   // Get text
   NSString* text = LC2NSString(islItem->szName);
   cell.labelView.text = text;
   const CGFloat dCellSize = cell.frame.size.width; // Current cell size. Image and text take this space. Image above text.
   // Calculate size of imageView based on size of textView.
   const CGFloat dImageViewSize = (text.length == 0) ? dCellSize : dCellSize - ISL_CUSTOM_GALLERY_CELL_LABEL_HEIGHT;
   const CGFloat dImageViewOffset = (text.length == 0) ? 0.0 : (dCellSize - dImageViewSize) / 2.0;

   // Get image
   UIImage* image = islItem->Image.get();
   if (image != nil) cell.imageView.image = image;
   // Load image on demand
   #ifdef BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE
   else pBase->SetThumbnail(int(indexPath.row), cell, CGSizeMake(dImageViewSize, dImageViewSize)); // Load image of cell size.
   #else
   else pBase->SetThumbnail(int(indexPath.row), cell); // Load image of default size. Imageview resize image itself.
   #endif

   // Set size of image and text fields.
   cell.imageView.frame = CGRectMake(dImageViewOffset, 0.0, dImageViewSize, dImageViewSize);
   if (text.length == 0) cell.labelView.frame = CGRectZero;
   else cell.labelView.frame = CGRectMake(0, dImageViewSize, dCellSize, ISL_CUSTOM_GALLERY_CELL_LABEL_HEIGHT);
   
   // call base class to add other views if required (e.g. video overlay image)
   pBase->AddSubviews(cell.contentView, int(indexPath.row), int(islItem->uData));

   // create selection overlay image
   bool bIsSelected = false;
   for (LListConstIterator<LISLIndexListable> li(lSelected); li.IsValid(); li.Next()) {
      if (indexPath.row == li->iIndexInSection) {
         bIsSelected = true;
         break;
      }
   }
   
   UIImageView* selectionView = (UIImageView*)[cell viewWithTag:ISL_CUSTOM_GALLERY_CELL_SELECTION_TAG];
   if (selectionView == nil) {
      LUIImage image(cICON_GALLERY_SELECTION);
      selectionView = [[[UIImageView alloc] initWithImage:image.get()] autorelease];
      selectionView.tag = ISL_CUSTOM_GALLERY_CELL_SELECTION_TAG;
      [cell.contentView addSubview:selectionView];
   }
   selectionView.frame = cell.imageView.frame; // Frame size can be changed on relayout.
   selectionView.hidden = !bIsSelected;
   
   return cell;
}

@end // @implementation LGalleryViewImpl

LIOSCollectionGalleryControl::LIOSCollectionGalleryControl()
: arrCollections(nil)
, hwndParent(NULL)
, idControl(-1)
, phMediaType(PHAssetMediaTypeUnknown)
{
   arrCollections = [[NSMutableArray alloc] init];
   
   fetchCollectionOptions = [[PHFetchOptions alloc] init];
   fetchCollectionOptions.includeAssetSourceTypes = PHAssetSourceTypeUserLibrary | PHAssetSourceTypeCloudShared | PHAssetSourceTypeiTunesSynced;
   
   fetchAssetOptions = [[PHFetchOptions alloc] init];
   fetchAssetOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
   fetchAssetOptions.includeAssetSourceTypes = PHAssetSourceTypeUserLibrary | PHAssetSourceTypeCloudShared | PHAssetSourceTypeiTunesSynced;
   
   imageRequestOptions = [[PHImageRequestOptions alloc] init];
   imageRequestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
   imageRequestOptions.resizeMode = PHImageRequestOptionsResizeModeNone;
   imageRequestOptions.networkAccessAllowed = YES; // Allow to download files stored on iCloud.
}

LIOSCollectionGalleryControl::~LIOSCollectionGalleryControl()
{
   [arrCollections release];
   [fetchCollectionOptions release];
   [fetchAssetOptions release];
   [imageRequestOptions release];
}

void LIOSCollectionGalleryControl::Init(LWindow& Parent, LWindow::cid _idControl)
{
   hwndParent = Parent.GetWindowHandle();
   idControl = _idControl;

   LUICollectionView CollectionView(idControl, [[LGalleryViewImpl alloc] initWithDataSource:(new LUICollectionViewDataSource()) baseClass:this andScrollDirection:UICollectionViewScrollDirectionVertical]);
   Parent.AddControl(CollectionView);
   
   // All media in one place
   {
      // Just add stub PHAssetCollection
      [arrCollections addObject:[[[PHAssetCollection alloc] init] autorelease]];
      // Image will be loaded in collectionView:cellForItemAtIndexPath:
      if (phMediaType == PHAssetMediaTypeImage) CollectionView.AddItem(TEXT(L_CUSTOMGALLERY_AllPhotos), nil, 0);
      else if (phMediaType == PHAssetMediaTypeVideo) CollectionView.AddItem(TEXT(L_CUSTOMGALLERY_AllVideos), nil, 0);
      else CollectionView.AddItem(TEXT(L_CUSTOMGALLERY_AllMedia), nil, 0);
   }
   
   // Get smart albums
   {
      PHFetchResult* allCollections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:fetchCollectionOptions];
      for (PHAssetCollection* collection in allCollections) {
         PHFetchResult* assets = [PHAsset fetchAssetsInAssetCollection:collection options:fetchAssetOptions];
         if (assets.count > 0) {   // Don't add empty collections
            [arrCollections addObject:collection];
            // Image will be loaded in collectionView:cellForItemAtIndexPath:
            CollectionView.AddItem(LNS2CString(collection.localizedTitle), nil, 0);
         }
      }
   }

   // Get user albums
   {
      PHFetchResult* allCollections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:fetchCollectionOptions];
      for (PHAssetCollection* collection in allCollections) {
         PHFetchResult* assets = [PHAsset fetchAssetsInAssetCollection:collection options:fetchAssetOptions];
         if (assets.count > 0) {   // Don't add empty collections
            [arrCollections addObject:collection];
            // Image will be loaded in collectionView:cellForItemAtIndexPath:
            CollectionView.AddItem(LNS2CString(collection.localizedTitle), nil, 0);
         }
      }
   }
   CollectionView.ReloadData();
}

PHAssetCollection* LIOSCollectionGalleryControl::GetCollectionAtIndex(uint32_t nIndex)
{
   return [arrCollections objectAtIndex:nIndex];
}

bool LIOSCollectionGalleryControl::IsEmpty()
{
   return (arrCollections.count == 0);
}

void LIOSCollectionGalleryControl::SetThumbnail(int iItemIndex, LUICollectionViewCellImpl* cell, CGSize sizeImage)
{
   PHAssetCollection* collection = GetCollectionAtIndex(iItemIndex);
   
   PHFetchResult* assets = nil;
   if (iItemIndex == 0) {
      assets = [PHAsset fetchAssetsWithOptions:fetchAssetOptions];
   } else {
      assets = [PHAsset fetchAssetsInAssetCollection:collection options:fetchAssetOptions];
   }

   void (^resHandler) (UIImage*, NSDictionary*) = ^(UIImage* image, NSDictionary* info) {
      NSError* error = [info objectForKey:PHImageErrorKey];
      if (error != nil) {
         LFDEBUGF("Error loading file: %s", error.localizedDescription.UTF8String);
      } else {
         cell.imageView.image = image;
      }
   };

   [[PHImageManager defaultManager] requestImageForAsset:(PHAsset*)[assets objectAtIndex:0]
                                              targetSize:sizeImage
                                             contentMode:PHImageContentModeDefault
                                                 options:imageRequestOptions
                                           resultHandler:resHandler];
}

void LIOSCollectionGalleryControl::SetMediaType(int iMediaType)
{
   LFTRACE("iMediaType: ", iMediaType);
   switch (iMediaType) {
      case MEDIA_TYPE_PHOTO: phMediaType = PHAssetMediaTypeImage; break;
      case MEDIA_TYPE_VIDEO: phMediaType = PHAssetMediaTypeVideo; break;
      case MEDIA_TYPE_PHOTO_AND_VIDEO: phMediaType = PHAssetMediaTypeUnknown; break;
      default: LFDEBUG("Unsupported media type"); break;
   };

   // If phMediaType is PHAssetMediaTypeUnknown, then try to show all media.
   if ((fetchAssetOptions != nil) && (phMediaType != PHAssetMediaTypeUnknown)) {
      fetchAssetOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType = %d", phMediaType];
   }
}

bool LIOSCollectionGalleryControl::DoesMediaFilesExists() const
{
   ASSERT(fetchAssetOptions != nil);
   return ([PHAsset fetchAssetsWithOptions:fetchAssetOptions].count > 0);
}

void LIOSCollectionGalleryControl::SetCellSize(int iCellSize)
{
   LControlHandle hGalleryControl = LWindow::FindControlHandle(hwndParent, idControl);
   LUICollectionView(hGalleryControl).SetItemSize(iCellSize, iCellSize);
   LUICollectionView(hGalleryControl).ReloadData();
}

// ** LIOSPhotoGalleryControl
LIOSPhotoGalleryControl::LIOSPhotoGalleryControl()
: fetchedAssets(nil)
, hwndParent(NULL)
, idControl(-1)
, phMediaType(PHAssetMediaTypeUnknown)
#ifdef BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE
, iCellSize(ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT)
#endif
{
   cacheImageManager = [[PHCachingImageManager alloc] init];
   cacheImageManager.allowsCachingHighQualityImages = NO; // Don't need high quality for thumbnails.
   
   arAssets = [[NSMutableArray alloc] init];
   
   imageRequestOptions = [[PHImageRequestOptions alloc] init];
   imageRequestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
   #ifdef BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE
   imageRequestOptions.resizeMode = PHImageRequestOptionsResizeModeExact;
   #else
   imageRequestOptions.resizeMode = PHImageRequestOptionsResizeModeNone;
   #endif
   imageRequestOptions.networkAccessAllowed = YES; // Allow to download files stored on iCloud.
}

LIOSPhotoGalleryControl::~LIOSPhotoGalleryControl()
{
   if (fetchedAssets != nil) {
      [fetchedAssets release];
      fetchedAssets = nil;
   }
   [cacheImageManager release];
   [arAssets release];
   [imageRequestOptions release];
}

void LIOSPhotoGalleryControl::Init(LWindow& Parent, LWindow::cid _idControl)
{
   hwndParent = Parent.GetWindowHandle();
   idControl = _idControl;
   
   LUICollectionView CollectionView(idControl, [[LGalleryViewImpl alloc] initWithDataSource:(new LUICollectionViewDataSource()) baseClass:this andScrollDirection:UICollectionViewScrollDirectionVertical]);
   Parent.AddControl(CollectionView);
}

void LIOSPhotoGalleryControl::SetAssetsCollection(PHAssetCollection* collection)
{
   LFTRACE();
   __block LUICollectionView CollectionView(LWindow::GetControlHandle(hwndParent, idControl));
   if (CollectionView.get() == nil) return;
   // Clear collection view.
   CollectionView.Clear();

   // Get non-empty collections
   if (fetchedAssets != nil) [fetchedAssets release];
   // Fetch items with media type
   PHFetchOptions* fetchOptions = [[[PHFetchOptions alloc] init] autorelease];
   fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
   // If phMediaType is PHAssetMediaTypeUnknown, then try to show all media.
   if (phMediaType != PHAssetMediaTypeUnknown) {
      fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType = %d", phMediaType];
   }
   fetchOptions.includeAssetSourceTypes = PHAssetSourceTypeUserLibrary | PHAssetSourceTypeCloudShared | PHAssetSourceTypeiTunesSynced;
   
   if ((collection.assetCollectionType == 0) && (collection.assetCollectionSubtype == 0)) {
      fetchedAssets = [PHAsset fetchAssetsWithOptions:fetchOptions];
   } else {
      fetchedAssets = [PHAsset fetchAssetsInAssetCollection:collection options:fetchOptions];
   }
   [fetchedAssets retain];
   
   [fetchedAssets enumerateObjectsUsingBlock:^(PHAsset* phAsset, NSUInteger idx, BOOL* pbStop) {
      // Image will be loaded in collectionView:cellForItemAtIndexPath:
      CollectionView.AddItem(TEXT(""), nil, 0);
      [arAssets addObject:phAsset];
   }];

   // Start caching of assets.
   #ifdef BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE
   CGSize imageSize = CGSizeMake(iCellSize, iCellSize);
   #else
   CGSize imageSize = CGSizeMake(ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT, ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT);
   #endif
   [cacheImageManager stopCachingImagesForAllAssets];
   [cacheImageManager startCachingImagesForAssets:arAssets targetSize:imageSize contentMode:PHImageContentModeDefault options:imageRequestOptions];
   
   CollectionView.ReloadData();
}

void LIOSPhotoGalleryControl::SetThumbnail(int iItemIndex, LUICollectionViewCellImpl* cell, CGSize sizeImage)
{
   void (^resHandler) (UIImage*, NSDictionary*) = ^(UIImage* image, NSDictionary* info) {
      NSError* error = [info objectForKey:PHImageErrorKey];
      if (error != nil) {
         LFDEBUGF("Error loading file: %s", error.localizedDescription.UTF8String);
      } else {
         cell.imageView.image = image;
      }
   };
   [cacheImageManager requestImageForAsset:(PHAsset*)[fetchedAssets objectAtIndex:iItemIndex]
                                targetSize:sizeImage
                               contentMode:PHImageContentModeDefault
                                   options:imageRequestOptions
                             resultHandler:resHandler];
}

void LIOSPhotoGalleryControl::AddSubviews(UIView* viewCell, int iItemIndex, int iItemData)
{
   PHAsset* phAsset = [fetchedAssets objectAtIndex:iItemIndex];
   const bool bIsVideo = (phAsset.mediaType == PHAssetMediaTypeVideo);
   UIImageView* imageView = (UIImageView*)[viewCell viewWithTag:ISL_CELL_IMAGE_TAG];
   UIImageView* videoIcon = (UIImageView*)[viewCell viewWithTag:ISL_CUSTOM_GALLERY_CELL_VIDEO_TAG];

   if (videoIcon == nil) {
      LUIImage image(cICON_GALLERY_VIDEO);
      videoIcon = [[[UIImageView alloc] initWithImage:image.get()] autorelease];
      videoIcon.tag = ISL_CUSTOM_GALLERY_CELL_VIDEO_TAG;
      [viewCell insertSubview:videoIcon aboveSubview:imageView];
   }
   videoIcon.frame = imageView.frame; // Frame can be changed after relayout.
   videoIcon.hidden = !bIsVideo;
}

bool LIOSPhotoGalleryControl::GetSelectedPaths(LFile::BrowseMultiplePaths& bmp)
{
   LFTRACE();
   LWindow* pWindow = LWindow::GetThisProperty(hwndParent);
   if (pWindow == nullptr) {
      LFDEBUG("Invalid window");
      return false;
   }
   
   for (LWindow::ISLSelectedIterator it(*pWindow, idControl); it.IsValid(); it.Next()) {
      PHAsset* asset = [fetchedAssets objectAtIndex:it.GetListViewID()];
      bmp.AddFilePath(LNS2CString(asset.localIdentifier));
   }

   return bmp.GetSize() != 0;
}

void LIOSPhotoGalleryControl::SetMediaType(int iMediaType)
{
   switch (iMediaType) {
      case MEDIA_TYPE_PHOTO: phMediaType = PHAssetMediaTypeImage; break;
      case MEDIA_TYPE_VIDEO: phMediaType = PHAssetMediaTypeVideo; break;
      case MEDIA_TYPE_PHOTO_AND_VIDEO: phMediaType = PHAssetMediaTypeUnknown; break;
      default: LFDEBUG("Unsupported media type"); break;
   };
}

void LIOSPhotoGalleryControl::SetCellSize(int _iCellSize)
{
   #ifdef BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE
   // Regenerate thumbnails.
   iCellSize = _iCellSize;
   [cacheImageManager stopCachingImagesForAllAssets];
   [cacheImageManager startCachingImagesForAssets:arAssets targetSize:CGSizeMake(iCellSize, iCellSize) contentMode:PHImageContentModeDefault options:imageRequestOptions];
   #endif

   LControlHandle hGalleryControl = LWindow::FindControlHandle(hwndParent, idControl);
   LUICollectionView(hGalleryControl).SetItemSize(_iCellSize, _iCellSize);
   LUICollectionView(hGalleryControl).ReloadData();
}


// ** LIOSCustomGallery
LIOSCustomGallery::LIOSCustomGallery(int iMediaType, LFile::BrowseMultiplePaths& _bmp, bool _bAllowMultiSel)
: AlbumGallery()
, PhotoGallery()
, bAllowMultiSel(_bAllowMultiSel)
, bmp(_bmp)
{
   LFTRACE("", iMediaType);
   AlbumGallery.SetMediaType(iMediaType);
   // Check if there are any media files of selected type
   if (!AlbumGallery.DoesMediaFilesExists()) {
      bool bShowWarning = false;
      if (iMediaType == MEDIA_TYPE_PHOTO) {
         if (LAlertWithButtonText::DisplayYesNo(GetWindowHandle(), TEXT(L_CUSTOMGALLERY_NoPhotos2), TEXT(L_CUSTOMGALLERY_PhotosNot), TEXT(L_CUSTOMGALLERY_OpenVideos), TEXT(L_CLOSE))) {
            iMediaType = MEDIA_TYPE_VIDEO;
            AlbumGallery.SetMediaType(iMediaType);
            // Another attempt to check if any files could be found.
            bShowWarning = !AlbumGallery.DoesMediaFilesExists();
         }
      } else if (iMediaType == MEDIA_TYPE_VIDEO) {
         if (LAlertWithButtonText::DisplayYesNo(GetWindowHandle(), TEXT(L_CUSTOMGALLERY_NoVideos), TEXT(L_CUSTOMGALLERY_VideosNot), TEXT(L_CUSTOMGALLERY_OpenPhotos), TEXT(L_CLOSE))) {
            iMediaType = MEDIA_TYPE_PHOTO;
            AlbumGallery.SetMediaType(iMediaType);
            // Another attempt to check if any files could be found.
            bShowWarning = !AlbumGallery.DoesMediaFilesExists();
         }
      } else {
         bShowWarning = true; // Don't try to open another media type, just show warning.
      }

      if (bShowWarning) {
         LIsMediaSourceAccessGranted(LIOS_MEDIA_SOURCE_PHOTO);
         LGetAccessToMediaSource(LIOS_MEDIA_SOURCE_PHOTO);
      }
   }
   PhotoGallery.SetMediaType(iMediaType);
}

bool LIOSCustomGallery::Open(LWindowHandle hwndParent)
{
   if (!AlbumGallery.DoesMediaFilesExists()) {
      // Just return, nothing to show.
      LFTRACE("There is no file of selected type");
      return false;
   }

   return LDialog::OpenBlank(hwndParent);
}

void LIOSCustomGallery::InitDialog()
{
   // Hide navigationBar, because dialog has it's own.
   HideTitleBar();
   
   LUINavigationBar NavBar(NAVIGATION_BAR_ID);
   NavBar.HandlePopItem(GetWindowHandle(), BACK_BUTTON_PRESSED_ID);
   AddControl(NavBar);
   NavbarAlbums = NavBar.GetTopNavigationItem();
   NavbarAlbums.SetCaption(TEXT(L_CUSTOMGALLERY_Collections));
   NavbarAlbums.SetRightButton(LUIBarButtonTitle(IDCANCEL, TEXT(L_CANCEL), UIBarButtonItemStyleDone), GetWindowHandle());
   
   AlbumGallery.Init(*this, ALBUM_GALLERY_CONTROL_ID);
   HandleISLSelChange(ALBUM_GALLERY_CONTROL_ID, ALBUM_SELECTED_MESSAGE_ID);

   PhotoGallery.Init(*this, PHOTO_GALLERY_CONTROL_ID);
   LUICollectionView(GetControlHandle(PHOTO_GALLERY_CONTROL_ID)).EnableMultipleSelection(bAllowMultiSel);
   HandleISLSelChange(PHOTO_GALLERY_CONTROL_ID, PHOTO_SELECTED_MESSAGE_ID);
   HideControl(PHOTO_GALLERY_CONTROL_ID);
}

void LIOSCustomGallery::DestroyDialog()
{
   ISLDestroy(ALBUM_GALLERY_CONTROL_ID);
   ISLDestroy(PHOTO_GALLERY_CONTROL_ID);
}

void LIOSCustomGallery::LayoutControls(int iWidth, int iHeight)
{
   const int iNavBarHeight = GetPixelsFromLogicalPoints(LUINavigationBar::GetDefaultHeightPts());
   MoveControlPixels(NAVIGATION_BAR_ID, 0, 0, iWidth, iNavBarHeight);
   const int iGalleryControlWidth = iWidth - (GetSpacerWidthPixels() * 2);
   const int iSpacerWidth = GetSpacerWidthPixels();
   const int iSpacerHeight = GetSpacerHeightPixels();
   MoveControlPixels(ALBUM_GALLERY_CONTROL_ID, iSpacerWidth, iNavBarHeight + iSpacerHeight, iGalleryControlWidth, iHeight - (iNavBarHeight + (iSpacerHeight * 2)));
   MoveControlPixels(PHOTO_GALLERY_CONTROL_ID, iSpacerWidth, iNavBarHeight + iSpacerHeight, iGalleryControlWidth, iHeight - (iNavBarHeight + (iSpacerHeight * 2)));

   // To avoid huge gap between cells try to select better size for cell based on gallery control width.
   int iColumnsCount = max(2, iGalleryControlWidth / ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT);
   int iGap = (iGalleryControlWidth % ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT) / (iColumnsCount - 1);
   int iCellSize = ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT; // Default value.
   
   // If gap is big or small calculate new cell size.
   if ((iGap < ISL_CUSTOM_GALLERY_CELL_GAP_MIN) || (iGap > ISL_CUSTOM_GALLERY_CELL_GAP_MAX)) {
      // Compare two cell sizes (fur current numbers of columns and for columns + 1).
      // Select size that is closer to default value.
      int iColumnWidthLower = iGalleryControlWidth / iColumnsCount;
      int iCellSizeLower = iColumnWidthLower - ISL_CUSTOM_GALLERY_CELL_GAP_MIN;
      int iColumnWidthGreather = iGalleryControlWidth / (iColumnsCount + 1);
      int iCellSizeGreather = iColumnWidthGreather - ISL_CUSTOM_GALLERY_CELL_GAP_MAX;
      if (abs(iColumnWidthLower - ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT) < abs(iCellSizeGreather - ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT)) iCellSize = iColumnWidthLower;
      else iCellSize = iCellSizeGreather;
   }
   
   iCellSize = ((iCellSize % 2) == 1) ? iCellSize - 1 : iCellSize; // Round down iCellSize to even value.

   // Set new cell size.
   AlbumGallery.SetCellSize(iCellSize);
   PhotoGallery.SetCellSize(iCellSize);
}

void LIOSCustomGallery::Command(CommandParmsWithNotify)
{
   switch (wID) {
      case ALBUM_SELECTED_MESSAGE_ID: {
         HideControl(ALBUM_GALLERY_CONTROL_ID);
         
         // update navigation bar
         if (!NavbarPhotos.IsValid()) {
            LUINavigationItem NavItem(TEXT(L_VIDEORC_Loading));
            NavItem.SetRightButton(LUIBarButtonTitle(IDOK, TEXT(L_DEL_SDKCLIENT_Done), UIBarButtonItemStyleDone), GetWindowHandle());
            NavbarPhotos = NavItem;
            NavbarPhotos.retain();
         }

         LUINavigationBar NavBar(GetControlHandle(NAVIGATION_BAR_ID));
         NavBar.PushNavigationItem(NavbarPhotos);
         
         // Display photos for selected album
         PHAssetCollection* collection = AlbumGallery.GetCollectionAtIndex(ISLGetCurSel(ALBUM_GALLERY_CONTROL_ID));
         PhotoGallery.SetAssetsCollection(collection);
         NavbarPhotos.SetCaption(TEXT(collection.localizedTitle.UTF8String));
         ISLSetCurSel(PHOTO_GALLERY_CONTROL_ID, -1); // remove selection
         ShowControl(PHOTO_GALLERY_CONTROL_ID);
      } break;
      case PHOTO_SELECTED_MESSAGE_ID: {
         
      } break;
      case BACK_BUTTON_PRESSED_ID: {
         HideControl(PHOTO_GALLERY_CONTROL_ID);
         ISLSetCurSel(ALBUM_GALLERY_CONTROL_ID, -1); // remove selection
         ShowControl(ALBUM_GALLERY_CONTROL_ID);
      } break;

      default:
         LDialog::Command(ArgumentsForCommandParmsWithNotify);
         break;
   }
}

bool LIOSCustomGallery::CmOk()
{
   return PhotoGallery.GetSelectedPaths(bmp);
}
