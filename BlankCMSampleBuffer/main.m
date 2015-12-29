//
//  main.m
//  BlankCMSampleBuffer
//
//  Created by armen karamian on 12/24/15.
//  Copyright © 2015 armen karamian. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AVFoundation;

static void releaseNSData(void *o, void *block, size_t size);

int main(int argc, const char * argv[]) {
	@autoreleasepool
	{
	
		NSError *err;
		NSURL *outputURL = [NSURL fileURLWithPath:@"/Users/armen/Desktop/testAudioOutput.aiff"];
		AudioChannelLayout channelLayout;
		memset(&channelLayout, 0, sizeof(AudioChannelLayout));
		channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;

		NSDictionary *outputSettings =
		[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
		[NSNumber numberWithFloat:48000.0], AVSampleRateKey,
		[NSNumber numberWithInt:1], AVNumberOfChannelsKey,
		[NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)],
		AVChannelLayoutKey,
		[NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
		[NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
		[NSNumber numberWithBool:NO],AVLinearPCMIsFloatKey,
		[NSNumber numberWithBool:YES], AVLinearPCMIsBigEndianKey,
		nil];
		
			//create asbd and channel layout for output
		AudioStreamBasicDescription asbd = {};
		asbd.mBitsPerChannel = 16;
		asbd.mBytesPerFrame = 2;
		asbd.mSampleRate = 48000.0;
		asbd.mFormatID = kAudioFormatLinearPCM;
		asbd.mFramesPerPacket = 1;
		asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
		asbd.mChannelsPerFrame = 1;
		asbd.mBytesPerFrame = asbd.mChannelsPerFrame * 2;
		asbd.mBytesPerPacket = asbd.mFramesPerPacket * asbd.mBytesPerFrame;
		asbd.mReserved = 0;
		
		AudioChannelLayout audioChannelLayout = {
			.mChannelLayoutTag = kAudioChannelLayoutTag_Mono,
			.mChannelBitmap = 0,
			.mNumberChannelDescriptions = 0
		};
		CMAudioFormatDescriptionRef audioFormat;
		
		CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, sizeof(audioChannelLayout), &audioChannelLayout,
									   0, NULL, NULL, &audioFormat);


		


		
		dispatch_queue_t q = dispatch_queue_create("assetwriterQ", NULL);
		
		AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:outputURL
														 fileType:AVFileTypeAIFF
															error:&err];
		AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
																	   outputSettings:outputSettings];
		
		if([writer canAddInput:input])
		{
			NSLog(@"Adding input");
			[writer addInput:input];
			input.expectsMediaDataInRealTime = NO;
			
			
			if([writer startWriting])
			{
				NSLog(@"Writing");
				[writer startSessionAtSourceTime:kCMTimeZero];
				
				[input requestMediaDataWhenReadyOnQueue:q usingBlock:^{
					while (input.isReadyForMoreMediaData && writer.status == AVAssetWriterStatusWriting)
					{
							//create array of empty samples assuming 16 bit
						int sampleCount = 48000;
						UInt16 audiosamples[sampleCount];
						for (int i = 0; i < sampleCount; i++)
						{
							audiosamples[i] = 1;
						}
						unsigned long audioSampleSize = sizeof(audiosamples);
						
							//create NSData with audio samples audio data
						NSData *audioData = [[NSData alloc] initWithBytes:audiosamples length:audioSampleSize];
						
						CMBlockBufferCustomBlockSource blockSource =
						{
							.version       = kCMBlockBufferCustomBlockSourceVersion,
							.AllocateBlock = NULL,
							.FreeBlock     = &releaseNSData,
							.refCon        = (__bridge_retained void*) audioData,
						};
						
						CMBlockBufferRef audiosampleBlock;
						
						OSStatus stat = CMBlockBufferCreateWithMemoryBlock(NULL,
																		   (uint8_t*) audioData.bytes,
																		   audioData.length,
																		   NULL,
																		   &blockSource,
																		   0,
																		   audioData.length,
																		   0,
																		   &audiosampleBlock);
						
						if (stat != noErr)
						{
							NSLog(@"Block buffer error");
							exit(1);
						}
						
						if (CMBlockBufferIsEmpty(audiosampleBlock))
						{
							NSLog(@"Block Buffer is empty");
							exit(1);
						}
						
						CMSampleBufferRef audioSampleBuffer;
						CMItemCount audioSampleCount = 48000;
						CMTime startTime = CMTimeMake(1, 48000);
				
						stat = CMAudioSampleBufferCreateWithPacketDescriptions(kCFAllocatorDefault,
																		audiosampleBlock,
																		true,
																		NULL,
																		NULL,
																		audioFormat,
																		audioSampleCount,
																		startTime,
																		NULL,
																		&audioSampleBuffer);

						if (stat != noErr)
						{
							NSLog(@"Sample buffer error");
							exit(1);
						}
						
						CMItemCount nunmItems = CMSampleBufferGetNumSamples(audioSampleBuffer);
							
						if (audioSampleBuffer)
						{
							if (!CMSampleBufferDataIsReady(audioSampleBuffer))
							{
								NSLog(@"sample buffer is not ready");
								exit(1);
							}
							if (!CMSampleBufferIsValid(audioSampleBuffer))
							{
								NSLog(@"Audio sapmle buffer is not valid");
								exit(1);
							}
							stat = CMSampleBufferMakeDataReady(audioSampleBuffer);
							if (stat == noErr)
							{
								bool result = [input appendSampleBuffer:audioSampleBuffer];
								if (!result)
								{
									NSLog(@"%@",writer.error);
								}
								else
									NSLog(@"Writing complete");
							}
							CFRelease(audiosampleBlock);
							CMSampleBufferInvalidate(audioSampleBuffer);
							CFRelease(audioSampleBuffer);
						}
						[input markAsFinished];
						CMTime endTime = CMTimeMake(48000, 48000);
						
					}
					[writer finishWritingWithCompletionHandler:^{
						NSLog(@"Writing to file complete");
					}];
					
				}];
				dispatch_sync(q, ^{NSLog(@"Done");});
				
			}
			else
			{
				NSLog(@"Cannot write, destination file already exists?");
			}
			
		}
		else
		{
			NSLog(@"Cannot add input");
		}
		
	}
    return 0;
	
}

static void releaseNSData(void *o, void *block, size_t size)
{
	NSData *data = (__bridge_transfer NSData*) o;
	data = nil;
}
