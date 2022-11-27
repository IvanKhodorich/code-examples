#include <llib/ios/asset.h>
#include <llib/gen/file.h>
#include <llib/gen/map.h>
#include <llib/gen/stringparse.h>
#include <llib/ios/app.h>
#include <llib/ios/eventqueue.h>
#include <llib/mobile/mediapicker.h>
#import <libkern/OSAtomic.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

// By default 15mpx resolution is used as limit for loaded asset. Bigger images will be scaled down silently
// It could be set in build.h
#ifndef LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS
#define LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS    4500
#endif // LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS
#ifndef LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS
#define LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS   3300
#endif // LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS

// Minimum scale resolution. If image is failed to load with own resolution, it will be scaled down.
// It could be set in build.h
#ifndef LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS
#define LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS    1920
#endif // LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS
#ifndef LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS
#define LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS   1440
#endif // LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS

// ** LIOSPHAssetLibrary
LIOSPHAssetLibrary::~LIOSPHAssetLibrary()
{
   LFTRACE();
   for (LMap<LMapStringKey, PHAsset*>::Iterator iterMap(mapPHAssets); iterMap.IsValid(); iterMap.Next()) {
      PHAsset* pPHAsset = iterMap->value;
      [pPHAsset release];
   }
}

LIOSPHAssetLibrary& LIOSPHAssetLibrary::GetInstance()
{
   static LIOSPHAssetLibrary PHAssetLibary;
   return PHAssetLibary;
}

bool LIOSPHAssetLibrary::IsAssetValid(const tchar* szPath)
{
   // First check if szPath contains "/private/var" or "/var" which is default mount point
   // for local and iCloud files. Photo identifier looks like "46A91588-B3A3-40D7-97E5-19501822DB30/L0/001".
   // This prevents from accessing PhotoLibrary in most obvious cases and asking user's permission.
   if ((tstrstr(szPath, TEXT("/private/var")) != nullptr) ||
       (tstrstr(szPath, TEXT("/var")) != nullptr) ||
       (tstrstr(szPath, TEXT("/Users")) != nullptr) // For Simulator builds.
       #ifndef NDEBUG
       || (tstrstr(szPath, TEXT("/SourceCode")) != nullptr) // For unit tests.
       #endif
       ) {
      return false;
   }

   // First of all check map.
   if (mapPHAssets.DoesExist(szPath)) return true;

   return GetAssetFromIOS(szPath);
}

bool LIOSPHAssetLibrary::GetAssetFromIOS(const tchar* szPath, PHAsset** pPhAsset)
{
   if ((szPath == nullptr) || (szPath[0] == 0)) {
      LFDEBUG("Empty asset path");
      return false;
   }
   
   NSString* nszPath = LMacNSStringFromString(szPath);
   if (nszPath == nil) return false;
   
   // Check first if the user has granted access to the Photo Library.
   // We do not want to automatically ask the user for permission at this function because it can be called from anywhere
   // like application startup. Permission should only be requested at the moment it is needed or we risk Apple rejection.
   if (!LIsMediaSourceAccessGranted(LIOS_MEDIA_SOURCE_PHOTO)) {
      LFDEBUG("No permission to access Photo Library yet. Use LGetAccessToMediaSource(), or LFile::BrowsePhoto*() functions to get access to the Photo library.");
      return false;
   }
   
   // NOTE: This line automatically requests for Photo Library access, which we do not want. See comment at call to LIsMediaSourceAccessGranted() above.
   PHAsset* phAsset = [[PHAsset fetchAssetsWithLocalIdentifiers:[NSArray arrayWithObject:nszPath] options:nil] lastObject];
   
   if (phAsset == nil) return false;

   [phAsset retain]; // Takes ownership. Free on destructor.

   mtxMapAccess.Lock();
   // Save phAsset in local map to have faster access.
   mapPHAssets.SetValue(szPath, phAsset);
   mtxMapAccess.Unlock();

   if (pPhAsset != nil) *pPhAsset = phAsset;
   return true;
}

PHAsset* LIOSPHAssetLibrary::GetAsset(const tchar* szPath)
{
   mtxMapAccess.Lock();
   PHAsset* phAsset = mapPHAssets.GetValue(szPath, nil);
   mtxMapAccess.Unlock();

   if (phAsset == nil) {
      // Check and add to map
      if (!GetAssetFromIOS(szPath, &phAsset)) {
         return nil;
      }
   }
   return phAsset;
}

// ** LIOSAsset

LIOSAsset::LIOSAsset(PHAsset* _phAsset)
: requestID(PHInvalidImageRequestID)
{
   phAsset = [_phAsset retain];
}

LIOSAsset::LIOSAsset(const tchar* szPath)
: phAsset(nil)
, requestID(PHInvalidImageRequestID)
{
   phAsset = LIOSPHAssetLibrary::GetInstance().GetAsset(szPath);
   if (phAsset == nil) {
      LFDEBUG("Failed to get PHAsset from: ", szPath);
      return;
   }
   [phAsset retain];
}

LIOSAsset::~LIOSAsset()
{
   if (phAsset != nil) {
      [phAsset release];
      phAsset = nil;
   }
}

bool LIOSAsset::IsValid() const
{
   return (phAsset != nil);
}

LUIImage LIOSAsset::GetImage(bool bIsHighQuality, CGSize size)
{
   LFTRACE();
   if (!IsValid()) {
      LFDEBUG("Asset is invalid");
      return image;
   }
   
   if (CGSizeEqualToSize(size, CGSizeZero)) size = CGSizeMake(CGFloat(phAsset.pixelWidth), CGFloat(phAsset.pixelHeight)); // Default values
   if (int(size.width * size.height) > LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS * LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS) {
      // Update image size, so total size is not bigger than LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS * LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS
      int iNewImageWidthPixels = size.width; // Default values
      int iNewImageHeightPixels = size.height;
      if (size.width > size.height) LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS, LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      else LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS, LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      size.width = double(iNewImageWidthPixels);
      size.height = double(iNewImageHeightPixels);
   }
   
   PHImageManager* imageManager = [PHImageManager defaultManager];
   PHImageRequestOptions* options = [[[PHImageRequestOptions alloc] init] autorelease];
   // Both cases garantee that block handler will be called only once.
   options.deliveryMode = bIsHighQuality ? PHImageRequestOptionsDeliveryModeHighQualityFormat : PHImageRequestOptionsDeliveryModeFastFormat;
   options.synchronous = YES; // Be careful to block main thread for a long time.
   options.networkAccessAllowed = YES; // Allow to download files stored on iCloud.
   options.resizeMode = PHImageRequestOptionsResizeModeExact;

   // Sometimes image can't be downloaded with required options. Possibly this happens because
   // of iCloud photos are not synced well.
   // https://stackoverflow.com/questions/31670929/how-to-convert-phasset-to-uiimage-in-objective-c
   // https://stackoverflow.com/questions/31037859/phimagemanager-requestimageforasset-returns-nil-sometimes-for-icloud-photos
   // Now there is not 100% solution or workarounds. Error could non informative
   // Some things we can do:
   // 1. Try to download image in smaller size if possible (~1920x1440)
   // 2. Try to download image in low/high quality
   
   GetImageWithOptions(options, size);
   if ((!image.IsValid()) && (int(size.width * size.height) > (LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS * LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS))) {
      LFDEBUG("Failed to get image with default options. Try download in smaller size");
      // Try to load smaller version
      int iNewImageWidthPixels = LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS; // Default values
      int iNewImageHeightPixels = LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS;
      if (size.width > size.height) LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS, LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      else LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS, LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      CGSize sizeScaled = CGSizeMake(CGFloat(iNewImageWidthPixels), CGFloat(iNewImageHeightPixels));
      GetImageWithOptions(options, sizeScaled);
   }

   if (!image.IsValid()) {
      LFDEBUG("Failed to get image in smaller size. Try download in another quality");
      PHImageRequestOptions* optionsQuality = [[options copy] autorelease];
      // Try to load in another quality
      options.deliveryMode = bIsHighQuality ? PHImageRequestOptionsDeliveryModeFastFormat : PHImageRequestOptionsDeliveryModeHighQualityFormat;
      GetImageWithOptions(optionsQuality, size);
   }

   return image;
}

LUIImage LIOSAsset::GetImage(LProcessInterface& Interface, bool bIsHighQuality, CGSize size)
{
   LFTRACE();
   if (!IsValid()) {
      LFDEBUG("Asset is invalid");
      return image;
   }

   if (CGSizeEqualToSize(size, CGSizeZero)) size = CGSizeMake(CGFloat(phAsset.pixelWidth), CGFloat(phAsset.pixelHeight)); // Default values
   if (int(size.width * size.height) > LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS * LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS) {
      // Update image size, so total size is not bigger than LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS * LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS
      int iNewImageWidthPixels = size.width; // Default values
      int iNewImageHeightPixels = size.height;
      if (size.width > size.height) LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS, LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      else LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_SHORT_SIZE_LIMIT_PIXELS, LIOS_ASSET_LONG_SIZE_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      size.width = double(iNewImageWidthPixels);
      size.height = double(iNewImageHeightPixels);
   }

   PHImageRequestOptions* options = [[[PHImageRequestOptions alloc] init] autorelease];
   // Both cases garantee that block handler will be called only once.
   options.deliveryMode = bIsHighQuality ? PHImageRequestOptionsDeliveryModeHighQualityFormat : PHImageRequestOptionsDeliveryModeFastFormat;
   options.networkAccessAllowed = YES; // Allow to download files stored on iCloud.
   options.resizeMode = PHImageRequestOptionsResizeModeExact;
   options.progressHandler = ^(double dProgress, NSError* error, BOOL* pbStop, NSDictionary* info) {
      (void)info;
      (void)pbStop;
      if (error != nil) LFDEBUGF("Error downloading file: %s", error.localizedDescription.UTF8String);
      Interface.SetProgress(dProgress);
   };
   
   // Sometimes image can't be downloaded with required options. Possibly this happens because
   // of iCloud photos are not synced well.
   // https://stackoverflow.com/questions/31670929/how-to-convert-phasset-to-uiimage-in-objective-c
   // https://stackoverflow.com/questions/31037859/phimagemanager-requestimageforasset-returns-nil-sometimes-for-icloud-photos
   // Now there is not 100% solution or workarounds. Error could non informative
   // Some things we can do:
   // 1. Try to download image in smaller size if possible (~1920x1440)
   // 2. Try to download image in low/high quality
   
   lprresult_t lpResult = GetImageWithOptions(Interface, options, size);
   if ((lpResult == LPROCESS_FAILED) && (int(size.width * size.height) > (LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS * LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS))) {
      LFDEBUG("Failed to get image with default options. Try download in smaller size");
      // Try to load smaller version
      int iNewImageWidthPixels = LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS; // Default values
      int iNewImageHeightPixels = LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS;
      if (size.width > size.height) LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS, LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      else LInscribeRect(int(size.width), int(size.height), LIOS_ASSET_SHORT_SIZE_MIN_LIMIT_PIXELS, LIOS_ASSET_LONG_SIZE_MIN_LIMIT_PIXELS, iNewImageWidthPixels, iNewImageHeightPixels);
      CGSize sizeScaled = CGSizeMake(CGFloat(iNewImageWidthPixels), CGFloat(iNewImageHeightPixels));
      lpResult = GetImageWithOptions(Interface, options, sizeScaled);
   }

   if (lpResult == LPROCESS_FAILED) {
      LFDEBUG("Failed to get image in smaller size. Try download in another quality");
      PHImageRequestOptions* optionsQuality = [[options copy] autorelease];
      // Try to load in another quality
      options.deliveryMode = bIsHighQuality ? PHImageRequestOptionsDeliveryModeFastFormat : PHImageRequestOptionsDeliveryModeHighQualityFormat;
      lpResult = GetImageWithOptions(Interface, optionsQuality, size);
   }

   return image;
}

lprresult_t LIOSAsset::GetImageWithOptions(LProcessInterface& Interface, PHImageRequestOptions* options, CGSize size)
{
   LFTRACE();
   if (Interface.IsToStop()) return LPROCESS_STOPPED;
   // There are two ways to get image. Sync and async requests.
   // Async requests can be interrupted and much better correspond to
   // LProcessInterface behavior (cancel image request when LProcessInterface stopped). But there is the problem with using async request, because
   // async request executes on the main thread so background thread should
   // synchronized with main thread to wait when image loaded on not loaded (cancelled).
   // It's possible that background thread that loads image should be stopped.
   // In this case background thread will wait while resultHandler block executes
   // on the main thread but main thread will wait while background thread stops.
   // From all possible solutions and scenarios that happens the most
   // best and safe is to use sync request on background thread to avoid problems
   // with dead lock or using of deallocated objects due to bad sync between threads.
   if (!LIsMainThread()) options.synchronous = YES;

   if (options.synchronous == YES) {
      return (GetImageWithOptions(options, size)) ? LPROCESS_COMPLETE : LPROCESS_FAILED;
   } else {
      // resultHandler will be called on main thread.
      // Be careful to block main thread by using LProcessInterfaceVoid on main thread.
      // Better to use sync method instead of LProcessInterfaceVoid on main thread.
      soLoadingImage.Reset();
      requestID = [[PHImageManager defaultManager] requestImageForAsset:phAsset targetSize:size contentMode:PHImageContentModeDefault options:options resultHandler:^(UIImage* result, NSDictionary* info) {
         // Check if process stopped and image request cancelled.
         NSNumber* bCancelled = [info objectForKey:PHImageCancelledKey];
         if (!bCancelled.boolValue) {
            NSError* error = [info objectForKey:PHImageErrorKey];
            if (error != nil) LFDEBUGF("Error loading file: %s", error.localizedDescription.UTF8String);
            else image.Attach(result); // Take ownership.
         }
         requestID = PHInvalidImageRequestID;
         soLoadingImage.Signal();
      }];

      // Wait while image returned
      lprresult_t lpResult = Interface.ProcessWaitSignalForever(soLoadingImage);
      if (lpResult == LPROCESS_STOPPED) {
         // Cancel request if Interface stopped or failed.
         [[PHImageManager defaultManager] cancelImageRequest:requestID];
         // Wait while resultHandler finishes.
         // It's not possible to cancel block execution and not possible
         // garantee that image will be invalid. It's needed to
         // wait when block executes to avoid bad memory exception
         // because of bad sync between threads (soLoadingImage can be deallocated on background
         // thread and still called on main thread inside resultHandler)
         // Don't block main thread. Interface already stopped.
         bool (^stopCondition) () = ^bool() {
            return soLoadingImage.IsSignaled();
         };
         lpResult = LEventQueueRunUntilStopCondition(stopCondition);
         if (lpResult != LPROCESS_COMPLETE) {
            LFDEBUG("LEventQueueRunUntilStopCondition failed.");
         }
      }

      return lpResult;
   }
}

bool LIOSAsset::GetImageWithOptions(PHImageRequestOptions* options, CGSize size)
{
   LFTRACE();
   if (options.synchronous != YES) {
      // Don't call this version with async option, because block will not be called and function returns nil.
      LFDEBUG("options.synchronous is NO. Image downloading could fail");
   }
   [[PHImageManager defaultManager] requestImageForAsset:phAsset targetSize:size contentMode:PHImageContentModeDefault options:options resultHandler:^(UIImage* result, NSDictionary* info) {
      NSError* error = [info objectForKey:PHImageErrorKey];
      if (error != nil) LFDEBUGF("Error loading file: %s", error.localizedDescription.UTF8String);
      else image.Attach(result); // Take ownership.
   }];
   return image.IsValid();
}

AVAsset* LIOSAsset::GetAVAsset()
{
   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return nil;
   }
   PHVideoRequestOptions* options = [[[PHVideoRequestOptions alloc] init] autorelease];
   options.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat; // Other options doesn't get tracks from returned AVAsset if placed on iCloud. Other options are for streaming while PHVideoRequestOptionsDeliveryModeHighQualityFormat is for editing/exporting.
   options.networkAccessAllowed = YES; // Allow to download files stored on iCloud.
   __block AVAsset* avAsset = nil;
   soLoadingVideo.Reset();
   // The result handler is called on an arbitrary queue.
   [[PHImageManager defaultManager] requestAVAssetForVideo:phAsset options:options resultHandler:^(AVAsset* _avAsset, AVAudioMix* audioMix, NSDictionary* info) {
      NSError* error = [info objectForKey:PHImageErrorKey];
      if (error != nil) LFDEBUGF("Error loading file: %s", error.localizedDescription.UTF8String);
      else {
         avAsset = _avAsset;
         [avAsset retain]; // Take ownership.
      }
      soLoadingVideo.Signal();
   }];

   soLoadingVideo.WaitSignalForever();

   return [avAsset autorelease];
}

AVAsset* LIOSAsset::GetAVAsset(LProcessInterface& Interface)
{
   if (Interface.IsToStop()) return nil;

   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return nil;
   }
   PHImageManager* imageManager = [PHImageManager defaultManager];
   PHVideoRequestOptions* options = [[[PHVideoRequestOptions alloc] init] autorelease];
   options.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat; // Other options doesn't get tracks from returned AVAsset if placed on iCloud. Other options are for streaming while PHVideoRequestOptionsDeliveryModeHighQualityFormat is for editing/exporting.
   options.networkAccessAllowed = YES; // Allow to download files stored on iCloud.
   // Progress handler, called in an arbitrary serial queue: only called when the data is not available locally and is retrieved from iCloud
   options.progressHandler = ^(double dProgress, NSError* error, BOOL* pbStop, NSDictionary* info) {
      (void)info;
      (void)pbStop;
      if (error != nil) LFDEBUGF("Error downloading file: %s", error.localizedDescription.UTF8String);
      Interface.SetProgress(dProgress); // Move to main thread.
   };
   __block AVAsset* avAsset = nil;
   soLoadingVideo.Reset();
   // The result handler is called on an arbitrary queue.
   requestID = [imageManager requestAVAssetForVideo:phAsset options:options resultHandler:^(AVAsset* _avAsset, AVAudioMix* audioMix, NSDictionary* info) {
      // Check if process stopped and video request cancelled. It's important to not
      // continue because block can be called when object is already invalid.
      NSNumber* bCancelled = [info objectForKey:PHImageCancelledKey];
      if (!bCancelled.boolValue) {
         NSError* error = [info objectForKey:PHImageErrorKey];
         if (error != nil) LFDEBUGF("Error loading file: %s", error.localizedDescription.UTF8String);
         else {
            avAsset = _avAsset;
            [avAsset retain]; // Take ownership.
         }
      }
      requestID = PHInvalidImageRequestID;
      soLoadingVideo.Signal();
   }];
   
   if (Interface.ProcessWaitSignalForever(soLoadingVideo) != LPROCESS_COMPLETE) {
      [imageManager cancelImageRequest:requestID];
      // It's needed to wait until resultHandler block will be called and soLoadingVideo
      // be signalled. It's important because in opposite case this instance of LIOSAsset
      // can be freed before resultHandler block executes and this leads to memory leak or
      // bad memory address exception.
      // Don't block main thread. Interface already stopped.
      if (LIsMainThread()) {
         bool (^stopCondition) () = ^bool() {
            return soLoadingVideo.IsSignaled();
         };
         if (LEventQueueRunUntilStopCondition(stopCondition) != LPROCESS_COMPLETE) {
            LFDEBUG("LEventQueueRunUntilStopCondition failed.");
         }
      } else soLoadingVideo.WaitSignalForever();
      return nil;
   }
   
   return [avAsset autorelease];
}

int LIOSAsset::GetWidthPixels() const
{
   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return 0;
   }
   return int(phAsset.pixelWidth);
}

int LIOSAsset::GetHeightPixels() const
{
   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return 0;
   }
   return int(phAsset.pixelHeight);
}

bool LIOSAsset::IsImageAsset() const
{
   return (phAsset.mediaType == PHAssetMediaTypeImage);
}

bool LIOSAsset::GetFileFromAsset(tchar* szFile, const tchar* szAsset)
{
   szFile[0] = 0;
   if (LIOSPHAssetLibrary::GetInstance().IsAssetValid(szAsset)) {
      LIOSAsset asset(LIOSPHAssetLibrary::GetInstance().GetAsset(szAsset));
      return asset.GetFullFileName(szFile);
   }
   return false;
}

bool LIOSAsset::GetFileExtensionFromAsset(tchar* szExtension, const tchar* szAsset)
{
   szExtension[0] = 0;
   if (LIOSPHAssetLibrary::GetInstance().IsAssetValid(szAsset)) {
      LIOSAsset asset(LIOSPHAssetLibrary::GetInstance().GetAsset(szAsset));
      return asset.GetFileExtension(szExtension);
   }
   return false;
}

bool LIOSAsset::GetFileNameFromAsset(tchar* szFileName, const tchar* szAsset)
{
   szFileName[0] = 0;
   if (LIOSPHAssetLibrary::GetInstance().IsAssetValid(szAsset)) {
      LIOSAsset asset(LIOSPHAssetLibrary::GetInstance().GetAsset(szAsset));
      return asset.GetFileName(szFileName);
   }
   return false;
}

bool LIOSAsset::GetFullFileName(tchar* szFile)
{
   szFile[0] = 0;
   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return false;
   }
   NSArray* arrAssetResource = [PHAssetResource assetResourcesForAsset:phAsset];
   if (arrAssetResource.count > 0) {
      PHAssetResource* assetResource = [arrAssetResource objectAtIndex:0];
      tlstrcpy(szFile, assetResource.originalFilename.UTF8String);
      return true;
   } else {
      LFTRACE("Failed to get full file name. Data can be corrupted.");
      return false;
   }
}

bool LIOSAsset::GetFileName(tchar* szFileName)
{
   szFileName[0] = 0;
   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return false;
   }
   NSArray* arrAssetResource = [PHAssetResource assetResourcesForAsset:phAsset];
   if (arrAssetResource.count > 0) {
      PHAssetResource* assetResource = [arrAssetResource objectAtIndex:0];
      LFile::GetFileNameFromPath(szFileName, assetResource.originalFilename.UTF8String);
      return true;
   } else {
      LFTRACE("Failed to get file name. Data can be corrupted.");
      return false;
   }
}

bool LIOSAsset::GetFileExtension(tchar* szExtension)
{
   szExtension[0] = 0;
   if (!IsValid()) {
      LFDEBUG("Not a valid asset");
      return false;
   }
   NSArray* arrAssetResource = [PHAssetResource assetResourcesForAsset:phAsset];
   if (arrAssetResource.count > 0) {
      PHAssetResource* assetResource = [arrAssetResource objectAtIndex:0];
      LFile::GetFileExtensionFromPath(szExtension, assetResource.originalFilename.UTF8String);
      return true;
   } else {
      LFTRACE("Failed to get extension. Data can be corrupted.");
      return false;
   }
}

void LIOSAsset::GetFileTitle(tchar* szName, const tchar* szURL)
{
   NSString *audioFile = [NSString stringWithFormat:@"%s", szURL];

   // Create Query object
   MPMediaQuery *songQuery = [[[MPMediaQuery alloc] init] autorelease];

   for (MPMediaItem *item in songQuery.items) {
      // Compare url string
      // iOS7 only support valueForProperty not valueForKey
      if (![audioFile isEqualToString:[[item valueForProperty:MPMediaItemPropertyAssetURL] absoluteString]]) continue;
      
      // Copy title
      tlstrcpy(szName, LNS2CString(item.title));
      break;
   }
   return ;
}

ALAssetsLibrary* LIOSAsset::GetLibrary()
{
   static ALAssetsLibrary* library = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      library = [[ALAssetsLibrary alloc] init]; // Create assets library.
      #ifdef BUILD_IOS_CAMERA_PERMISSION_WHEN_CREATE_ASSETSLIBRARY
      // Check permission to Camera library. iOS11 could have in some cases only writable access
      // so ask for permission here and be sure that read/write access is approved.
      if (!LIsMediaSourceAccessGranted(LIOS_MEDIA_SOURCE_PHOTO)) {
         LGetAccessToMediaSource(LIOS_MEDIA_SOURCE_PHOTO);
      }
      #endif
   });
   ASSERT(library != nil);
   return library;
}

// ** Process(LIOSAddImageToLibrary)

lprresult_t Process(LProcessInterface& Interface, LIOSAddImageToLibrary& Data)
{
   NSData* imageData = [NSData dataWithContentsOfFile:LC2NSString(Data.szImageFilePath)];
   
   __block bool bResult = false;
   __block bool bDidFinish = false;
   
   // Request to save the image to the photo library
   [LIOSAsset::GetLibrary() writeImageDataToSavedPhotosAlbum:imageData metadata:nil completionBlock:^(NSURL* assetURL, NSError* error){
      if (error) {
         LDEBUG("Process(LIOSAddImageToLibrary) Failed to save image to the photo library");
         bResult = false;
         bDidFinish = true;
      } else {
         tlstrcpy(Data.szAssetURL, LNS2CString(assetURL.path));
         bResult = true;
         bDidFinish = true;
      }
   }];

   while (!Interface.IsToStop() && !bDidFinish) LEventQueueProcessOneEventWait();
   
   if (bResult) return LPROCESS_COMPLETE;
   return Interface.IsToStop() ? LPROCESS_STOPPED : LPROCESS_FAILED;
}


// ** Process(LIOSAddVideoToLibrary)

lprresult_t Process(LProcessInterface& Interface, LIOSAddVideoToLibrary& Data)
{
   NSURL* videoURL = [NSURL fileURLWithPath:LC2NSString(Data.szVideoFilePath)];
   
   __block bool bResult = false;
   __block bool bDidFinish = false;
   
   // Request to save the video to the camera roll
   [LIOSAsset::GetLibrary() writeVideoAtPathToSavedPhotosAlbum:videoURL completionBlock:^(NSURL* assetURL, NSError* error){
      if (error) {
         LDEBUG("Process(LIOSAddVideoToLibrary) Failed to save video to the camera roll");
         bResult = false;
         bDidFinish = true;
      } else {
         tlstrcpy(Data.szAssetURL, LNS2CString(assetURL.path));
         bResult = true;
         bDidFinish = true;
      }
   }];
   
   while (!Interface.IsToStop() && !bDidFinish) LEventQueueProcessOneEventWait();

   
   if (bResult) return LPROCESS_COMPLETE;
   return Interface.IsToStop() ? LPROCESS_STOPPED : LPROCESS_FAILED;
}
