//
//  DataWebApiResourceTests.m
//  WebApiClient
//
//  Created by Matt on 22/10/15.
//  Copyright © 2015 Blue Rocket, Inc. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseTestingSupport.h"

#import "DataWebApiResource.h"

@interface DataWebApiResourceTests : BaseTestingSupport

@end

@implementation DataWebApiResourceTests

- (void)testBasicProperties {
	const unsigned char input[4] = {4, 8, 12, 24};
	NSData *data = [NSData dataWithBytes:input length:4];
	DataWebApiResource *rsrc = [[DataWebApiResource alloc] initWithData:data name:@"test" fileName:@"file" MIMEType:nil];
	
	assertThat(rsrc.name, equalTo(@"test"));
	assertThat(rsrc.fileName, equalTo(@"file"));
	assertThatLongLong(rsrc.length, equalToLongLong(4));
	assertThat(rsrc.MIMEType, equalTo(@"application/octet-stream"));
	assertThat(rsrc.MD5, equalTo(@"623edca41c8071ada535895091acf2e5"));
}

@end
