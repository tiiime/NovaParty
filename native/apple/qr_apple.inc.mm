#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <TargetConditionals.h>
static NSString *qrPNG(NSString *value){
 CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];[filter setValue:[value dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];[filter setValue:@"M" forKey:@"inputCorrectionLevel"];
 CIImage *code=filter.outputImage;if(!code)return @"";CGRect bounds=CGRectInset(code.extent,-4,-4);
 CIImage *white=[[CIImage imageWithColor:[CIColor colorWithRed:1 green:1 blue:1]]imageByCroppingToRect:bounds];
 CIImage *image=[[code imageByCompositingOverImage:white]imageByApplyingTransform:CGAffineTransformMakeScale(8,8)];
 CIContext *context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];CGImageRef cg=[context createCGImage:image fromRect:image.extent];if(!cg)return @"";
 NSMutableData *data=[NSMutableData new];CGImageDestinationRef out=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.png"),1,nullptr);if(out){CGImageDestinationAddImage(out,cg,nullptr);CGImageDestinationFinalize(out);CFRelease(out);}CGImageRelease(cg);return [data base64EncodedStringWithOptions:0];
}
static NSString *qrDecode(NSString *encoded){NSData *bytes=[[NSData alloc]initWithBase64EncodedString:encoded options:0];CIImage *image=[CIImage imageWithData:bytes];if(!image||image.extent.size.width*image.extent.size.height>16000000)return @"";CIDetector *detector=[CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];for(CIQRCodeFeature *feature in [detector featuresInImage:image])if(feature.messageString)return feature.messageString;return @"";}
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@interface NVQRScanner : UIViewController<AVCaptureMetadataOutputObjectsDelegate>
@property(nonatomic,copy)void(^completion)(NSString *,NSString *);
@property(nonatomic,strong)AVCaptureSession *capture;
@property(nonatomic,strong)AVCaptureVideoPreviewLayer *preview;
@property(nonatomic,copy)NSString *heading;
@property(nonatomic,copy)NSString *closeText;
@property(nonatomic)BOOL finished;
-(void)finish:(NSString*)type value:(NSString*)value;
-(void)stop;
@end
@implementation NVQRScanner
-(void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
 UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(24,55,320,80)];label.text=self.heading;label.textColor=UIColor.whiteColor;label.font=[UIFont systemFontOfSize:24];label.numberOfLines=2;[self.view addSubview:label];
 UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.frame=CGRectMake(24,145,160,52);[button setTitle:self.closeText forState:UIControlStateNormal];button.backgroundColor=UIColor.whiteColor;button.layer.cornerRadius=16;[button addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:button];
}
-(void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];AVAuthorizationStatus status=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];if(status==AVAuthorizationStatusNotDetermined){[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL allowed){dispatch_async(dispatch_get_main_queue(),^{if(!self.finished){if(allowed)[self setupCamera];else[self finish:@"qr_error" value:@"camera_permission_denied"];}});}];}else if(status==AVAuthorizationStatusAuthorized)[self setupCamera];else[self finish:@"qr_error" value:@"camera_permission_denied"];}
-(void)setupCamera{if(self.finished||self.capture)return;AVCaptureDevice *device=[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];if(!device){[self finish:@"qr_error" value:@"camera_unavailable"];return;}NSError *error=nil;AVCaptureDeviceInput *input=[AVCaptureDeviceInput deviceInputWithDevice:device error:&error];if(!input){[self finish:@"qr_error" value:@"camera_unavailable"];return;}
 AVCaptureSession *session=[AVCaptureSession new];AVCaptureMetadataOutput *output=[AVCaptureMetadataOutput new];if(![session canAddInput:input]||![session canAddOutput:output]){[self finish:@"qr_error" value:@"camera_unavailable"];return;}[session addInput:input];[session addOutput:output];[output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];output.metadataObjectTypes=@[AVMetadataObjectTypeQRCode];self.capture=session;
 self.preview=[AVCaptureVideoPreviewLayer layerWithSession:session];self.preview.videoGravity=AVLayerVideoGravityResizeAspectFill;self.preview.frame=self.view.bounds;[self.view.layer insertSublayer:self.preview atIndex:0];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session startRunning];});}
-(void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];self.preview.frame=self.view.bounds;}
-(void)captureOutput:(AVCaptureOutput*)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject*>*)objects fromConnection:(AVCaptureConnection*)connection{for(AVMetadataMachineReadableCodeObject *object in objects)if([object.type isEqual:AVMetadataObjectTypeQRCode]&&object.stringValue){[self finish:@"qr_result" value:object.stringValue];return;}}
-(void)cancel{[self finish:@"qr_canceled" value:@""];}
-(void)stop{self.completion=nil;[self finish:@"qr_canceled" value:@""];}
-(void)finish:(NSString*)type value:(NSString*)value{if(self.finished)return;self.finished=YES;AVCaptureSession *session=self.capture;self.capture=nil;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session stopRunning];});if(self.completion)self.completion(type,value);self.completion=nil;[self dismissViewControllerAnimated:YES completion:nil];}
-(void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(!self.finished)[self finish:@"qr_canceled" value:@""];}
@end
static UIViewController *qrPresenter(){UIWindow *window=nil;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive)for(UIWindow *candidate in ((UIWindowScene*)scene).windows)if(candidate.isKeyWindow)window=candidate;UIViewController *vc=window.rootViewController;while(vc.presentedViewController)vc=vc.presentedViewController;return vc;}
#endif
