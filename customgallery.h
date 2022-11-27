// LIOSCustomGallery
// (c) LLib Source Code Trust. All rights reserved.
//
// BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE means to generate thumbnails exactly as
// gallery cell, they will be regenerated every time size of cell changed. By default
// macro disabled and thumbnails cached and generated in default size
// and resized by UIImageView itself.
//

#pragma once
#include <llib/gui/dialog.h>
#include <llib/gui/interwinmsg.h>
#include <llib/ios/uicollectionviewcell.h>
#include <llib/ios/uinavigationbar.h>

#define MEDIA_TYPE_PHOTO           0
#define MEDIA_TYPE_VIDEO           1
#define MEDIA_TYPE_PHOTO_AND_VIDEO 2

#define ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT     120 // Default cell size.

// ** LGalleryThumbnailCallback

class LGalleryThumbnailCallback {
public:
   virtual void SetThumbnail(int iItemIndex, LUICollectionViewCellImpl* cell, CGSize size = CGSizeMake(ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT, ISL_CUSTOM_GALLERY_CELL_SIZE_DEFAULT)) = 0; // Set thumbnail for iItemIndex asynchroniously to cell.
   virtual void AddSubviews(UIView* viewCell, int iItemIndex, int iItemData) { (void)viewCell; (void)iItemIndex; (void)iItemData; } // don't add any subviews by default
};

// ** LIOSCollectionGalleryControl

class LIOSCollectionGalleryControl:public LGalleryThumbnailCallback {
public:
   explicit LIOSCollectionGalleryControl();
   ~LIOSCollectionGalleryControl();
   
   void Init(LWindow& Parent, LWindow::cid idControl); // starts the thread
   
   PHAssetCollection* GetCollectionAtIndex(uint32_t nIndex);

   virtual void SetThumbnail(int iItemIndex, LUICollectionViewCellImpl* cell, CGSize size);
   bool IsEmpty(); // Returns true if there is no any collection to show with required media type

   void SetMediaType(int iMediaType); // Change media type to show. Returns true if possible to change media type i.e. if there are any files of selected type.

   bool DoesMediaFilesExists() const; // Detect if there are any files of selected media type.
   
   void SetCellSize(int iCellSize);   // Set cell size of CollectionView that displays gallery.

protected:
   NSMutableArray* arrCollections; // Only non empty collections
   PHAssetMediaType phMediaType;
   PHFetchOptions* fetchCollectionOptions;
   PHFetchOptions* fetchAssetOptions;
   PHImageRequestOptions* imageRequestOptions;

   LWindowHandle hwndParent;
   LWindow::cid idControl;
};

class LIOSPhotoGalleryControl:public LGalleryThumbnailCallback {
public:
   LIOSPhotoGalleryControl();
   ~LIOSPhotoGalleryControl();
   
   void Init(LWindow& Parent, LWindow::cid idControl);
   void SetAssetsCollection(PHAssetCollection* collection);
   
   virtual void SetThumbnail(int iItemIndex, LUICollectionViewCellImpl* cell, CGSize size);
   virtual void AddSubviews(UIView* viewCell, int iItemIndex, int iItemData);
   
   bool GetSelectedPaths(LFile::BrowseMultiplePaths& bmp);

   void SetMediaType(int iMediaType); // Change media type to show. Returns true if possible to change media type i.e. if there are any files of selected type.

   void SetCellSize(int iCellSize);   // Set cell size of CollectionView that displays album.

protected:
   PHFetchResult<PHAsset*>* fetchedAssets;
   PHAssetMediaType phMediaType;
   PHCachingImageManager* cacheImageManager;
   NSMutableArray* arAssets;
   PHImageRequestOptions* imageRequestOptions;

   LWindowHandle hwndParent;
   LWindow::cid idControl;
   #ifdef BUILD_CUSTOMGALLERY_GENERATE_THUMBS_CELL_SIZE
   int iCellSize; // Save cell size for further regenerating
   #endif
};

class LIOSCustomGallery:public LDialog {
public:
   explicit LIOSCustomGallery(int iMediaType, LFile::BrowseMultiplePaths& bmp, bool bAllowMultiSel = true); // See LIOSCollectionGalleryControl::iMediaType
   
   virtual void InitDialog();
   virtual void DestroyDialog();
   virtual void LayoutControls(int iWidth, int iHeight);
   virtual void Command(CommandParmsWithNotify);
   virtual bool CmOk();

   bool Open(LWindowHandle hwndParent);

protected:
   LUINavigationItemRef NavbarAlbums;
   LUINavigationItemRef NavbarPhotos;
   
   LIOSCollectionGalleryControl AlbumGallery;
   LIOSPhotoGalleryControl PhotoGallery;
   bool bAllowMultiSel;
   LFile::BrowseMultiplePaths& bmp; // Save selected path on closing
};
