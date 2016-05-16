//
//  JSONAPIErrorTests.m
//  WebApiClient
//
//  Created by Matt on 4/25/16.
//  Copyright © 2016 Blue Rocket, Inc. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseTestingSupport.h"

#import "JSONAPIError.h"

@interface JSONAPIErrorTests : BaseTestingSupport

@end

@implementation JSONAPIErrorTests

- (void)testInitializeWithDictionary {
	NSDictionary<NSString *, id> *dict = @{
										   @"id" : @"abc123",
										   @"code" : @"123",
										   @"status" : @"422",
										   @"title" : @"Title",
										   @"detail" : @"Detail",
										   };
	JSONAPIError *error = [[JSONAPIError alloc] initWithResponseObject:dict];
	assertThat(error, notNilValue());
	assertThat(error.id, equalTo(@"abc123"));
	assertThat(error.code, equalTo(@"123"));
	assertThat(error.status, equalTo(@"422"));
	assertThat(error.title, equalTo(@"Title"));
	assertThat(error.detail, equalTo(@"Detail"));
}

- (void)testInitializeHelperWithDictionary {
	NSDictionary<NSString *, id> *dict = @{
										   @"id" : @"abc123",
										   @"code" : @"123",
										   @"status" : @"422",
										   @"title" : @"Title",
										   @"detail" : @"Detail",
										   };
	JSONAPIError *error = [JSONAPIError JSONAPIErrorWithResponseObject:dict];
	assertThat(error, notNilValue());
	assertThat(error.id, equalTo(@"abc123"));
	assertThat(error.code, equalTo(@"123"));
	assertThat(error.status, equalTo(@"422"));
	assertThat(error.title, equalTo(@"Title"));
	assertThat(error.detail, equalTo(@"Detail"));
}

@end
