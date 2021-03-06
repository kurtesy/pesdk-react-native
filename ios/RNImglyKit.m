#import "RNImglyKit.h"
#import "RNImglyKitSubclass.h"

#define DEBUG_RN_IMGLY 0

@implementation RNPESDKImglyKit

NSString *const kErrorUnableToUnlock = @"E_UNABLE_TO_UNLOCK";
NSString *const kErrorUnableToLoad = @"E_UNABLE_TO_LOAD";
NSString *const kErrorUnableToExport = @"E_UNABLE_TO_EXPORT";

NSString *const kExportTypeFileURL = @"file-url";
NSString *const kExportTypeDataURL = @"data-url";
NSString *const kExportTypeObject = @"object";

- (void)dealloc {
  [self dismiss:self.mediaEditViewController animated:NO];
}

- (void)present:(nonnull PESDKMediaEditViewControllerBlock)mediaEditViewController withUTI:(nonnull IMGLYUTIBlock)uti
  configuration:(nullable NSDictionary *)dictionary serialization:(nullable NSDictionary *)state
        resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject
{
#if DEBUG_RN_IMGLY
  {
    // For release debugging
    NSURL *debugURL = [RCTConvert IMGLYExportFileURL:@"imgly-debug" withExpectedUTI:kUTTypeJSON];
    if (debugURL) {
      NSError *error = nil;
      NSJSONWritingOptions debugOptions = NSJSONWritingPrettyPrinted;
      if (@available(iOS 11.0, *)) { debugOptions = debugOptions | NSJSONWritingSortedKeys; }
      NSData *debugData = [NSJSONSerialization dataWithJSONObject:dictionary options:debugOptions error:&error];
      [debugData imgly_writeToURL:debugURL andCreateDirectoryIfNecessary:YES error:&error];
      if (error != nil) {
        NSLog(@"Could not write debug configuration: %@", error);
      } else {
        NSLog(@"Wrote debug configuration to URL: %@", debugURL);
      }
    }
  }
#endif

  __block NSError *error = nil;
  NSData *serializationData = nil;
  if (state != nil) {
    serializationData = [NSJSONSerialization dataWithJSONObject:state options:kNilOptions error:&error];
    if (error != nil) {
      reject(kErrorUnableToLoad, [NSString imgly_string:@"Invalid serialization." withError:error], error);
      return;
    }
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.licenseError != nil) {
      reject(kErrorUnableToUnlock, [NSString imgly_string:@"Unable to unlock with license." withError:self.licenseError], self.licenseError);
      return;
    }

    PESDKAssetCatalog *assetCatalog = PESDKAssetCatalog.defaultItems;
    PESDKConfiguration *configuration = [[PESDKConfiguration alloc] initWithBuilder:^(PESDKConfigurationBuilder * _Nonnull builder) {
      builder.assetCatalog = assetCatalog;
      [builder configureFromDictionary:dictionary error:&error];
    }];
    if (error != nil) {
      RCTLogError(@"Error while decoding configuration: %@", error);
      reject(kErrorUnableToLoad, [NSString imgly_string:@"Unable to load configuration." withError:error], error);
      return;
    }

    // Set default values if necessary
    id valueExportType = [NSDictionary imgly_dictionary:dictionary valueForKeyPath:@"export.type" default:kExportTypeFileURL];
    id valueExportFile = [NSDictionary imgly_dictionary:dictionary valueForKeyPath:@"export.filename" default:[NSString stringWithFormat:@"imgly-export/%@", [[NSUUID UUID] UUIDString]]];
    id valueSerializationEnabled = [NSDictionary imgly_dictionary:dictionary valueForKeyPath:@"export.serialization.enabled" default:@(NO)];
    id valueSerializationType = [NSDictionary imgly_dictionary:dictionary valueForKeyPath:@"export.serialization.exportType" default:kExportTypeFileURL];
    id valueSerializationFile = [NSDictionary imgly_dictionary:dictionary valueForKeyPath:@"export.serialization.filename" default:valueExportFile];
    id valueSerializationEmbedImage = [NSDictionary imgly_dictionary:dictionary valueForKeyPath:@"export.serialization.embedSourceImage" default:@(NO)];

    NSString *exportType = [RCTConvert NSString:valueExportType];
    NSURL *exportFile = [RCTConvert IMGLYExportFileURL:valueExportFile withExpectedUTI:uti(configuration)];
    BOOL serializationEnabled = [RCTConvert BOOL:valueSerializationEnabled];
    NSString *serializationType = [RCTConvert NSString:valueSerializationType];
    NSURL *serializationFile = [RCTConvert IMGLYExportFileURL:valueSerializationFile withExpectedUTI:kUTTypeJSON];
    BOOL serializationEmbedImage = [RCTConvert BOOL:valueSerializationEmbedImage];

    // Make sure that the export settings are valid
    if ((exportType == nil) ||
        (exportFile == nil && [exportType isEqualToString:kExportTypeFileURL]) ||
        (serializationFile == nil && [serializationType isEqualToString:kExportTypeFileURL]))
    {
      RCTLogError(@"Invalid export configuration");
      reject(kErrorUnableToLoad, @"Invalid export configuration", nil);
      return;
    }

    // Update configuration
    NSMutableDictionary *updatedDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionary];
    [updatedDictionary setValue:exportFile.absoluteString forKeyPath:@"export.filename"];
    configuration = [[PESDKConfiguration alloc] initWithBuilder:^(PESDKConfigurationBuilder * _Nonnull builder) {
      builder.assetCatalog = assetCatalog;
      [builder configureFromDictionary:updatedDictionary error:&error];
    }];
    if (error != nil) {
      RCTLogError(@"Error while updating configuration: %@", error);
      reject(kErrorUnableToLoad, [NSString imgly_string:@"Unable to update configuration." withError:error], error);
      return;
    }

    PESDKMediaEditViewController *viewController = mediaEditViewController(configuration, serializationData);
    if (viewController == nil) {
      return;
    }

    self.exportType = exportType;
    self.exportFile = exportFile;
    self.serializationEnabled = serializationEnabled;
    self.serializationType = serializationType;
    self.serializationFile = serializationFile;
    self.serializationEmbedImage = serializationEmbedImage;
    self.resolve = resolve;
    self.reject = reject;
    self.mediaEditViewController = viewController;

    UIViewController *currentViewController = RCTPresentedViewController();
    [currentViewController presentViewController:self.mediaEditViewController animated:YES completion:NULL];
  });
}

- (void)dismiss:(nonnull PESDKMediaEditViewController *)mediaEditViewController animated:(BOOL)animated
{
  if (mediaEditViewController != self.mediaEditViewController) {
    RCTLogError(@"Unregistered %@", NSStringFromClass(mediaEditViewController.class));
  }

  self.exportType = nil;
  self.exportFile = nil;
  self.serializationEnabled = NO;
  self.serializationType = nil;
  self.serializationFile = nil;
  self.serializationEmbedImage = NO;
  self.resolve = nil;
  self.reject = nil;
  self.mediaEditViewController = nil;

  dispatch_async(dispatch_get_main_queue(), ^{
    [mediaEditViewController.presentingViewController dismissViewControllerAnimated:animated completion:nil];
  });
}

- (void)handleLicenseError:(nullable NSError *)error
{
  self.licenseError = nil;
  if (error != nil) {
    if ([error.domain isEqualToString:@"ImglyKit.IMGLY.Error"]) {
      switch (error.code) {
        case 3:
          RCTLogWarn(@"%@: %@", NSStringFromClass(self.class), error.localizedDescription);
          break;
        default:
          self.licenseError = error;
          RCTLogError(@"%@: %@", NSStringFromClass(self.class), error.localizedDescription);
          break;
      }
    } else {
      self.licenseError = error;
      RCTLogError(@"Error while unlocking with license: %@", error);
    }
  }
}

- (void)unlockWithLicenseURL:(nonnull NSURL *)url {}

- (void)unlockWithLicenseString:(nonnull NSString *)string {}

- (void)unlockWithLicenseObject:(nonnull NSDictionary *)dictionary {}

- (void)unlockWithLicense:(nonnull id)json
{
  NSString *string = nil;
  NSURL *url = nil;
  BOOL isString = [json isKindOfClass:[NSString class]];
  if (isString) {
    string = json;
    @try { // NSURL has a history of crashing with bad input, so let's be safe
      url = [NSURL URLWithString:string];
    }
    @catch (__unused NSException *e) {}
  }

  // If the user specifies a file URL we do not use the converter and use the URL without any checks
  if (url == nil || !url.isFileURL) {
    // `RCTConvert` changed the conversion for json to URL and it throws now an error if it is not a string
    if (isString) {
      url = [RCTConvert NSURL:json];
      // Test if the resulting URL is an existing local file otherwise we try to read the license from a string or a dictionary
      if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        url = nil;
      }
    }
  }

  if (url != nil) {
    [self unlockWithLicenseURL:url];
  }
  else if (string != nil) {
    [self unlockWithLicenseString:string];
  }
  else if ([json isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictionary = json;
    [self unlockWithLicenseObject:dictionary];
  }
  else if (json) {
    RCTLogConvertError(json, @"a valid license format");
  }
}

@end

@implementation NSString (IMGLYStringWithError)

+ (nonnull NSString *)imgly_string:(nonnull NSString *)message withError:(nullable NSError *)error
{
  NSString *description = error.localizedDescription;
  if (description != nil) {
    return [NSString stringWithFormat:@"%@ %@", message, description];
  } else {
    return message;
  }
}

@end

@implementation NSData (IMGLYCreateDirectoryOnWrite)

- (BOOL)imgly_writeToURL:(nonnull NSURL *)fileURL andCreateDirectoryIfNecessary:(BOOL)createDirectory error:(NSError *_Nullable*_Nullable)error
{
  if (createDirectory) {
    if (![[NSFileManager defaultManager] createDirectoryAtURL:fileURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) {
      return NO;
    }
  }
  return [self writeToURL:fileURL options:NSDataWritingAtomic error:error];
}

@end

@implementation RCTConvert (IMGLYExportURLs)

+ (nullable IMGLYExportURL *)IMGLYExportURL:(nullable id)json
{
  // This code is identical to the implementation of
  // `+ (NSURL *)NSURL:(id)json`
  // except that it creates a path to a temporary file instead of assuming a resource path as last resort.

  NSString *path = [self NSString:json];
  if (!path) {
    return nil;
  }

  @try { // NSURL has a history of crashing with bad input, so let's be safe

    NSURL *URL = [NSURL URLWithString:path];
    if (URL.scheme) { // Was a well-formed absolute URL
      return URL;
    }

    // Check if it has a scheme
    if ([path rangeOfString:@":"].location != NSNotFound) {
      NSMutableCharacterSet *urlAllowedCharacterSet = [NSMutableCharacterSet new];
      [urlAllowedCharacterSet formUnionWithCharacterSet:[NSCharacterSet URLUserAllowedCharacterSet]];
      [urlAllowedCharacterSet formUnionWithCharacterSet:[NSCharacterSet URLPasswordAllowedCharacterSet]];
      [urlAllowedCharacterSet formUnionWithCharacterSet:[NSCharacterSet URLHostAllowedCharacterSet]];
      [urlAllowedCharacterSet formUnionWithCharacterSet:[NSCharacterSet URLPathAllowedCharacterSet]];
      [urlAllowedCharacterSet formUnionWithCharacterSet:[NSCharacterSet URLQueryAllowedCharacterSet]];
      [urlAllowedCharacterSet formUnionWithCharacterSet:[NSCharacterSet URLFragmentAllowedCharacterSet]];
      path = [path stringByAddingPercentEncodingWithAllowedCharacters:urlAllowedCharacterSet];
      URL = [NSURL URLWithString:path];
      if (URL) {
        return URL;
      }
    }

    // Assume that it's a local path
    path = path.stringByRemovingPercentEncoding;
    if ([path hasPrefix:@"~"]) {
      // Path is inside user directory
      path = path.stringByExpandingTildeInPath;
    } else if (!path.absolutePath) {
      // Create a path to a temporary file
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:path];
    }
    if (!(URL = [NSURL fileURLWithPath:path isDirectory:NO])) {
      RCTLogConvertError(json, @"a valid URL");
    }
    return URL;
  }
  @catch (__unused NSException *e) {
    RCTLogConvertError(json, @"a valid URL");
    return nil;
  }
}

+ (nullable IMGLYExportFileURL *)IMGLYExportFileURL:(nullable id)json withExpectedUTI:(nonnull CFStringRef)expectedUTI
{
  // This code is similar to the implementation of
  // `+ (RCTFileURL *)RCTFileURL:(id)json`.

  NSURL *fileURL = [self IMGLYExportURL:json];
  if (!fileURL.fileURL) {
    RCTLogError(@"URI must be a local file, '%@' isn't.", fileURL);
    return nil;
  }

  // Append correct file extension if necessary
  NSString *fileUTI = CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(fileURL.pathExtension.lowercaseString), nil));
  if (fileUTI == nil || !UTTypeEqual((__bridge CFStringRef)(fileUTI), expectedUTI)) {
    NSString *extension = CFBridgingRelease(UTTypeCopyPreferredTagWithClass(expectedUTI, kUTTagClassFilenameExtension));
    if (extension != nil) {
      fileURL = [fileURL URLByAppendingPathExtension:extension];
    }
  }

  BOOL isDirectory = false;
  if ([[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDirectory]) {
    if (isDirectory) {
      RCTLogError(@"File '%@' must not be a directory.", fileURL);
    } else {
      RCTLogWarn(@"File '%@' will be overwritten on export.", fileURL);
    }
  }
  return fileURL;
}

@end

@implementation NSDictionary (IMGLYDefaultValueForKeyPath)

- (nullable id)imgly_valueForKeyPath:(nonnull NSString *)keyPath default:(nullable id)defaultValue
{
  id value = [self valueForKeyPath:keyPath];

  if (value == nil || value == [NSNull null]) {
    return defaultValue;
  } else {
    return value;
  }
}

+ (nullable id)imgly_dictionary:(nullable NSDictionary *)dictionary valueForKeyPath:(nonnull NSString *)keyPath default:(nullable id)defaultValue
{
  if (dictionary == nil) {
    return defaultValue;
  }
  return [dictionary imgly_valueForKeyPath:keyPath default:defaultValue];
}

@end
