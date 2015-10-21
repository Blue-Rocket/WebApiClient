//
//  WebApiClientDigestUtils.c
//  WebApiClient
//
//  Created by Matt on 22/10/15.
//  Copyright © 2015 Blue Rocket, Inc. Distributable under the terms of the Apache License, Version 2.0.
//

#include "WebApiClientDigestUtils.h"

#include <CommonCrypto/CommonDigest.h>

// In bytes
#define FileHashDefaultChunkSizeForReadingData 4096

CFDataRef WebApiClientMD5DigestCreateWithData(CFDataRef data) {
	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(CFDataGetBytePtr(data), (CC_LONG)CFDataGetLength(data), result);
	return CFDataCreate(kCFAllocatorDefault, result, CC_MD5_DIGEST_LENGTH);
}

CFDataRef WebApiClientMD5DigestCreateWithFilePath(CFStringRef filePath, size_t bufferSize) {
	
	// Declare needed variables
	CFDataRef result = NULL;
	CFReadStreamRef readStream = NULL;
	
	// Get the file URL
	CFURLRef fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)filePath, kCFURLPOSIXPathStyle, (Boolean)false);
	if ( fileURL ) {
		// Create and open the read stream
		readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, fileURL);
		if ( readStream ) {
			Boolean didSucceed = CFReadStreamOpen(readStream);
			if ( didSucceed ) {
				// Initialize the hash object
				CC_MD5_CTX hashObject;
				CC_MD5_Init(&hashObject);
				
				// Make sure chunkSizeForReadingData is valid
				if ( bufferSize < 1 ) {
					bufferSize = FileHashDefaultChunkSizeForReadingData;
				}
				
				// Feed the data to the hash object
				bool hasMoreData = true;
				while ( hasMoreData ) {
					uint8_t buffer[bufferSize];
					CFIndex readBytesCount = CFReadStreamRead(readStream, (UInt8 *)buffer, (CFIndex)sizeof(buffer));
					if ( readBytesCount == -1 ) break;
					if ( readBytesCount == 0 ) {
						hasMoreData = false;
						continue;
					}
					CC_MD5_Update(&hashObject, (const void *)buffer, (CC_LONG)readBytesCount);
				}
				
				// Check if the read operation succeeded
				didSucceed = !hasMoreData;
				
				// Compute the hash digest
				unsigned char digest[CC_MD5_DIGEST_LENGTH];
				CC_MD5_Final(digest, &hashObject);
				
				// Abort if the read operation failed
				if ( didSucceed ) {
					result = CFDataCreate(kCFAllocatorDefault, digest, CC_MD5_DIGEST_LENGTH);
				}
			}
		}
	}
	
	if ( readStream ) {
		CFReadStreamClose(readStream);
		CFRelease(readStream);
	}
	if ( fileURL ) {
		CFRelease(fileURL);
	}
	return result;
}

CFStringRef WebApiClientHexEncodedStringCreateWithData(CFDataRef data) {
	CFStringRef result = NULL;
	if ( data ) {
		const CFIndex len = CFDataGetLength(data);
		if ( len > 0 ) {
			char hash[2 * CFDataGetLength(data) + 1];
			const UInt8 * bytes = CFDataGetBytePtr(data);
			for ( CFIndex i = 0; i < len; ++i ) {
				snprintf(hash + (2 * i), 3, "%02x", (int)(bytes[i]));
			}
			result = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)hash, kCFStringEncodingUTF8);
		}
	}
	return result;
}
