// Copyright 2023-2025 Wang Bin. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define USE_TEXCACHE 0

#import "FvpPlugin.h"
#include "mdk/RenderAPI.h"
#include "mdk/Player.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#include <atomic>
#include <functional>
#include <mutex>
#include <unordered_map>
#include <iostream>

using namespace mdk;
using namespace std;

@interface MetalTexture : NSObject<FlutterTexture>
@end

@implementation MetalTexture {
    @public
    id<MTLDevice> device;
    id<MTLCommandQueue> cmdQueue;
    id<MTLTexture> texture;
    CVPixelBufferRef pixbuf;
    id<MTLTexture> fltex;
    CVMetalTextureCacheRef texCache;
    CVMetalTextureCacheRef pipTextureCache;
    CVPixelBufferPoolRef pipPixelBufferPool;
    mutex mtx; // ensure whole frame render pass commands are recorded before blitting
}

- (instancetype)initWithWidth:(int)width height:(int)height
{
    self = [super init];
    device = MTLCreateSystemDefaultDevice();
    cmdQueue = [device newCommandQueue];
    auto td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    texture = [device newTextureWithDescriptor:td];
    //assert(!texture.iosurface); // CVPixelBufferCreateWithIOSurface(fltex.iosurface)
    auto attr = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attr, kCVPixelBufferMetalCompatibilityKey, kCFBooleanTrue);
    auto iosurface_props = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attr, kCVPixelBufferIOSurfacePropertiesKey, iosurface_props); // optional?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attr, &pixbuf);
    CFRelease(attr);
    texCache = {};
    pipTextureCache = {};
    pipPixelBufferPool = {};
    CVMetalTextureCacheCreate(nullptr, nullptr, device, nullptr, &pipTextureCache);
    NSDictionary* pipBufferAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferWidthKey: @(width),
        (NSString*)kCVPixelBufferHeightKey: @(height),
        (NSString*)kCVPixelBufferMetalCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVPixelBufferPoolCreate(
        kCFAllocatorDefault,
        nullptr,
        (__bridge CFDictionaryRef)pipBufferAttributes,
        &pipPixelBufferPool
    );
#if (USE_TEXCACHE + 0)
    CVMetalTextureCacheCreate(nullptr, nullptr, device, nullptr, &texCache);
    CVMetalTextureRef cvtex;
    CVMetalTextureCacheCreateTextureFromImage(nil, texCache, pixbuf, nil, MTLPixelFormatBGRA8Unorm, width, height, 0, &cvtex);
    fltex = CVMetalTextureGetTexture(cvtex);
    CFRelease(cvtex);
#else
    auto iosurface = CVPixelBufferGetIOSurface(pixbuf);
    td.usage = MTLTextureUsageShaderRead; // Unknown?
// macos: failed assertion `Texture Descriptor Validation IOSurface textures must use MTLStorageModeManaged or MTLStorageModeShared'
// ios: failed assertion `Texture Descriptor Validation IOSurface textures must use MTLStorageModeShared
    fltex = [device newTextureWithDescriptor:td iosurface:iosurface plane:0];
#endif
    return self;
}

- (void)dealloc {
    CVPixelBufferRelease(pixbuf);
    if (texCache)
        CFRelease(texCache);
    if (pipTextureCache)
        CFRelease(pipTextureCache);
    if (pipPixelBufferPool)
        CFRelease(pipPixelBufferPool);
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    //return CVPixelBufferRetain(pixbuf);
    scoped_lock lock(mtx);
    auto cmdbuf = [cmdQueue commandBuffer];
    auto blit = [cmdbuf blitCommandEncoder];
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(texture.width, texture.height, texture.depth)
        toTexture:fltex destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)]; // macos 10.15
    [blit endEncoding];
	[cmdbuf commit];
    return CVPixelBufferRetain(pixbuf);
}

- (void)copyPixelBufferForPictureInPictureWithCompletion:
    (void (^)(CVPixelBufferRef _Nullable pixelBuffer))completion {
    if (!pipPixelBufferPool || !pipTextureCache) {
        completion(nil);
        return;
    }

    CVPixelBufferRef output = nullptr;
    if (CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pipPixelBufferPool,
            &output
        ) != kCVReturnSuccess || !output) {
        completion(nil);
        return;
    }

    CVMetalTextureRef cvTexture = nullptr;
    const auto status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        pipTextureCache,
        output,
        nullptr,
        MTLPixelFormatBGRA8Unorm,
        texture.width,
        texture.height,
        0,
        &cvTexture
    );
    if (status != kCVReturnSuccess || !cvTexture) {
        CVPixelBufferRelease(output);
        completion(nil);
        return;
    }

    id<MTLTexture> outputTexture = CVMetalTextureGetTexture(cvTexture);
    if (!outputTexture) {
        CFRelease(cvTexture);
        CVPixelBufferRelease(output);
        completion(nil);
        return;
    }

    id<MTLCommandBuffer> commandBuffer;
    {
        scoped_lock lock(mtx);
        commandBuffer = [cmdQueue commandBuffer];
        auto blit = [commandBuffer blitCommandEncoder];
        [blit copyFromTexture:texture
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(texture.width, texture.height, texture.depth)
                    toTexture:outputTexture
             destinationSlice:0
             destinationLevel:0
            destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blit endEncoding];
    }
    if (!commandBuffer) {
        CFRelease(cvTexture);
        CVPixelBufferRelease(output);
        completion(nil);
        return;
    }
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        @autoreleasepool {
            const BOOL succeeded =
                buffer.status == MTLCommandBufferStatusCompleted;
            completion(succeeded ? output : nil);
            CFRelease(cvTexture);
            CVPixelBufferRelease(output);
        }
    }];
    [commandBuffer commit];
}
@end


class TexturePlayer final: public Player
{
public:
    TexturePlayer(int64_t handle, int width, int height, NSObject<FlutterTextureRegistry>* texReg)
        : Player(reinterpret_cast<mdkPlayerAPI*>(handle))
    {
        mtex_ = [[MetalTexture alloc] initWithWidth:width height:height];
        texId_ = [texReg registerTexture:mtex_];
        MetalRenderAPI ra{};
        ra.device = (__bridge void*)mtex_->device;
        ra.cmdQueue = (__bridge void*)mtex_->cmdQueue;
// TODO: texture pool to avoid blitting
        ra.texture = (__bridge void*)mtex_->texture;
        setRenderAPI(&ra);
        setVideoSurfaceSize(width, height);

        setRenderCallback([this, texReg](void* opaque){
            {
                scoped_lock lock(mtex_->mtx);
                renderVideo();
            }
            [texReg textureFrameAvailable:texId_];
            function<void(MetalTexture*, int64_t)> callback;
            {
                scoped_lock lock(pipCallbackMutex_);
                callback = pipFrameCallback_;
            }
            if (callback)
                callback(mtex_, position());
        });
    }

    ~TexturePlayer() override {
        setRenderCallback(nullptr);
        setVideoSurfaceSize(-1, -1);
    }

    int64_t textureId() const { return texId_;}
    MetalTexture* texture() const { return mtex_; }
    void setPictureInPictureFrameCallback(
        function<void(MetalTexture*, int64_t)> callback
    ) {
        scoped_lock lock(pipCallbackMutex_);
        pipFrameCallback_ = std::move(callback);
    }
private:
    int64_t texId_ = 0;
    MetalTexture* mtex_ = nil;
    mutex pipCallbackMutex_;
    function<void(MetalTexture*, int64_t)> pipFrameCallback_;
};

#if !TARGET_OS_OSX
static CMSampleBufferRef _Nullable CreatePictureInPictureSampleBuffer(
    CVPixelBufferRef pixelBuffer,
    int64_t positionMs
) {
    CMVideoFormatDescriptionRef format = nullptr;
    if (CMVideoFormatDescriptionCreateForImageBuffer(
            kCFAllocatorDefault,
            pixelBuffer,
            &format
        ) != noErr || !format) {
        return nullptr;
    }

    CMSampleTimingInfo timing = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake(positionMs, 1000),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sampleBuffer = nullptr;
    const auto status = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        format,
        &timing,
        &sampleBuffer
    );
    CFRelease(format);
    if (status != noErr || !sampleBuffer)
        return nullptr;

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        true
    );
    if (attachments && CFArrayGetCount(attachments) > 0) {
        auto attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(
            attachments,
            0
        );
        CFDictionarySetValue(
            attachment,
            kCMSampleAttachmentKey_DisplayImmediately,
            kCFBooleanTrue
        );
    }
    return sampleBuffer;
}

static UIViewController* _Nullable TopViewController(
    UIViewController* _Nullable controller
) {
    if ([controller isKindOfClass:[UINavigationController class]]) {
        return TopViewController(
            ((UINavigationController*)controller).visibleViewController
        );
    }
    if ([controller isKindOfClass:[UITabBarController class]]) {
        return TopViewController(
            ((UITabBarController*)controller).selectedViewController
        );
    }
    if (controller.presentedViewController)
        return TopViewController(controller.presentedViewController);
    return controller;
}

static UIViewController* _Nullable PictureInPictureRootViewController() {
    UIWindow* window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;
            for (UIWindow* candidate in ((UIWindowScene*)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (window)
                break;
        }
    } else {
        window = UIApplication.sharedApplication.delegate.window;
    }
    return TopViewController(window.rootViewController);
}
#endif


@interface FvpPlugin ()
#if !TARGET_OS_OSX
    <AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate>
#endif
{
    unordered_map<int64_t, shared_ptr<TexturePlayer>> players;
#if !TARGET_OS_OSX
    shared_ptr<TexturePlayer> pictureInPicturePlayer;
    atomic_bool pictureInPictureFramePending;
    atomic_bool pictureInPictureFramesEnabled;
    atomic<int64_t> lastPictureInPicturePositionMs;
    atomic<uint64_t> pictureInPictureGeneration;
    int64_t pictureInPictureTextureId;
#endif
}
@property(readonly, strong, nonatomic) NSObject<FlutterTextureRegistry>* texRegistry;
#if !TARGET_OS_OSX
@property(strong, nonatomic) FlutterMethodChannel* pictureInPictureChannel;
@property(strong, nonatomic) AVSampleBufferDisplayLayer* pictureInPictureLayer API_AVAILABLE(ios(15.0));
@property(strong, nonatomic) AVPictureInPictureController* pictureInPictureController API_AVAILABLE(ios(15.0));
@property(strong, nonatomic) UIView* pictureInPictureHostView;
@property(copy, nonatomic) NSString* pictureInPictureId;
@property(copy, nonatomic) FlutterResult pendingPictureInPictureResult;
@property(assign, nonatomic) BOOL pictureInPictureStartRequested;
@property(assign, nonatomic) double pictureInPictureRate;
#endif
@end

@implementation FvpPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
#if TARGET_OS_OSX
    auto messenger = registrar.messenger;
#else
    auto messenger = [registrar messenger];
  // Allow audio playback when the Ring/Silent switch is set to silent
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
#endif
    FlutterMethodChannel* channel = [FlutterMethodChannel methodChannelWithName:@"fvp" binaryMessenger:messenger];
    FvpPlugin* instance = [[FvpPlugin alloc] initWithRegistrar:registrar];
#if TARGET_OS_OSX
#else
  [registrar addApplicationDelegate:instance];
#endif
    [registrar publish:instance];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    self = [super init];
#if TARGET_OS_OSX
    _texRegistry = registrar.textures;
#else
    _texRegistry = [registrar textures];
    pictureInPictureFramePending.store(false);
    pictureInPictureFramesEnabled.store(false);
    lastPictureInPicturePositionMs.store(-1);
    pictureInPictureGeneration.store(0);
    pictureInPictureTextureId = -1;
    _pictureInPictureRate = 1.0;
    _pictureInPictureChannel = [FlutterMethodChannel
        methodChannelWithName:@"mithka/fvp_picture_in_picture"
        binaryMessenger:[registrar messenger]
    ];
    __weak FvpPlugin* weakSelf = self;
    [_pictureInPictureChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        [weakSelf handlePictureInPictureMethodCall:call result:result];
    }];
#endif
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"CreateRT"]) {
        const auto handle = ((NSNumber*)call.arguments[@"player"]).longLongValue;
        const auto width = ((NSNumber*)call.arguments[@"width"]).intValue;
        const auto height = ((NSNumber*)call.arguments[@"height"]).intValue;
        auto player = make_shared<TexturePlayer>(handle, width, height, _texRegistry);
        players[player->textureId()] = player;
        result(@(player->textureId()));
    } else if ([call.method isEqualToString:@"ReleaseRT"]) {
        const auto texId = ((NSNumber*)call.arguments[@"texture"]).longLongValue;
#if !TARGET_OS_OSX
        if (texId == pictureInPictureTextureId)
            [self stopPictureInPictureAndNotifyFlutter:NO];
#endif
        [_texRegistry unregisterTexture:texId];
        players.erase(texId);
        result(nil);
    } else if ([call.method isEqualToString:@"MixWithOthers"]) {
        [[maybe_unused]] const auto value = ((NSNumber*)call.arguments[@"value"]).boolValue;
#if TARGET_OS_OSX
#else
        if (value) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        } else {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        }
#endif
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#if !TARGET_OS_OSX
- (void)handlePictureInPictureMethodCall:(FlutterMethodCall*)call
                                  result:(FlutterResult)result {
    if ([call.method isEqualToString:@"isSupported"]) {
        if (@available(iOS 15.0, *)) {
            result(@(AVPictureInPictureController.isPictureInPictureSupported));
        } else {
            result(@NO);
        }
    } else if ([call.method isEqualToString:@"prepare"]) {
        result(@([self preparePictureInPicture:call.arguments]));
    } else if ([call.method isEqualToString:@"startPrepared"]) {
        [self startPreparedPictureInPicture:call.arguments result:result];
    } else if ([call.method isEqualToString:@"update"]) {
        [self updatePictureInPicture:call.arguments];
        result(nil);
    } else if ([call.method isEqualToString:@"cancel"]) {
        NSString* requestedId = [call.arguments isKindOfClass:[NSDictionary class]]
            ? call.arguments[@"id"]
            : nil;
        if (!requestedId || [requestedId isEqualToString:self.pictureInPictureId])
            [self stopPictureInPictureAndNotifyFlutter:NO];
        result(nil);
    } else if ([call.method isEqualToString:@"stop"]) {
        [self stopPictureInPictureAndNotifyFlutter:YES];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (BOOL)preparePictureInPicture:(id)arguments {
    if (@available(iOS 15.0, *)) {
        if (!AVPictureInPictureController.isPictureInPictureSupported)
            return NO;
        if (![arguments isKindOfClass:[NSDictionary class]])
            return NO;
        NSDictionary* args = arguments;
        NSString* sessionId = args[@"id"];
        NSNumber* playerId = args[@"playerId"];
        if (![sessionId isKindOfClass:[NSString class]] ||
            ![playerId isKindOfClass:[NSNumber class]]) {
            return NO;
        }

        const auto textureId = playerId.longLongValue;
        auto playerIterator = players.find(textureId);
        if (playerIterator == players.end()) {
            NSLog(@"Mithka FVP PiP prepare failed: player %lld not found", textureId);
            return NO;
        }

        const BOOL replacingSession = self.pictureInPictureId != nil &&
            ![self.pictureInPictureId isEqualToString:sessionId];
        [self stopPictureInPictureAndNotifyFlutter:replacingSession];
        const auto generation = pictureInPictureGeneration.fetch_add(1) + 1;
        pictureInPicturePlayer = playerIterator->second;
        pictureInPictureTextureId = textureId;
        self.pictureInPictureId = sessionId;
        self.pictureInPictureRate = [args[@"speed"] doubleValue] > 0.0
            ? [args[@"speed"] doubleValue]
            : 1.0;

        NSError* audioError = nil;
        AVAudioSession* audioSession = AVAudioSession.sharedInstance;
        [audioSession setCategory:AVAudioSessionCategoryPlayback
                             mode:AVAudioSessionModeMoviePlayback
                          options:0
                            error:&audioError];
        [audioSession setActive:YES error:&audioError];

        UIViewController* root = PictureInPictureRootViewController();
        if (!root) {
            [self stopPictureInPictureAndNotifyFlutter:NO];
            return NO;
        }

        UIView* hostView = [[UIView alloc] initWithFrame:root.view.bounds];
        hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        hostView.alpha = 0.01;
        hostView.userInteractionEnabled = NO;
        AVSampleBufferDisplayLayer* displayLayer = [AVSampleBufferDisplayLayer layer];
        displayLayer.frame = hostView.bounds;
        displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [hostView.layer addSublayer:displayLayer];
        [root.view addSubview:hostView];

        CMTimebaseRef timebase = nullptr;
        if (CMTimebaseCreateWithSourceClock(
                kCFAllocatorDefault,
                CMClockGetHostTimeClock(),
                &timebase
            ) == noErr && timebase) {
            CMTimebaseSetTime(
                timebase,
                CMTimeMake(pictureInPicturePlayer->position(), 1000)
            );
            CMTimebaseSetRate(
                timebase,
                pictureInPicturePlayer->state() == State::Playing
                    ? self.pictureInPictureRate
                    : 0.0
            );
            displayLayer.controlTimebase = timebase;
            CFRelease(timebase);
        }

        AVPictureInPictureControllerContentSource* source =
            [[AVPictureInPictureControllerContentSource alloc]
                initWithSampleBufferDisplayLayer:displayLayer
                playbackDelegate:self
            ];
        AVPictureInPictureController* controller =
            [[AVPictureInPictureController alloc] initWithContentSource:source];
        controller.delegate = self;
        controller.requiresLinearPlayback = NO;
        controller.canStartPictureInPictureAutomaticallyFromInline = YES;

        self.pictureInPictureHostView = hostView;
        self.pictureInPictureLayer = displayLayer;
        self.pictureInPictureController = controller;
        pictureInPictureFramePending.store(false);
        pictureInPictureFramesEnabled.store(false);
        lastPictureInPicturePositionMs.store(-1);

        __weak FvpPlugin* weakSelf = self;
        pictureInPicturePlayer->setPictureInPictureFrameCallback(
            [weakSelf, generation](MetalTexture* texture, int64_t positionMs) {
                FvpPlugin* strongSelf = weakSelf;
                if (!strongSelf)
                    return;
                [strongSelf enqueuePictureInPictureFrameFromTexture:texture
                                                          position:positionMs
                                                        generation:generation];
            }
        );
        [self enqueuePictureInPictureFrameFromTexture:pictureInPicturePlayer->texture()
                                             position:pictureInPicturePlayer->position()
                                           generation:generation];
        [self applyPictureInPictureArguments:args allowSeek:NO];
        NSLog(@"Mithka FVP PiP prepared active player %lld", textureId);
        return YES;
    }
    return NO;
}

- (void)enqueuePictureInPictureFrameFromTexture:(MetalTexture*)texture
                                        position:(int64_t)positionMs
                                      generation:(uint64_t)generation {
    if (generation != pictureInPictureGeneration.load())
        return;
    const auto previousPosition = lastPictureInPicturePositionMs.load();
    if (!pictureInPictureFramesEnabled.load() && previousPosition >= 0)
        return;
    if (previousPosition >= 0 && llabs(positionMs - previousPosition) < 33)
        return;
    if (pictureInPictureFramePending.exchange(true))
        return;
    lastPictureInPicturePositionMs.store(positionMs);

    __weak FvpPlugin* weakSelf = self;
    [texture copyPixelBufferForPictureInPictureWithCompletion:^(CVPixelBufferRef pixelBuffer) {
        FvpPlugin* strongSelf = weakSelf;
        if (!strongSelf ||
            generation != strongSelf->pictureInPictureGeneration.load()) {
            return;
        }
        if (!pixelBuffer) {
            strongSelf->pictureInPictureFramePending.store(false);
            return;
        }
        CMSampleBufferRef sampleBuffer = CreatePictureInPictureSampleBuffer(
            pixelBuffer,
            positionMs
        );
        if (!sampleBuffer) {
            strongSelf->pictureInPictureFramePending.store(false);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            FvpPlugin* mainSelf = weakSelf;
            if (mainSelf &&
                generation == mainSelf->pictureInPictureGeneration.load()) {
                if (@available(iOS 15.0, *)) {
                    AVSampleBufferDisplayLayer* layer = mainSelf.pictureInPictureLayer;
                    if (layer.status == AVQueuedSampleBufferRenderingStatusFailed)
                        [layer flush];
                    if (layer.readyForMoreMediaData)
                        [layer enqueueSampleBuffer:sampleBuffer];
                }
                mainSelf->pictureInPictureFramePending.store(false);
            }
            CFRelease(sampleBuffer);
        });
    }];
}

- (void)applyPictureInPictureArguments:(NSDictionary*)args
                              allowSeek:(BOOL)allowSeek {
    if (!pictureInPicturePlayer)
        return;
    NSNumber* muted = args[@"muted"];
    if ([muted isKindOfClass:[NSNumber class]])
        pictureInPicturePlayer->setMute(muted.boolValue);
    NSNumber* speed = args[@"speed"];
    if ([speed isKindOfClass:[NSNumber class]] && speed.doubleValue > 0.0) {
        self.pictureInPictureRate = speed.doubleValue;
        pictureInPicturePlayer->setPlaybackRate(speed.floatValue);
    }
    NSNumber* playing = args[@"playing"];
    if ([playing isKindOfClass:[NSNumber class]]) {
        pictureInPicturePlayer->set(
            playing.boolValue ? State::Playing : State::Paused
        );
    }
    NSNumber* position = args[@"positionMs"];
    if (allowSeek && [position isKindOfClass:[NSNumber class]]) {
        const auto requested = position.longLongValue;
        if (llabs(pictureInPicturePlayer->position() - requested) > 2500)
            pictureInPicturePlayer->seek(requested, SeekFlag::FromStart);
    }

    if (@available(iOS 15.0, *)) {
        AVSampleBufferDisplayLayer* layer = self.pictureInPictureLayer;
        if (layer.controlTimebase) {
            CMTimebaseSetTime(
                layer.controlTimebase,
                CMTimeMake(pictureInPicturePlayer->position(), 1000)
            );
            CMTimebaseSetRate(
                layer.controlTimebase,
                pictureInPicturePlayer->state() == State::Playing
                    ? self.pictureInPictureRate
                    : 0.0
            );
        }
        [self.pictureInPictureController invalidatePlaybackState];
    }
}

- (void)startPreparedPictureInPicture:(id)arguments
                                result:(FlutterResult)result {
    if (@available(iOS 15.0, *)) {
        if (![arguments isKindOfClass:[NSDictionary class]] ||
            !self.pictureInPictureController ||
            !pictureInPicturePlayer) {
            result(@NO);
            return;
        }
        if (self.pendingPictureInPictureResult) {
            result(@NO);
            return;
        }
        NSDictionary* args = arguments;
        if (![args[@"id"] isEqualToString:self.pictureInPictureId]) {
            result(@NO);
            return;
        }
        [self applyPictureInPictureArguments:args allowSeek:YES];
        pictureInPictureFramesEnabled.store(true);
        self.pendingPictureInPictureResult = result;
        self.pictureInPictureStartRequested = NO;
        [self tryStartPreparedPictureInPictureWithAttempts:80];
        return;
    }
    result(@NO);
}

- (void)tryStartPreparedPictureInPictureWithAttempts:(NSInteger)attempts {
    if (@available(iOS 15.0, *)) {
        if (!self.pendingPictureInPictureResult ||
            !self.pictureInPictureController) {
            return;
        }
        if (self.pictureInPictureController.isPictureInPicturePossible) {
            if (!self.pictureInPictureStartRequested) {
                self.pictureInPictureStartRequested = YES;
                NSLog(@"Mithka FVP PiP startPictureInPicture");
                [self.pictureInPictureController startPictureInPicture];
                __weak FvpPlugin* weakSelf = self;
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC),
                    dispatch_get_main_queue(),
                    ^{
                        FvpPlugin* strongSelf = weakSelf;
                        if (strongSelf.pendingPictureInPictureResult) {
                            strongSelf.pendingPictureInPictureResult(@NO);
                            strongSelf.pendingPictureInPictureResult = nil;
                            [strongSelf stopPictureInPictureAndNotifyFlutter:NO];
                        }
                    }
                );
            }
            return;
        }
        if (attempts <= 0) {
            NSLog(@"Mithka FVP PiP start timed out waiting for possible");
            self.pendingPictureInPictureResult(@NO);
            self.pendingPictureInPictureResult = nil;
            [self stopPictureInPictureAndNotifyFlutter:NO];
            return;
        }
        __weak FvpPlugin* weakSelf = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{
                [weakSelf tryStartPreparedPictureInPictureWithAttempts:attempts - 1];
            }
        );
    }
}

- (void)updatePictureInPicture:(id)arguments {
    if (![arguments isKindOfClass:[NSDictionary class]])
        return;
    NSDictionary* args = arguments;
    if (![args[@"id"] isEqualToString:self.pictureInPictureId])
        return;
    [self applyPictureInPictureArguments:args allowSeek:NO];
}

- (void)stopPictureInPictureAndNotifyFlutter:(BOOL)notifyFlutter {
    pictureInPictureGeneration.fetch_add(1);
    NSString* stoppedId = self.pictureInPictureId;
    if (pictureInPicturePlayer)
        pictureInPicturePlayer->setPictureInPictureFrameCallback(nullptr);
    pictureInPicturePlayer.reset();
    pictureInPictureTextureId = -1;
    pictureInPictureFramePending.store(false);
    pictureInPictureFramesEnabled.store(false);
    lastPictureInPicturePositionMs.store(-1);

    FlutterResult pendingResult = self.pendingPictureInPictureResult;
    self.pendingPictureInPictureResult = nil;
    if (pendingResult)
        pendingResult(@NO);

    if (@available(iOS 15.0, *)) {
        self.pictureInPictureController.delegate = nil;
        if (self.pictureInPictureController.isPictureInPictureActive)
            [self.pictureInPictureController stopPictureInPicture];
        [self.pictureInPictureLayer flushAndRemoveImage];
        self.pictureInPictureController = nil;
        self.pictureInPictureLayer = nil;
    }
    [self.pictureInPictureHostView removeFromSuperview];
    self.pictureInPictureHostView = nil;
    self.pictureInPictureId = nil;
    self.pictureInPictureStartRequested = NO;
    self.pictureInPictureRate = 1.0;

    if (notifyFlutter && stoppedId) {
        [self.pictureInPictureChannel invokeMethod:@"didStop"
                                        arguments:@{@"id": stoppedId}];
    }
}

- (void)pictureInPictureControllerDidStartPictureInPicture:
    (AVPictureInPictureController*)pictureInPictureController API_AVAILABLE(ios(15.0)) {
    FlutterResult result = self.pendingPictureInPictureResult;
    self.pendingPictureInPictureResult = nil;
    if (result)
        result(@YES);
}

- (void)pictureInPictureController:
            (AVPictureInPictureController*)pictureInPictureController
    failedToStartPictureInPictureWithError:(NSError*)error API_AVAILABLE(ios(15.0)) {
    NSLog(@"Mithka FVP PiP failed to start: %@", error.localizedDescription);
    FlutterResult result = self.pendingPictureInPictureResult;
    self.pendingPictureInPictureResult = nil;
    if (result)
        result(@NO);
    [self stopPictureInPictureAndNotifyFlutter:NO];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:
    (AVPictureInPictureController*)pictureInPictureController API_AVAILABLE(ios(15.0)) {
    [self stopPictureInPictureAndNotifyFlutter:YES];
}

- (void)pictureInPictureController:
            (AVPictureInPictureController*)pictureInPictureController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:
            (void (^)(BOOL restored))completionHandler API_AVAILABLE(ios(15.0)) {
    completionHandler(NO);
}

- (void)pictureInPictureController:(AVPictureInPictureController*)pictureInPictureController
                        setPlaying:(BOOL)playing API_AVAILABLE(ios(15.0)) {
    if (!pictureInPicturePlayer)
        return;
    pictureInPicturePlayer->set(playing ? State::Playing : State::Paused);
    AVSampleBufferDisplayLayer* layer = self.pictureInPictureLayer;
    if (layer.controlTimebase) {
        CMTimebaseSetTime(
            layer.controlTimebase,
            CMTimeMake(pictureInPicturePlayer->position(), 1000)
        );
        CMTimebaseSetRate(
            layer.controlTimebase,
            playing ? self.pictureInPictureRate : 0.0
        );
    }
    [pictureInPictureController invalidatePlaybackState];
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:
    (AVPictureInPictureController*)pictureInPictureController API_AVAILABLE(ios(15.0)) {
    if (!pictureInPicturePlayer)
        return kCMTimeRangeInvalid;
    const auto durationMs = pictureInPicturePlayer->mediaInfo().duration;
    if (durationMs <= 0)
        return CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity);
    return CMTimeRangeMake(kCMTimeZero, CMTimeMake(durationMs, 1000));
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:
    (AVPictureInPictureController*)pictureInPictureController API_AVAILABLE(ios(15.0)) {
    return !pictureInPicturePlayer ||
        pictureInPicturePlayer->state() != State::Playing;
}

- (void)pictureInPictureController:(AVPictureInPictureController*)pictureInPictureController
         didTransitionToRenderSize:(CMVideoDimensions)newRenderSize API_AVAILABLE(ios(15.0)) {
}

- (void)pictureInPictureController:(AVPictureInPictureController*)pictureInPictureController
                    skipByInterval:(CMTime)skipInterval
                 completionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(15.0)) {
    if (!pictureInPicturePlayer) {
        completionHandler();
        return;
    }
    const auto durationMs = pictureInPicturePlayer->mediaInfo().duration;
    auto targetMs = pictureInPicturePlayer->position() +
        (int64_t)llround(CMTimeGetSeconds(skipInterval) * 1000.0);
    targetMs = std::max<int64_t>(0, targetMs);
    if (durationMs > 0)
        targetMs = std::min<int64_t>(durationMs, targetMs);
    pictureInPicturePlayer->seek(targetMs, SeekFlag::FromStart);
    if (self.pictureInPictureLayer.controlTimebase) {
        CMTimebaseSetTime(
            self.pictureInPictureLayer.controlTimebase,
            CMTimeMake(targetMs, 1000)
        );
    }
    completionHandler();
}

- (BOOL)pictureInPictureControllerShouldProhibitBackgroundAudioPlayback:
    (AVPictureInPictureController*)pictureInPictureController API_AVAILABLE(ios(15.0)) {
    return NO;
}
#endif

// ios only, optional. called first in dealloc(texture registry is still alive). plugin instance must be registered via publish
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
#if !TARGET_OS_OSX
  [self stopPictureInPictureAndNotifyFlutter:NO];
#endif
  players.clear();
}

#if TARGET_OS_OSX
#else
- (void)applicationWillTerminate:(UIApplication *)application {
  [self stopPictureInPictureAndNotifyFlutter:NO];
  players.clear();
}
#endif
@end
