

#import "AVExportHandler.h"

@implementation AVExportHandler {
    
    CGSize sizeRef;
    NSMutableArray *instructionsArray;
    
}

- (void)exportMixComposition:(AVMutableComposition *)mixComposition completion:(void (^)(NSURL *url, BOOL success))onCompletion{
    
    NSURL *randomFinalVideoFileURL = [self getRandomVideoFileURL];
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPresetHighestQuality];
    exportSession.outputFileType=AVFileTypeQuickTimeMovie;
    exportSession.outputURL = randomFinalVideoFileURL;
    
    CMTimeValue val = mixComposition.duration.value;
    CMTime start = CMTimeMake(0, 1);
    CMTime duration = CMTimeMake(val, 1);
    CMTimeRange range = CMTimeRangeMake(start, duration);
    exportSession.timeRange = range;
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        switch ([exportSession status]) {
            case AVAssetExportSessionStatusFailed:
            {
                NSLog(@"Export failed: %@ %@", [[exportSession error] localizedDescription],[[exportSession error]debugDescription]);
                onCompletion(nil,NO);
            }
            case AVAssetExportSessionStatusCancelled:
            {
                NSLog(@"Export canceled");
                onCompletion(nil,NO);
                break;
            }
            case AVAssetExportSessionStatusCompleted:
            {
                NSLog(@"Export complete!");
                onCompletion(exportSession.outputURL, YES);
            }
            default:
            {
                NSLog(@"default");
            }
        }
    }];
    
}

- (NSURL *)getRandomVideoFileURL{
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *myPathDocs =  [documentsDirectory stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"mergeVideo-%d.mp4",arc4random() % 1000]];
    NSURL *randomUrl = [NSURL fileURLWithPath:myPathDocs];
    
    return randomUrl;
    
}


- (void)mergeVideosFrom:(NSArray <AVAsset *> *)videosArray completion:(void(^)(AVMutableComposition *composition, NSError *error))onCompletion {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        AVMutableComposition *mixComposition = [AVMutableComposition composition];
        
        AVMutableCompositionTrack *videoCompositionTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        
        AVMutableCompositionTrack *audioCompositionTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        
        CGSize size = CGSizeZero;
        CMTime time = kCMTimeZero;
        
        NSMutableArray *instructions = [NSMutableArray new];
        
        for(AVAsset *asset in videosArray.copy)
        {
            AVAssetTrack *videoAssetTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
            
            NSError *videoError;
            [videoCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAssetTrack.timeRange.duration)
                                           ofTrack:videoAssetTrack
                                            atTime:time
                                             error:&videoError];
            
            videoCompositionTrack.preferredTransform = videoAssetTrack.preferredTransform;
            if (videoError) {
                NSLog(@"Error - %@", videoError.debugDescription);
                dispatch_async(dispatch_get_main_queue(), ^{
                    onCompletion(nil,videoError);
                });
                
            }
            
            AVAssetTrack *audioAssetTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
            
            NSError *audioError;
            [audioCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAssetTrack.timeRange.duration)
                                           ofTrack:audioAssetTrack
                                            atTime:time
                                             error:&audioError];
            if (audioError) {
                NSLog(@"Error - %@", audioError.debugDescription);
                dispatch_async(dispatch_get_main_queue(), ^{
                    onCompletion(nil,videoError);
                });
                
            }
            AVMutableVideoCompositionInstruction *videoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
            videoCompositionInstruction.timeRange = CMTimeRangeMake(time, videoAssetTrack.timeRange.duration);
            videoCompositionInstruction.layerInstructions = @[[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoCompositionTrack]];
            [instructions addObject:videoCompositionInstruction];
            
            time = CMTimeAdd(time, videoAssetTrack.timeRange.duration);
            
            if (CGSizeEqualToSize(size, CGSizeZero)) {
                size = videoAssetTrack.naturalSize;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            sizeRef = size;
            instructionsArray = instructions;
            onCompletion(mixComposition,nil);
            
        });
    });
}

- (void)playerItemFromVideosArray:(NSArray <AVAsset *> *)videosArray completion:(void(^)(AVPlayerItem *playerItem, NSError *error))completion {
    
    __block AVMutableComposition *mixComposition;
    __block AVMutableVideoComposition *mutableVideoComposition;
    
    [self mergeVideosFrom:videosArray.copy completion:^(AVMutableComposition *composition, NSError *error) {
        
        if (!error) {
            mixComposition = composition;
            mutableVideoComposition = [AVMutableVideoComposition videoComposition];
            mutableVideoComposition.instructions = instructionsArray;
            mutableVideoComposition.frameDuration = CMTimeMake(1, 30);
            mutableVideoComposition.renderSize = sizeRef;
            
            AVPlayerItem *pi = [AVPlayerItem playerItemWithAsset:mixComposition];
            pi.videoComposition = mutableVideoComposition;
            completion(pi,nil);
        }
        else {
            completion(nil,error);
        }
    }];
}


@end
