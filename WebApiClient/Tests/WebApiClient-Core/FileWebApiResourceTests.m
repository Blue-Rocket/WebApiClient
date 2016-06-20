//
//  FileWebApiResourceTests.m
//  WebApiClient
//
//  Created by Matt on 22/10/15.
//  Copyright © 2015 Blue Rocket, Inc. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseTestingSupport.h"

#import "FileWebApiResource.h"

@interface FileWebApiResourceTests : BaseTestingSupport

@end

@implementation FileWebApiResourceTests

- (void)testBasicProperties {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	FileWebApiResource *rsrc = [[FileWebApiResource alloc] initWithURL:fileURL name:@"test" MIMEType:nil];
	
	assertThat(rsrc.name, equalTo(@"test"));
	assertThat(rsrc.fileName, equalTo(@"upload-icon-test.png"));
	assertThatLongLong(rsrc.length, equalToLongLong(7355));
	assertThat(rsrc.MIMEType, equalTo(@"image/png"));
	assertThat(rsrc.MD5, equalTo(@"7166135eb596e03ad359f2dfb91f5ed4"));
}

@end
