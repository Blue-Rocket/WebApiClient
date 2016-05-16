//
//  AFNetworkingWebApiClientTests.m
//  WebApiClient
//
//  Created by Matt on 18/08/15.
//  Copyright (c) 2015 Blue Rocket. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseNetworkTestingSupport.h"

#import <AFNetworking/AFURLSessionManager.h>
#import <CocoaHTTPServer/DDData.h>
#import <Godzippa/Godzippa.h>
#import "AFNetworkingWebApiClient.h"
#import "DataWebApiResource.h"
#import "FileWebApiResource.h"
#import "JSONAPIErrorExtractor.h"
#import "WebApiClientEnvironment.h"

@interface AFNetworkingWebApiClientTests : BaseNetworkTestingSupport

@end

@interface AFNetworkingWebApiClientTestsBean : NSObject
@property (nonatomic, strong) NSString *uniqueId;
@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSDictionary *info;
@end

@implementation AFNetworkingWebApiClientTestsBean
@end

@implementation AFNetworkingWebApiClientTests {
	AFNetworkingWebApiClient *client;
}

- (void)setUp {
	[super setUp];
	BREnvironment *env = [self.testEnvironment copy];
	env[WebApiClientSupportServerPortEnvironmentKey] = [NSString stringWithFormat:@"%u", [self.http listeningPort]];
	NSLog(@"Environment port set to %@", env[WebApiClientSupportServerPortEnvironmentKey]);
	client = [[AFNetworkingWebApiClient alloc] initWithEnvironment:env];
}

- (void)testNotificationsSuccess {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	id<WebApiRoute> route = [client routeForName:@"test" error:nil];
	
	__block BOOL willBegin = NO;
	[self expectationForNotification:WebApiClientRequestWillBeginNotification object:route handler:^BOOL(NSNotification *note) {
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSURLResponse *res = [note userInfo][WebApiClientURLResponseNotificationKey];
		assertThat(req.URL.absoluteString, equalTo([self httpURLForRelativePath:@"test"].absoluteString));
		assertThat(res, nilValue());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		willBegin = YES;
		return YES;
	}];

	__block BOOL didBegin = NO;
	[self expectationForNotification:WebApiClientRequestDidBeginNotification object:route handler:^BOOL(NSNotification *note) {
		didBegin = YES;
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSURLResponse *res = [note userInfo][WebApiClientURLResponseNotificationKey];
		assertThat(req.URL.absoluteString, equalTo([self httpURLForRelativePath:@"test"].absoluteString));
		assertThat(res, nilValue());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		// make sure task identifier is tracked appropriately
		assertThat(client.activeTaskIdentifiers, hasCountOf(1));
		return YES;
	}];
	
	__block BOOL didSucceed = NO;
	[self expectationForNotification:WebApiClientRequestDidSucceedNotification object:route handler:^BOOL(NSNotification *note) {
		didSucceed = YES;
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSURLResponse *res = [note userInfo][WebApiClientURLResponseNotificationKey];
		assertThat(req.URL.absoluteString, equalTo([self httpURLForRelativePath:@"test"].absoluteString));
		assertThat(res, notNilValue());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));

		// make sure task identifier is released appropriately
		assertThat(client.activeTaskIdentifiers, isEmpty());
		
		return YES;
	}];
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThatBool(willBegin, isTrue());
		assertThatBool(didBegin, isTrue());
		assertThatBool(didSucceed, isFalse());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testInvokeError404 {
	__block BOOL called = NO;
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThatInteger(response.statusCode, equalTo(@404));
		assertThat(error, notNilValue());
		assertThat([error.userInfo[NSURLErrorFailingURLErrorKey] absoluteString], equalTo([[self httpURLForRelativePath:@"test"] absoluteString]));
		assertThat(response.responseObject, nilValue());
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokeError422 {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"code\":123, \"message\":\"Your request failed.\"}" response:response status:422];
	}];
	
	__block BOOL called = NO;
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThatInteger(response.statusCode, equalTo(@422));
		assertThat(error, notNilValue());
		assertThat(response.responseObject, notNilValue());
		assertThat([response.responseObject valueForKeyPath:@"code"], equalTo(@123));
		assertThat([response.responseObject valueForKeyPath:@"message"], equalTo(@"Your request failed."));
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokeError422JSONAPI {
	client.errorExtractor = [JSONAPIErrorExtractor new];
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"errors\":[{\"code\":\"123\",\"detail\":\"Your request failed.\"}]}" response:response status:422];
	}];
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThatInteger(response.statusCode, equalTo(@422));
		assertThat(error, notNilValue());
		assertThatInteger(error.code, equalToInteger(123));
		assertThat(error.localizedDescription, equalTo(@"Your request failed."));
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testInvokeSimpleGET {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		assertThat(request.headers[@"Accept"], equalTo(WebApiClientJSONContentType));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];

	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)respondWithJSONAPI:(NSString *)json response:(RouteResponse *)response status:(NSInteger)statusCode {
	[response setStatusCode:statusCode];
	[response setHeader:@"Content-Type" value:@"application/vnd.api+json; charset=utf-8"];
	[response respondWithString:json encoding:NSUTF8StringEncoding];
}

- (void)testInvokeSimpleJSONAPI_GET {
	client.defaultSerializationAcceptableContentTypes = @{[NSDictionary nameForWebApiSerialization:WebApiSerializationJSON] : WebApiClientJSONAPIContentType};
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		assertThat(request.headers[@"Accept"], equalTo(WebApiClientJSONAPIContentType));
		[self respondWithJSONAPI:@"{\"success\":true}" response:response status:200];
	}];
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testInvokeSimpleGETOnBackgroundThread {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	__block BOOL called = NO;
	[client requestAPI:@"test" withPathVariables:nil parameters:nil data:nil queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
			  progress:nil 
			  finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should NOT be on main thread", isFalse(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokeSimpleGETBlockingThread {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	NSTimeInterval maxWait = 2;
	NSError *error = nil;
	id<WebApiResponse> response = [client blockingRequestAPI:@"test" withPathVariables:nil parameters:nil data:nil maximumWait:maxWait error:&error];
	assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
	assertThat(error, nilValue());
	assertThat(response.routeName, equalTo(@"test"));
}

- (void)testInvokeSimpleGETBlockingThreadTimeout {
	NSTimeInterval maxWait = 2;

	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		[NSThread sleepForTimeInterval:maxWait + 0.2];
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	NSError *error = nil;
	id<WebApiResponse> response = [client blockingRequestAPI:@"test" withPathVariables:nil parameters:nil data:nil maximumWait:maxWait error:&error];
	assertThat(response, nilValue());
	assertThat(error, notNilValue());
	assertThat(error.domain, equalTo(WebApiClientErrorDomain));
	assertThatInteger(error.code, equalToInteger(WebApiClientErrorResponseTimeout));
}

- (void)testInvokeGETWithPathVariable {
	[self.http handleMethod:@"GET" withPath:@"/document/123" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	__block BOOL called = NO;
	[client requestAPI:@"doc" withPathVariables:@{@"uniqueId" : @123 } parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"doc"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokeGETWithPathVariableObject {
	[self.http handleMethod:@"GET" withPath:@"/document/123" block:^(RouteRequest *request, RouteResponse *response) {
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	// instead of a dictionary, pass an arbitrary object for the path variables; all declared properties will be available as path variables
	AFNetworkingWebApiClientTestsBean *docRef = [AFNetworkingWebApiClientTestsBean new];
	docRef.uniqueId = @"123";
	docRef.displayName = @"Top Secret";
	
	__block BOOL called = NO;
	[client requestAPI:@"doc" withPathVariables:docRef parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"doc"));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokeGETWithQueryParameter {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		NSDictionary *queryParams = [request params];
		assertThat(queryParams[@"foo"], equalTo(@"bar"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	__block BOOL called = NO;
	[client requestAPI:@"test" withPathVariables:nil parameters:@{@"foo" : @"bar"} data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokeGETWithQueryParameterObject {
	[self.http handleMethod:@"GET" withPath:@"/test" block:^(RouteRequest *request, RouteResponse *response) {
		NSDictionary *queryParams = [request params];
		assertThat(queryParams[@"uniqueId"], equalTo(@"123"));
		assertThat(queryParams[@"displayName"], equalTo(@"Top Secret"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	// instead of a dictionary, pass an arbitrary object for the query params; all declared properties will be available as parameters
	AFNetworkingWebApiClientTestsBean *docRef = [AFNetworkingWebApiClientTestsBean new];
	docRef.uniqueId = @"123";
	docRef.displayName = @"Top Secret";
	
	__block BOOL called = NO;
	[client requestAPI:@"test" withPathVariables:nil parameters:docRef data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"test"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testInvokePUTWithParameterObject {
	[self.http handleMethod:@"PUT" withPath:@"/document/123" block:^(RouteRequest *request, RouteResponse *response) {
		NSDictionary *postParams = [NSJSONSerialization JSONObjectWithData:[request body] options:0 error:nil];
		assertThat(postParams[@"uniqueId"], equalTo(@"123"));
		assertThat(postParams[@"displayName"], equalTo(@"Top Secret"));
		assertThat([postParams valueForKeyPath:@"info.password"], equalTo(@"secret"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	// instead of a dictionary, pass an arbitrary object for the query params; all declared properties will be available as parameters
	AFNetworkingWebApiClientTestsBean *docRef = [AFNetworkingWebApiClientTestsBean new];
	docRef.uniqueId = @"123";
	docRef.displayName = @"Top Secret";
	docRef.info = @{@"password" : @"secret"};
	
	__block BOOL called = NO;
	[client requestAPI:@"saveDoc" withPathVariables:docRef parameters:docRef data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"saveDoc"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		called = YES;
	}];
	assertThatBool([self processMainRunLoopAtMost:10 stop:&called], equalTo(@YES));
}

- (void)testFileUpload {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-test.txt" withExtension:nil];
	[self.http handleMethod:@"POST" withPath:@"/file/test_file" block:^(RouteRequest *request, RouteResponse *response) {
		NSDictionary *bodyParts = [self extractMultipartFormParts:request];
		assertThat(bodyParts, hasCountOf(1));
		DataWebApiResource *rsrc = bodyParts[@"test_file"];
		assertThat(rsrc.MIMEType, equalTo(@"text/plain"));
		assertThat(rsrc.fileName, equalTo(@"upload-test.txt"));
		assertThat([[NSString alloc] initWithData:rsrc.data encoding:NSUTF8StringEncoding], equalTo(@"Hello, server!\n"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"test_file" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"file" withPathVariables:r parameters:nil data:r finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"file"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testFileAndParametersUpload {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-test.txt" withExtension:nil];
	[self.http handleMethod:@"POST" withPath:@"/file/test_file" block:^(RouteRequest *request, RouteResponse *response) {
		NSDictionary *bodyParts = [self extractMultipartFormParts:request];
		assertThat(bodyParts, hasCountOf(2));
		DataWebApiResource *rsrc = bodyParts[@"test_file"];
		assertThat(rsrc.MIMEType, equalTo(@"text/plain"));
		assertThat(rsrc.fileName, equalTo(@"upload-test.txt"));
		assertThat([[NSString alloc] initWithData:rsrc.data encoding:NSUTF8StringEncoding], equalTo(@"Hello, server!\n"));
		
		NSString *fooValue = bodyParts[@"foo"];
		assertThat(fooValue, equalTo(@"bar"));
		
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"test_file" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"file" withPathVariables:r parameters:@{@"foo" : @"bar"} data:r finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"file"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testRawDataUpload {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil][NSFileSize];
	NSString *fileMD5 = [[[NSData dataWithContentsOfURL:fileURL] md5Digest] hexStringValue];
	[self.http handleMethod:@"POST" withPath:@"/image" block:^(RouteRequest *request, RouteResponse *response) {
		NSData *bodyData = [request body];
		NSString *md5 = [[bodyData md5Digest] hexStringValue];
		assertThat(md5, equalTo(fileMD5));
		assertThat([request header:@"Content-Length"], equalTo([NSString stringWithFormat:@"%llu", [fileSize unsignedLongLongValue]]));
		assertThat([request header:@"Content-Type"], equalTo(@"image/png"));
		assertThat([request header:@"Content-MD5"], equalTo(@"7166135eb596e03ad359f2dfb91f5ed4"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"image.png" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"upload-image" withPathVariables:nil parameters:nil data:r finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"upload-image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testRawDataUploadWithProgress {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil][NSFileSize];
	NSString *fileMD5 = [[[NSData dataWithContentsOfURL:fileURL] md5Digest] hexStringValue];
	[self.http handleMethod:@"POST" withPath:@"/image" block:^(RouteRequest *request, RouteResponse *response) {
		NSData *bodyData = [request body];
		NSString *md5 = [[bodyData md5Digest] hexStringValue];
		assertThat(md5, equalTo(fileMD5));
		assertThat([request header:@"Content-Length"], equalTo([NSString stringWithFormat:@"%llu", [fileSize unsignedLongLongValue]]));
		assertThat([request header:@"Content-Type"], equalTo(@"image/png"));
		assertThat([request header:@"Content-MD5"], equalTo(@"7166135eb596e03ad359f2dfb91f5ed4"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"image.png" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	__block NSProgress *upProgress = NO;
	__block BOOL downloadProgressed = NO;
	[client requestAPI:@"upload-image" withPathVariables:nil parameters:nil data:r queue:dispatch_get_main_queue() progress:^(NSString * _Nonnull routeName, NSProgress * _Nullable uploadProgress, NSProgress * _Nullable downloadProgress) {
		if ( uploadProgress && !upProgress ) {
			assertThatDouble(uploadProgress.fractionCompleted, greaterThan(@0));
			upProgress = uploadProgress;
		}
		if ( downloadProgress ) {
			assertThatDouble(downloadProgress.fractionCompleted, greaterThan(@0));
			downloadProgressed = YES;
		}
		assertThat(routeName, equalTo(@"upload-image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
	} finished:^(id<WebApiResponse>  _Nonnull response, NSError * _Nullable error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"upload-image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:5 handler:nil];
	assertThat(upProgress, describedAs(@"Got upload progress", notNilValue(), nil));
	assertThatDouble(upProgress.fractionCompleted, isNot(lessThan(@1.0)));
	assertThatBool(downloadProgressed, describedAs(@"Got download progress", isTrue(), nil));
}

- (void)testRawDataUploadProgressNotifications {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil][NSFileSize];
	NSString *fileMD5 = [[[NSData dataWithContentsOfURL:fileURL] md5Digest] hexStringValue];
	[self.http handleMethod:@"POST" withPath:@"/image" block:^(RouteRequest *request, RouteResponse *response) {
		NSData *bodyData = [request body];
		NSString *md5 = [[bodyData md5Digest] hexStringValue];
		assertThat(md5, equalTo(fileMD5));
		assertThat([request header:@"Content-Length"], equalTo([NSString stringWithFormat:@"%llu", [fileSize unsignedLongLongValue]]));
		assertThat([request header:@"Content-Type"], equalTo(@"image/png"));
		assertThat([request header:@"Content-MD5"], equalTo(@"7166135eb596e03ad359f2dfb91f5ed4"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	id<WebApiRoute> route = [client routeForName:@"upload-image" error:nil];
	NSString *routeURLString = [self httpURLForRelativePath:@"image"].absoluteString;
	
	__block BOOL willBegin = NO;
	[self expectationForNotification:WebApiClientRequestWillBeginNotification object:route handler:^BOOL(NSNotification *note) {
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSURLResponse *res = [note userInfo][WebApiClientURLResponseNotificationKey];
		assertThat(req.URL.absoluteString, equalTo(routeURLString));
		assertThat(res, nilValue());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		willBegin = YES;
		return YES;
	}];
	
	__block BOOL didBegin = NO;
	[self expectationForNotification:WebApiClientRequestDidBeginNotification object:route handler:^BOOL(NSNotification *note) {
		didBegin = YES;
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSURLResponse *res = [note userInfo][WebApiClientURLResponseNotificationKey];
		assertThat(req.URL.absoluteString, equalTo(routeURLString));
		assertThat(res, nilValue());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		// make sure task identifier is tracked appropriately
		assertThat(client.activeTaskIdentifiers, hasCountOf(1));
		return YES;
	}];
	
	__block BOOL didProgress = NO;
	[self expectationForNotification:WebApiClientRequestDidProgressNotification object:route handler:^BOOL(NSNotification *note) {
		didProgress = YES;
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSProgress *progress = [note userInfo][WebApiClientProgressNotificationKey];
		assertThat(req.URL.absoluteString, equalTo(routeURLString));
		assertThat(progress, notNilValue());
		assertThatDouble(progress.fractionCompleted, greaterThan(@0));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		// make sure task identifier is released appropriately
		assertThat(client.activeTaskIdentifiers, hasCountOf(1));
		
		return YES;
	}];
	
	__block BOOL didSucceed = NO;
	[self expectationForNotification:WebApiClientRequestDidSucceedNotification object:route handler:^BOOL(NSNotification *note) {
		didSucceed = YES;
		NSURLRequest *req = [note userInfo][WebApiClientURLRequestNotificationKey];
		NSURLResponse *res = [note userInfo][WebApiClientURLResponseNotificationKey];
		assertThat(req.URL.absoluteString, equalTo(routeURLString));
		assertThat(res, notNilValue());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		// make sure task identifier is released appropriately
		assertThat(client.activeTaskIdentifiers, isEmpty());
		
		return YES;
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"image.png" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"upload-image" withPathVariables:nil parameters:nil data:r finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"upload-image"));
		assertThatBool(willBegin, isTrue());
		assertThatBool(didBegin, isTrue());
		assertThatBool(didProgress, isTrue());
		assertThatBool(didSucceed, isFalse());
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testFormPOST {
	NSDictionary *formParameters = @{@"one" : @"two", @"three" : @"four"};
	[self.http handleMethod:@"POST" withPath:@"/form" block:^(RouteRequest *request, RouteResponse *response) {
		NSDictionary *bodyParts = [self extractMultipartFormParts:request];
		assertThat(bodyParts, equalTo(formParameters));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"form-post" withPathVariables:nil parameters:formParameters data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"form-post"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	
	// also test using the serializationName form in config.json, to the same endpoint
	XCTestExpectation *requestAltExpectation = [self expectationWithDescription:@"HTTP alt request"];
	[client requestAPI:@"form-post-alt" withPathVariables:nil parameters:formParameters data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"form-post-alt"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestAltExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testInvokeGETWithGzipEncoding {
	[self.http handleMethod:@"GET" withPath:@"/document/123" block:^(RouteRequest *request, RouteResponse *response) {
		assertThat([request header:@"Accept-Encoding"], equalTo(@"gzip"));

		NSError *error = nil;
		NSData *compressed = [[@"{\"success\":true}" dataUsingEncoding:NSUTF8StringEncoding] dataByGZipCompressingWithError:&error];
		assertThat(error, nilValue());
		
		[response setStatusCode:200];
		[response setHeader:@"Content-Type" value:@"application/json; charset=utf-8"];
		[response setHeader:@"Content-Encoding" value:@"gzip"];
		[response respondWithData:compressed];
	}];
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"docGzip" withPathVariables:@{@"uniqueId" : @123 } parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"docGzip"));
		assertThat(response.responseHeaders[@"Content-Encoding"], equalTo(@"gzip"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:2 handler:nil];
}


- (void)testInvokePUTWithGzipEncoding {
	[self.http handleMethod:@"PUT" withPath:@"/document/123" block:^(RouteRequest *request, RouteResponse *response) {
		assertThat([request header:@"Content-Encoding"], equalTo(@"gzip"));
		NSError *error = nil;
		NSData *decompressed = [[request body] dataByGZipDecompressingDataWithError:&error];
		assertThat(error, nilValue());
		NSDictionary *postParams = [NSJSONSerialization JSONObjectWithData:decompressed options:0 error:nil];
		assertThat(postParams[@"uniqueId"], equalTo(@"123"));
		assertThat(postParams[@"displayName"], equalTo(@"Top Secret"));
		assertThat([postParams valueForKeyPath:@"info.password"], equalTo(@"secret"));
		[self respondWithJSON:@"{\"success\":true}" response:response status:200];
	}];
	
	// instead of a dictionary, pass an arbitrary object for the query params; all declared properties will be available as parameters
	AFNetworkingWebApiClientTestsBean *docRef = [AFNetworkingWebApiClientTestsBean new];
	docRef.uniqueId = @"123";
	docRef.displayName = @"Top Secret";
	docRef.info = @{@"password" : @"secret"};
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"saveDocGzip" withPathVariables:docRef parameters:docRef data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, equalTo(@{@"success" : @YES}));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"saveDocGzip"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		[requestExpectation fulfill];
	}];
	[self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testImageRequest {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	UIImage *image = [UIImage imageWithContentsOfFile:[fileURL path]];
	[self.http handleMethod:@"GET" withPath:@"/image" block:^(RouteRequest *request, RouteResponse *response) {
		[response setStatusCode:200];
		[response respondWithFile:fileURL.path async:YES];
	}];
	
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"image" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, instanceOf([UIImage class]));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		UIImage *img = response.responseObject;
		assertThatInt((int)(image.size.width * image.scale), equalToInt((int)(img.size.width * img.scale)));
		assertThatInt((int)(image.size.height * image.scale), equalToInt((int)(img.size.height * img.scale)));
		
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testImageDownload {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil][NSFileSize];
	NSString *fileMD5 = [[[NSData dataWithContentsOfURL:fileURL] md5Digest] hexStringValue];
	[self.http handleMethod:@"GET" withPath:@"/image" block:^(RouteRequest *request, RouteResponse *response) {
		[response setStatusCode:200];
		[response respondWithFile:fileURL.path async:YES];
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"image.png" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	[client requestAPI:@"download-image" withPathVariables:nil parameters:nil data:nil finished:^(id<WebApiResponse> response, NSError *error) {
		assertThat(response.responseObject, instanceOf([FileWebApiResource class]));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"download-image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		FileWebApiResource *resource = response.responseObject;
		assertThat(resource, isNot(sameInstance(r)));
		assertThat(resource.MIMEType, equalTo(@"image/png"));
		assertThat(resource.MD5, equalTo(fileMD5));
		assertThatLongLong(resource.length, equalTo(fileSize));
		
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testImageDownloadWithProgress {
	NSURL *fileURL = [self.bundle URLForResource:@"upload-icon-test.png" withExtension:nil];
	NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil][NSFileSize];
	NSString *fileMD5 = [[[NSData dataWithContentsOfURL:fileURL] md5Digest] hexStringValue];
	[self.http handleMethod:@"GET" withPath:@"/image" block:^(RouteRequest *request, RouteResponse *response) {
		[response setStatusCode:200];
		[response respondWithFile:fileURL.path async:YES];
	}];
	
	FileWebApiResource *r = [[FileWebApiResource alloc] initWithURL:fileURL name:@"image.png" MIMEType:nil];
	XCTestExpectation *requestExpectation = [self expectationWithDescription:@"HTTP request"];
	__block BOOL uploadProgressed = NO;
	__block BOOL downloadProgressed = NO;
	[client requestAPI:@"download-image" withPathVariables:nil parameters:nil data:nil queue:dispatch_get_main_queue() progress:^(NSString * _Nonnull routeName, NSProgress * _Nullable uploadProgress, NSProgress * _Nullable downloadProgress) {
		if ( uploadProgress ) {
			uploadProgressed = YES;
		}
		if ( downloadProgress ) {
			assertThatDouble(downloadProgress.fractionCompleted, greaterThan(@0));
			downloadProgressed = YES;
		}
		assertThat(routeName, equalTo(@"download-image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
	} finished:^(id<WebApiResponse>  _Nullable response, NSError * _Nullable error) {
		assertThat(response.responseObject, instanceOf([FileWebApiResource class]));
		assertThat(error, nilValue());
		assertThat(response.routeName, equalTo(@"download-image"));
		assertThatBool([NSThread isMainThread], describedAs(@"Should be on main thread", isTrue(), nil));
		
		FileWebApiResource *resource = response.responseObject;
		assertThat(resource, isNot(sameInstance(r)));
		assertThat(resource.MIMEType, equalTo(@"image/png"));
		assertThat(resource.MD5, equalTo(fileMD5));
		assertThatLongLong(resource.length, equalTo(fileSize));
		assertThat([resource URLValue], notNilValue());
		
		[requestExpectation fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:5 handler:nil];
	assertThatBool(uploadProgressed, describedAs(@"There should be no upload progress for GET", isFalse(), nil));
	assertThatBool(downloadProgressed, describedAs(@"Got download progress", isTrue(), nil));
}

@end
