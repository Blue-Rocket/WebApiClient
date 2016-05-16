//
//  JSONAPIErrorExtractorTests.m
//  WebApiClient
//
//  Created by Matt on 4/25/16.
//  Copyright © 2016 Blue Rocket, Inc. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseTestingSupport.h"

#import "JSONAPIError.h"
#import "JSONAPIErrorExtractor.h"
#import "NSDictionary+WebApiClient.h"

static NSString * const kErrorDomain = @"Foobar";

@interface JSONAPIErrorExtractorTests : BaseTestingSupport

@end

@implementation JSONAPIErrorExtractorTests {
	JSONAPIErrorExtractor *extractor;
}

- (void)setUp {
    [super setUp];
	extractor = [[JSONAPIErrorExtractor alloc] init];
	extractor.errorDomain = kErrorDomain;
}

- (void)testNonErrorResult {
	id<WebApiResponse> response = @{@"routeName" : @"foo",
									@"statusCode" : @200,
									@"responseObject" : @"Hi."};
	NSError *error = [extractor errorForResponse:response error:nil];
	assertThat(error, nilValue());
}

- (void)testSingleErrorResult {
	id<WebApiResponse> response = @{@"routeName" : @"foo",
									@"statusCode" : @422,
									@"responseObject" : @{
											@"errors" : @[
													@{
														@"id" : @"abc123",
														@"code" : @"123",
														@"status" : @"422",
														@"title" : @"Title",
														@"detail" : @"Detail",
														}
													]
											}};
	NSError *origError = [NSError errorWithDomain:@"Orig" code:-123 userInfo:nil];
	NSError *error = [extractor errorForResponse:response error:origError];
	assertThat(error, notNilValue());
	assertThat(error.domain, equalTo(kErrorDomain));
	assertThatInteger(error.code, equalToInteger(123));
	assertThat(error.localizedDescription, equalTo(@"Detail"));
	assertThat(error.userInfo[WebApiErrorResponseObjectKey], instanceOf([NSArray class]));
	
	NSArray *jsonErrors = error.userInfo[WebApiErrorResponseObjectKey];
	assertThat(jsonErrors, hasCountOf(1));
	assertThat([jsonErrors firstObject], isA([JSONAPIError class]));
	JSONAPIError *jsonError = [jsonErrors firstObject];
	assertThat(jsonError.id, equalTo(@"abc123"));
}

@end
