//
//  AFNetworkingWebApiClientTests.m
//  WebApiClient
//
//  Created by Matt on 18/08/15.
//  Copyright (c) 2015 Blue Rocket. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseNetworkTestingSupport.h"

#import <OCMock/OCMock.h>
#import "WebApiAuthorizationProvider.h"
#import "WebApiClientSupport.h"
#import "RestKitWebApiDataMapper.h"

@interface TestWebApiClient : WebApiClientSupport

@property (nonatomic, readonly) NSArray *routeNames;

@end

@implementation TestWebApiClient {
	NSMutableArray *routeNames;
}

@synthesize routeNames;

- (void)registerRoute:(id<WebApiRoute>)route forName:(NSString *)name {
	[super registerRoute:route forName:name];
	if ( routeNames == nil ) {
		routeNames = [[NSMutableArray alloc] initWithCapacity:8];
	}
	[routeNames addObject:name];
}

@end

@interface User : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *password;
@end

@interface TestUser : User
@property (nonatomic, strong) NSString *subclassProp;
@end

@implementation User
@end

@implementation TestUser
@end

@interface TestAuthorizationProvider : NSObject <WebApiAuthorizationProvider>
@end

@implementation TestAuthorizationProvider

- (void)configureAuthorizationForRoute:(id<WebApiRoute>)route request:(NSMutableURLRequest *)request {
	[request addValue:@"token foobar" forHTTPHeaderField:@"Authorization"];
}

@end

#pragma mark - Unit tests

@interface WebApiClientSupportTests : BaseNetworkTestingSupport

@end

@implementation WebApiClientSupportTests {
	TestWebApiClient *client;
}

- (void)setUp {
	[super setUp];
	
	client = [[TestWebApiClient alloc] initWithEnvironment:self.testEnvironment];
}

- (void)testBaseApiURL {
	NSURL *baseURL = [client baseApiURL];
	assertThat(baseURL, equalTo([NSURL URLWithString:@"http://localhost/"]));
}

- (void)testLoadRoutes {
	assertThat(client.routeNames, hasItems(@"register", @"login", nil));
	id<WebApiRoute> route = [client routeForName:@"register" error:nil];
	assertThat(route, notNilValue());
	assertThat(route.name, equalTo(@"register"));
	assertThat(route.path, equalTo(@"register"));
	assertThat(route.method, equalTo(@"POST"));
	assertThat(route.dataMapper, equalTo(@"RestKitWebApiDataMapper"));
	assertThat(route[@"dataMapperRequestRootKeyPath"], equalTo(@"user"));
	assertThatBool(route.preventUserInteraction, isTrue());
	
	route = [client routeForName:@"login" error:nil];
	assertThat(route, notNilValue());
	assertThat(route.name, equalTo(@"login"));
	assertThat(route.path, equalTo(@"login"));
	assertThat(route.method, equalTo(@"POST"));
	assertThat(route.dataMapper, equalTo(@"RestKitWebApiDataMapper"));
	assertThat(route[@"dataMapperRequestRootKeyPath"], equalTo(@"user"));
	assertThatBool(route.preventUserInteraction, isTrue());
}

- (void)testURLPathVariable {
	id<WebApiRoute> route = [client routeForName:@"user" error:nil];
	NSURL *url = [client URLForRoute:route pathVariables:@{ @"userId" : @(1234) } parameters:nil error:nil];
	assertThat([url absoluteString], equalTo(@"http://localhost/user/1234"));
}

- (void)testURLPathVariableAbsoluteURL {
	id<WebApiRoute> route = [client routeForName:@"elsewhere" error:nil];
	NSURL *url = [client URLForRoute:route pathVariables:@{ @"baseURL" : @"https://example.com" } parameters:nil error:nil];
	assertThat([url absoluteString], equalTo(@"https://example.com/yes/i/can"));
}

- (void)testDictionaryFromUserObject {
	TestUser *user = [TestUser new];
	user.subclassProp = @"subclass";
	user.name = @"name";
	user.password = @"pass";
	NSDictionary *dictionary = [client dictionaryForParametersObject:user];
	assertThat(dictionary, equalTo(@{ @"subclassProp" : @"subclass",
									  @"name" : @"name",
									  @"password" : @"pass"}));
}

- (void)testRouteRegisteredWithDataMapper {
	id<WebApiRoute> route = [client routeForName:@"register" error:nil];
	id<WebApiDataMapper> mapper = [client dataMapperForRoute:route];
	assertThatBool([mapper isKindOfClass:[RestKitWebApiDataMapper class]], isTrue());
}

- (void)testAddAuthenticationHTTPHeaders {
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost/foo"]];
	id<WebApiRoute> route = [client routeForName:@"register" error:nil];
	client.appId = @"MyTestId";
	[client addAuthorizationHeadersToRequest:req forRoute:route];
	NSDictionary *headers = [req allHTTPHeaderFields];
	assertThat(headers, equalTo(@{ @"X-App-API-Key" : @"test_token",
								   @"X-App-ID" : @"MyTestId"}));
}

- (void)testAddAuthenticationHTTPHeadersWithUserService {
	TestAuthorizationProvider *authProvider = [TestAuthorizationProvider new];
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost/foo"]];
	id<WebApiRoute> route = [client routeForName:@"register" error:nil];
	client.appId = @"MyTestId";
	client.authorizationProvider = authProvider;
	[client addAuthorizationHeadersToRequest:req forRoute:route];
	NSDictionary *headers = [req allHTTPHeaderFields];
	assertThat(headers, equalTo(@{ @"X-App-API-Key" : @"test_token",
								   @"X-App-ID" : @"MyTestId",
								   @"Authorization" : @"token foobar"}));
}

/**
 Hmm, testing with NSHTTPCookieStorage doesn't seem to work, so this is commented out for now.
 I'm not alone in this assessment: http://stackoverflow.com/questions/20134621/unit-testing-nshttpcookiestore
 
- (void)testCookiesAccessForBaseApiURL {
	NSHTTPCookieStorage *jar = [[NSHTTPCookieStorage alloc] init];
	jar.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
	NSDictionary *cookieData = @{
								 NSHTTPCookieName : @"test",
								 NSHTTPCookieExpires : [NSDate distantFuture],
								 NSHTTPCookieOriginURL : [[client baseApiURL] absoluteString],
								 NSHTTPCookiePath : @"/",
								 NSHTTPCookieValue : @"test-value",
								 };
	NSHTTPCookie *cookie = [[NSHTTPCookie alloc] initWithProperties:cookieData];
	[jar setCookie:cookie];
	assertThat(jar.cookies, hasCountOf(1));
	NSArray<NSHTTPCookie *> *found = [client cookiesForAPI:nil inCookieStorage:jar];
	assertThat(found, contains(cookie, nil));
}
*/

@end
