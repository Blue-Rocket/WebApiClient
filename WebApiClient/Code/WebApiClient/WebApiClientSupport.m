//
//  WebApiClientSupport.m
//  WebApiClient
//
//  Created by Matt on 12/08/15.
//  Copyright (c) 2015 Blue Rocket. Distributable under the terms of the Apache License, Version 2.0.
//

#import "WebApiClientSupport.h"

#import <BRCocoaLumberjack/BRCocoaLumberjack.h>
#import <BREnvironment/BREnvironment.h>
#import <BRLocalize/Core.h>
#import <MAObjCRuntime/MARTNSObject.h>
#import <MAObjCRuntime/RTProperty.h>
#import <SOCKit/SOCKit.h>
#import "WebApiAuthorizationProvider.h"
#import "WebApiClientEnvironment.h"
#import "WebApiDataMapper.h"

NSString * const WebApiClientSupportAppApiKeyDefaultHTTPHeaderName = @"X-Api-Key";
NSString * const WebApiClientSupportAppIdDefaultHTTPHeaderName = @"X-App-ID";

static NSString * const kRoutePropertyPattern = @"_pattern";
static NSString * const kRoutePropertyDataMapperInstance = @"_dataMapper";

@implementation WebApiClientSupport {
	NSMutableDictionary *routes;
	NSURL *baseApiURL;
}

- (id)init {
	return [self initWithEnvironment:[BREnvironment sharedEnvironment]];
}

- (id)initWithEnvironment:(BREnvironment *)theEnvironment {
	if ( (self = [super init]) ) {
		routes = [[NSMutableDictionary alloc] initWithCapacity:16];
		self.appApiKey = theEnvironment[WebApiClientSupportAppApiKeyEnvironmentKey];
		self.appApiKeyHTTPHeaderName = WebApiClientSupportAppApiKeyDefaultHTTPHeaderName;
		self.appIdHTTPHeaderName = WebApiClientSupportAppIdDefaultHTTPHeaderName;
		self.appId = [[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleIdentifierKey];
		[self loadDefaultRoutes:theEnvironment];
		baseApiURL = [self setupBaseApiURL:theEnvironment];
	}
	return self;
}

+ (instancetype)sharedClient {
	static WebApiClientSupport *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[self alloc] init];
	});
	return shared;
}

- (void)loadDefaultRoutes:(BREnvironment *)environment {
	// look for routes in config.json/webservice.api dictionary
	id routeConfigs = environment[@"webservice.api"];
	if ( ![routeConfigs conformsToProtocol:@protocol(NSFastEnumeration)] ) {
		return;
	}
   for ( id routeName in routeConfigs ) {
	   DDLogDebug(@"Inspecting web api route %@", routeName);
	   [self registerRoute:routeConfigs[routeName] forName:routeName];
   }
}

- (NSURL *)setupBaseApiURL:(BREnvironment *)environment {
	NSString *protocol = environment[WebApiClientSupportServerProtocolEnvironmentKey];
	NSString *host = environment[WebApiClientSupportServerHostEnvironmentKey];
	int port = [environment[WebApiClientSupportServerPortEnvironmentKey] intValue];
	
	if ( !port
		|| ([protocol isEqualToString:@"http"] && port == 80 )
		|| ([protocol isEqualToString:@"https"] && port == 443) ) {
		// don't include port in base URL
		return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/", protocol, host]];
	}
	return [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%d/", protocol, host, port]];
}

- (void)registerRoute:(id<WebApiRoute>)route forName:(NSString *)name {
	NSMutableDictionary *internalRoute = [[NSMutableDictionary alloc] initWithCapacity:4];
	if ( [route isKindOfClass:[NSDictionary class]] ) {
		// copy all route props
		[internalRoute addEntriesFromDictionary:(NSDictionary *)route];
	} else {
		// manually copy WebApiRoute values
		internalRoute[NSStringFromSelector(@selector(method))] = route.method;
		internalRoute[NSStringFromSelector(@selector(path))] = route.path;
	}
	
	// force name to given name
	internalRoute.name = name;
	
	// add our SOCPattern
	internalRoute[kRoutePropertyPattern] = [[SOCPattern alloc] initWithString:route.path];
	
	routes[name] = internalRoute;
	
	// extending classes may want to do more here, just please call [super registerRoute:forName:]
}

- (id<WebApiRoute>)routeForName:(NSString *)name error:(NSError *__autoreleasing *)error {
	id<WebApiRoute> result = routes[name];
	if ( !result && error ) {
		*error = [NSError errorWithDomain:WebApiClientErrorDomain code:WebApiClientErrorRouteNotAvailable userInfo:
				  @{@"name" : name, NSLocalizedDescriptionKey : [@"{web.api.missingRoute}" localizedString] }];
	}
	return result;
}

- (NSURL *)baseApiURL {
	return baseApiURL;
}

- (NSDictionary *)dictionaryForParametersObject:(id)parameters {
	if ( [parameters isKindOfClass:[NSDictionary class]] ) {
		return parameters;
	}
	
	static NSSet *ignoreProperties;
	if ( !ignoreProperties ) {
		ignoreProperties = [NSSet setWithArray:@[@"hash", @"superclass", @"description", @"debugDescription"]];
	}
	
	// inspect properties of object up to, but not including, root class, and return dictionary of all those values
	NSMutableArray *propNames = [[NSMutableArray alloc] initWithCapacity:8];
	Class objClass = [parameters class];
	while ( class_getSuperclass(objClass) ) {
		for ( RTProperty *prop in [objClass rt_properties] ) {
			if ( [ignoreProperties containsObject:prop.name] ) {
				continue;
			}
			[propNames addObject:prop.name];
		}
		objClass = class_getSuperclass(objClass);
	}
	NSDictionary *result = [parameters dictionaryWithValuesForKeys:propNames];
	NSSet *nulls = [result keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
		return [obj isKindOfClass:[NSNull class]];
	}];
	if ( [nulls anyObject] ) {
		NSMutableDictionary *mutableResult = [result mutableCopy];
		[mutableResult removeObjectsForKeys:[nulls allObjects]];
		result = mutableResult;
	}
	return result;
}

- (NSURL *)URLForRoute:(id<WebApiRoute>)route pathVariables:(id)pathVariables parameters:(id)parameters error:(NSError *__autoreleasing *)error {
	NSString *path = nil;
	SOCPattern *pattern = route[kRoutePropertyPattern];
	if ( pattern ) {
		path = [pattern stringFromObject:pathVariables withBlock:^NSString *(NSString *propertyValue) {
			return [propertyValue stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		}];
	} else {
		path = route.path;
	}
	
	if ( !path ) {
		DDLogError(@"No API path defined for route %@", route);
		if ( error ) {
			*error = [NSError errorWithDomain:WebApiClientErrorDomain code:WebApiClientErrorRouteNotAvailable userInfo:
					  @{@"route" : route, NSLocalizedDescriptionKey : [@"{web.api.missingRoutePath}" localizedString] }];
		}
		return nil;
	}
	
	if ( parameters ) {
		NSString *params = [[self dictionaryForParametersObject:parameters] asURLQueryParameterString];
		if ( [params length] > 0 ) {
			path = [path stringByAppendingFormat:@"?%@", params];
		}
	}
	
	NSURL *url = [NSURL URLWithString:path relativeToURL:[self baseApiURL]];
	return url;
}

- (id<WebApiDataMapper>)dataMapperForRoute:(id<WebApiRoute>)route {
	id<WebApiDataMapper> mapper = route[kRoutePropertyDataMapperInstance];
	if ( mapper ) {
		return mapper;
	}
	NSString *dataMapperName = route.dataMapper;
	if ( [dataMapperName length] < 1 ) {
		return nil;
	}
	// is this a class name?
	Class dataMapperClass = NSClassFromString(dataMapperName);
	if ( dataMapperClass ) {
		if ( [dataMapperClass conformsToProtocol:@protocol(WebApiSingletonDataMapper)] ) {
			mapper = [dataMapperClass sharedDataMapper];
		} else {
			mapper = [[dataMapperClass alloc] init];
		}
	}
	if ( mapper && [route conformsToProtocol:@protocol(MutableWebApiRoute)] ) {
		route[kRoutePropertyDataMapperInstance] = mapper;
	}
	return mapper;
}

- (void)requestAPI:(NSString *)name withPathVariables:(id)pathVariables parameters:(NSDictionary *)parameters data:(id<WebApiResource>)data
		  finished:(void (^)(id<WebApiResponse>, NSError *))callback {
	[self requestAPI:name withPathVariables:pathVariables parameters:parameters data:data queue:dispatch_get_main_queue() progress:nil finished:callback];
}

- (void)requestAPI:(NSString *)name withPathVariables:(id)pathVariables parameters:(id)parameters data:(id<WebApiResource>)data
			 queue:(dispatch_queue_t)callbackQueue
		  progress:(nullable WebApiClientRequestProgressBlock)progressCallback
		  finished:(nonnull void (^)(id<WebApiResponse> _Nonnull, NSError * _Nullable))callback {
	// extending classes probably want to do something useful here
}

- (nullable id<WebApiResponse>)blockingRequestAPI:(NSString *)name
								withPathVariables:(nullable id)pathVariables
									   parameters:(nullable id)parameters
											 data:(nullable id<WebApiResource>)data
									  maximumWait:(const NSTimeInterval)maximumWait
											error:(NSError **)error {
	
	// results
	__block id<WebApiResponse> clientResponse = nil;
	__block NSError *clientError = nil;
	
	// we're going to block the calling thread here, for up to maximumWait seconds
	NSCondition *condition = [NSCondition new];
	[condition lock];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	__block BOOL finished = NO;
	[self requestAPI:name withPathVariables:pathVariables parameters:parameters data:data queue:bgQueue progress:nil finished:^(id<WebApiResponse>  _Nonnull response, NSError * _Nullable error) {
		[condition lock];
		finished = YES;
		clientResponse = response;
		clientError = error;
		[condition signal];
		[condition unlock];
	}];
	
	// block and wait for our response now...
	BOOL timeout = NO;
	if ( maximumWait > 0 ) {
		NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:maximumWait];
		while ( !finished && [timeoutDate timeIntervalSinceNow] > 0 ) {
			timeout = ![condition waitUntilDate:timeoutDate];
		}
	} else {
		while ( !finished ) {
			[condition wait];
		}
	}
	[condition unlock];
	
	if ( timeout && !clientError ) {
		log4Warn(@"No response returned from route %@ within %0.1f seconds", name, maximumWait);
		NSString *message = [NSString stringWithFormat:[@"{web.api.responseTimeout}" localizedString], @(maximumWait)];
		clientError = [NSError errorWithDomain:WebApiClientErrorDomain code:WebApiClientErrorResponseTimeout userInfo:
					   @{@"name" : name, NSLocalizedDescriptionKey : message }];
	}
	
	if ( error && clientError ) {
		*error = clientError;
	}
	return clientResponse;
}

- (void)addRequestHeadersToRequest:(NSMutableURLRequest *)request forRoute:(id<WebApiRoute>)route {
	NSDictionary<NSString *, NSString *> *routeHeaders = route.requestHeaders;
	[self.globalHTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
		if ( !routeHeaders[key] ) {
			[request addValue:obj forHTTPHeaderField:key];
		}
	}];
	[routeHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
		[request addValue:obj forHTTPHeaderField:key];
	}];
}

- (void)addAuthorizationHeadersToRequest:(NSMutableURLRequest *)request forRoute:(id<WebApiRoute>)route {
	if ( self.appApiKey ) {
		[request setValue:self.appApiKey forHTTPHeaderField:self.appApiKeyHTTPHeaderName];
	}
	if ( self.appId ) {
		[request setValue:self.appId forHTTPHeaderField:self.appIdHTTPHeaderName];
	}
	if ( self.authorizationProvider ) {
		[self.authorizationProvider configureAuthorizationForRoute:route request:request];
	}
}

- (NSArray<NSHTTPCookie *> *)cookiesForAPI:(nullable NSString *)name inCookieStorage:(nullable NSHTTPCookieStorage *)cookieJar {
	NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:8];
	NSURL *cookieURL = ([name length] ? [self URLForRoute:[self routeForName:name error:nil] pathVariables:nil parameters:nil error:nil] : baseApiURL);
	NSHTTPCookieStorage *jar = (cookieJar ? cookieJar : [NSHTTPCookieStorage sharedHTTPCookieStorage]);
	if ( cookieURL ) {
		NSArray *found = [jar cookiesForURL:baseApiURL];
		if ( found ) {
			[result addObjectsFromArray:found];
		}
	}
	return result;
}

@end
