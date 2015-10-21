//
//  WebApiClientDigestUtilsTests.m
//  WebApiClient
//
//  Created by Matt on 22/10/15.
//  Copyright © 2015 Blue Rocket, Inc. All rights reserved.
//

#import "BaseTestingSupport.h"

#import "WebApiClientDigestUtils.h"

@interface WebApiClientDigestUtilsTests : BaseTestingSupport

@end

@implementation WebApiClientDigestUtilsTests

- (void)testMD5DigestData {
	const unsigned char input[4] = {4, 8, 12, 24};
	CFDataRef data = CFDataCreate(kCFAllocatorDefault, input, 4);
	CFDataRef digest = WebApiClientMD5DigestCreateWithData(data);

	UInt8 expected[16] = {0x62, 0x3e, 0xdc, 0xa4, 0x1c, 0x80, 0x71, 0xad, 0xa5, 0x35, 0x89, 0x50, 0x91, 0xac, 0xf2, 0xe5};
	assertThatInt(CFDataGetLength(digest), equalToInt(16));
	
	const UInt8 *bytes = CFDataGetBytePtr(digest);
	for ( CFIndex i = 0; i < 16; i++ ) {
		assertThatUnsignedInt(bytes[i], equalToUnsignedInt(expected[i]));
	}
	
	CFRelease(digest);
}

- (void)testMD5DigestFile {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	CFDataRef digest = WebApiClientMD5DigestCreateWithFilePath((__bridge CFStringRef)[fileURL path], 0);
	
	UInt8 expected[16] = {0x71, 0x66, 0x13, 0x5e, 0xb5, 0x96, 0xe0, 0x3a, 0xd3, 0x59, 0xf2, 0xdf, 0xb9, 0x1f, 0x5e, 0xd4};
	assertThatInt(CFDataGetLength(digest), equalToInt(16));
	
	const UInt8 *bytes = CFDataGetBytePtr(digest);
	for ( CFIndex i = 0; i < 16; i++ ) {
		assertThatUnsignedInt(bytes[i], equalToUnsignedInt(expected[i]));
	}
	
	CFRelease(digest);
}

- (void)testHexString {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	CFDataRef digest = WebApiClientMD5DigestCreateWithFilePath((__bridge CFStringRef)[fileURL path], 0);
	NSString *string = CFBridgingRelease(WebApiClientHexEncodedStringCreateWithData(digest));
	assertThat((NSString *)string, equalTo(@"7166135eb596e03ad359f2dfb91f5ed4"));
	CFRelease(digest);
}

@end
