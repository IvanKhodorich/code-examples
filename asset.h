// Helper methods to work with ALAsset objects.
// (c) LLib Source Code Trust. All rights reserved
//
#ifndef ios_asset_h
#define ios_asset_h

#include <llib/gen/llibbase.h>
#include <llib/gen/map.h>
#include <llib/gen/thread.h>
#include <llib/ios/uiimage.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>

// This is wrapper around a map that set relations between PHAsset
// and its local identifier.
// Map owns PHAsset pointer to make it easy and faster access to phAsset.
// PHAsset is metaobject so don't take a lot of space while preformance gain
// is possible in some curtumstances.

class LIOSPHAssetLibrary {
public:
   static LIOSPHAssetLibrary& GetInstance(); // Returns singleton object. Returns static object to have ability to release PHAssets in destructor. Usually created when trying to get photo/video from iOS Photos.
   ~LIOSPHAssetLibrary();

   bool IsAssetValid(const tchar* szPath); // Non-const because can add phAsset into map. through GetAssetFromIOS.
   PHAsset* GetAsset(const tchar* szPath); // Non-const because can add phAsset into map. through GetAssetFromIOS.

private:
   LIOSPHAssetLibrary() {}                   // Only allow GetInstance() for handling LIOSPHAssetLibrary.
   bool GetAssetFromIOS(const tchar* szPath, PHAsset** pPhAsset = nil);

   LMap<LMapStringKey, PHAsset*> mapPHAssets;
   LMutex mtxMapAccess;
};

// ** LIOSAsset

class LIOSAsset {
public:
   explicit LIOSAsset(PHAsset* phAsset);
   explicit LIOSAsset(const tchar* szPath); // szPath should present localIdentifier
   ~LIOSAsset();
   
   bool IsValid() const;
   
   LUIImage GetImage(bool bIsHighQuality = true, CGSize size = CGSizeZero); // Use it when there is no true LProcessInterface
   LUIImage GetImage(LProcessInterface& Interface, bool bIsHighQuality = true, CGSize size = CGSizeZero); // Don't use it with LProcessInterfaceVoid.
   AVAsset* GetAVAsset(); // Use it when there is no true LProcessInterface
   AVAsset* GetAVAsset(LProcessInterface& Interface); // Don't use with LProcessInterfaceVoid.

   int GetWidthPixels() const;
   int GetHeightPixels() const;

   // The following functions are slow and not always returns valid data because PHAssetResource is empty.
   // Try to avoid of using them. Assume that if asset is valid it can be used later.
   // Check result after using of them.
   bool GetFullFileName(tchar* szFile);            // Returns file.jpg
   bool GetFileName(tchar* szFileName);            // Returns file
   bool GetFileExtension(tchar* szExtension);      // Returns .jpg

   bool IsImageAsset() const;                      // Returns true if assets represents image
   static bool GetFileFromAsset(tchar* szFile, const tchar* szAsset);                  // Returns file.jpg
   static bool GetFileNameFromAsset(tchar* szFileName, const tchar* szAsset);          // Returns file
   static bool GetFileExtensionFromAsset(tchar* szExtension, const tchar* szAsset);    // Returns .jpg
   static void GetFileTitle(tchar* szName, const tchar* szPath);

   static ALAssetsLibrary* GetLibrary();
   
protected:

   PHAsset* phAsset;            // iOS asset
   LUIImage image;              // Image that represents asset
   LSignalObject soLoadingVideo; // SO for loading AVAsset* video
   LSignalObject soLoadingImage; // SO for loading AVAsset* image
   PHImageRequestID requestID;

private:
   lprresult_t GetImageWithOptions(LProcessInterface& Interface, PHImageRequestOptions* options, CGSize size); // Don't use it with LProcessInterfaceVoid.
   bool GetImageWithOptions(PHImageRequestOptions* options, CGSize size);
};


// Adds image file with szImageFilePath to user's photo library.
// Returns szAssetURL of a new file in the library.

class LIOSAddImageToLibrary {
public:
   tchar szImageFilePath[LSTR];
   tchar szAssetURL[LSTR];
};

lprresult_t Process(LProcessInterface& Interface, LIOSAddImageToLibrary& Data);


// Adds video file with szVideoFilePath to user's photo library.
// Returns szAssetURL of a new file in the library.

class LIOSAddVideoToLibrary {
public:
   tchar szVideoFilePath[LSTR];
   tchar szAssetURL[LSTR];
};

lprresult_t Process(LProcessInterface& Interface, LIOSAddVideoToLibrary& Data);

#endif // ios_asset_h
