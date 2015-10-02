//
//  AFNetworkingWebApiClient.m
//  WebApiClient
//
//  Created by Matt on 12/08/15.
//  Copyright (c) 2015 Blue Rocket. Distributable under the terms of the Apache License, Version 2.0.
//

#import "AFNetworkingWebApiClient.h"

#import <AFNetworking/AFHTTPSessionManager.h>
#import <BRCocoaLumberjack/BRCocoaLumberjack.h>
#import <BREnvironment/BREnvironment.h>
#import <BRLocalize/BRLocalize.h>
#import "WebApiDataMapper.h"
#import "WebApiResource.h"

@implementation AFNetworkingWebApiClient {
	AFHTTPSessionManager *manager;
	NSLock *lock;
	// a mapping of NSURLSessionTask identifiers to associated WebApiRoute objects, to support notifications
	NSMutableDictionary *tasksToRoutes;
	
	// to support callbacks on arbitrary queues, our manager must NOT use the main thread
	dispatch_queue_t completionQueue;
}

- (id)initWithEnvironment:(BREnvironment *)environment {
	if ( (self = [super initWithEnvironment:environment]) ) {
		tasksToRoutes = [[NSMutableDictionary alloc] initWithCapacity:8];
		lock = [[NSLock alloc] init];
		lock.name = @"AFNetworkingApiClientLock";
		[self initializeURLSessionManager];
	}
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(taskDidResume:) name:AFNetworkingTaskDidResumeNotification object:nil];
	[center addObserver:self selector:@selector(taskDidComplete:) name:AFNetworkingTaskDidCompleteNotification object:nil];
	return self;
}

- (void)dealloc {
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center removeObserver:self name:AFNetworkingTaskDidResumeNotification object:nil];
	[center removeObserver:self name:AFNetworkingTaskDidCompleteNotification object:nil];
}

- (void)initializeURLSessionManager {
	if ( manager ) {
		[manager invalidateSessionCancelingTasks:YES];
	}
	NSURLSessionConfiguration *sessConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
	AFHTTPSessionManager *mgr = [[AFHTTPSessionManager alloc] initWithBaseURL:[self baseApiURL] sessionConfiguration:sessConfig];
	manager = mgr;
	if ( completionQueue ) {
		completionQueue = nil;
	}
	NSString *callbackQueueName = [@"WebApiClient-" stringByAppendingString:[[self baseApiURL] absoluteString]];
	completionQueue = dispatch_queue_create([callbackQueueName UTF8String], DISPATCH_QUEUE_CONCURRENT);
	manager.completionQueue = completionQueue;
}

- (AFHTTPRequestSerializer *)requestSerializationForRoute:(id<WebApiRoute>)route URL:(NSURL *)url parameters:(id)parameters data:(id)data error:(NSError * __autoreleasing *)error {
	WebApiSerialization type = route.serialization;
	if ( data != nil && (type != WebApiSerializationForm || type != WebApiSerializationNone) ) {
		// for data uploads, need to serialize into the body
		type = WebApiSerializationForm;
	}
	AFHTTPRequestSerializer *ser;
	switch ( type ) {
		case WebApiSerializationForm:
		case WebApiSerializationURL:
			ser = [AFHTTPRequestSerializer serializer];
			break;
		case WebApiSerializationJSON:
			ser = [AFJSONRequestSerializer serializer];
			[ser setValue:@"application/json" forHTTPHeaderField:@"Accept"];
			break;
		case WebApiSerializationNone:
			ser = nil;
			break;
			
	}
	return ser;
}

- (NSArray *)activeTaskIdentifiers {
	NSArray *idents = nil;
	[lock lock];
	idents = [tasksToRoutes allKeys];
	[lock unlock];
	return idents;
}

- (id<WebApiRoute>)routeForActiveTaskIdentifier:(NSUInteger)identifier {
	id<WebApiRoute> route = nil;
	[lock lock];
	route = tasksToRoutes[@(identifier)];
	[lock unlock];
	return route;
}

- (id<WebApiRoute>)routeForTask:(NSURLSessionTask *)task {
	return [self routeForActiveTaskIdentifier:task.taskIdentifier];
}

- (void)setRoute:(id<WebApiRoute>)route forTask:(NSURLSessionTask *)task {
	[lock lock];
	if ( route == nil ) {
		[tasksToRoutes removeObjectForKey:@(task.taskIdentifier)];
	} else {
		tasksToRoutes[@(task.taskIdentifier)] = route;
	}
	[lock unlock];
}

#pragma mark - Notifications

- (void)taskDidResume:(NSNotification *)note {
	NSURLSessionTask *task = note.object;
	id<WebApiRoute> route = [self routeForTask:task];
	if ( route ) {
		[[NSNotificationCenter defaultCenter] postNotificationName:WebApiClientRequestDidBeginNotification object:route
														  userInfo:@{WebApiClientURLRequestNotificationKey : task.originalRequest}];
	}
}

- (void)taskDidComplete:(NSNotification *)notification {
	NSURLSessionTask *task = notification.object;
	id<WebApiRoute> route = [self routeForTask:task];
	if ( !route ) {
		return;
	}
	[self setRoute:nil forTask:task];
	NSError *error = notification.userInfo[AFNetworkingTaskDidCompleteErrorKey];
	NSNotification *note = nil;
	if ( error ) {
		NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithCapacity:4];
		info[NSUnderlyingErrorKey] = error;
		if ( task.originalRequest ) {
			info[WebApiClientURLRequestNotificationKey] = task.originalRequest;
		}
		if ( task.response ) {
			info[WebApiClientURLResponseNotificationKey] = task.response;
		}
		note = [[NSNotification alloc] initWithName:WebApiClientRequestDidFailNotification object:route
										   userInfo:info];
	} else {
		note = [[NSNotification alloc] initWithName:WebApiClientRequestDidSucceedNotification object:route
										   userInfo:@{WebApiClientURLRequestNotificationKey : task.originalRequest,
													  WebApiClientURLResponseNotificationKey : task.response}];
	}
	if ( note ) {
		[[NSNotificationCenter defaultCenter] postNotification:note];
	}
}

#pragma mark - Public API

static void * AFNetworkingWebApiClientTaskStateContext = &AFNetworkingWebApiClientTaskStateContext;

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
	[self requestAPI:name withPathVariables:pathVariables parameters:parameters data:data queue:bgQueue finished:^(id<WebApiResponse>  _Nonnull response, NSError * _Nullable error) {
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

- (void)requestAPI:(NSString *)name withPathVariables:(id)pathVariables parameters:(id)parameters data:(id<WebApiResource>)data
		  finished:(void (^)(id<WebApiResponse>, NSError *))callback {
	[self requestAPI:name withPathVariables:pathVariables parameters:parameters data:data queue:dispatch_get_main_queue() finished:callback];
}

- (void)requestAPI:(NSString *)name
 withPathVariables:(nullable id)pathVariables
		parameters:(nullable id)parameters
			  data:(nullable id<WebApiResource>)data
			 queue:(dispatch_queue_t)callbackQueue
		  finished:(void (^)(id<WebApiResponse> response, NSError * __nullable error))callback {

	void (^doCallback)(id<WebApiResponse>, NSError *) = ^(id<WebApiResponse> response, NSError *error) {
		if ( callback ) {
			dispatch_async(callbackQueue, ^{
				callback(response, error);
			});
		}
	};

	NSError *error = nil;
	id<WebApiRoute> route = [self routeForName:name error:&error];
	if ( !route ) {
		return doCallback(nil, error);
	}
	
	// note we do NOT pass parameters to this method, because we'll let AFNetworking handle that for us later
	NSURL *url = [self URLForRoute:route pathVariables:pathVariables parameters:nil error:&error];
	if ( !url ) {
		return doCallback(nil, error);
	}
	AFHTTPRequestSerializer *ser = [self requestSerializationForRoute:route URL:url parameters:parameters data:data error:&error];
	if ( !ser ) {
		return doCallback(nil, error);
	}
	
	id<WebApiDataMapper> dataMapper = [self dataMapperForRoute:route];

	// kick out to new thread, so mapping, etc don't block UI
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSError *error = nil;
		NSDictionary *reqParameters = nil;
		id reqData = data;
		if ( parameters ) {
			if ( dataMapper ) {
				id encoded = [dataMapper performEncodingWithObject:parameters route:route error:&error];
				if ( !encoded ) {
					return doCallback(nil, error);
				}
				if ( [encoded isKindOfClass:[NSDictionary class]] ) {
					reqParameters = encoded;
				} else {
					reqData = encoded;
				}
			} else {
				reqParameters = [self dictionaryForParametersObject:parameters];
			}
		}
		NSMutableURLRequest *req = nil;
		if ( route.serialization == WebApiSerializationForm || (route.serialization != WebApiSerializationNone && data != nil) ) {
			req = [ser multipartFormRequestWithMethod:route.method URLString:[url absoluteString] parameters:reqParameters constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
				if ( data ) {
					[formData appendPartWithInputStream:data.inputStream name:data.name fileName:data.fileName length:data.length mimeType:data.MIMEType];
				}
			} error:&error];
		} else {
			req = [ser requestWithMethod:route.method URLString:[url absoluteString] parameters:reqParameters error:&error];
		}
		
		[self addAuthorizationHeadersToRequest:req forRoute:route];
		
		__block NSURLSessionDataTask *task = [manager dataTaskWithRequest:req completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
			NSMutableDictionary *apiResponse = [[NSMutableDictionary alloc] initWithCapacity:4];
			apiResponse.routeName = name;
			if ( [response isKindOfClass:[NSHTTPURLResponse class]] ) {
				NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
				apiResponse.statusCode = httpResponse.statusCode;
				apiResponse.responseHeaders = httpResponse.allHeaderFields;
			}
			void (^handleResponse)(id, NSError *) = ^(id finalResponseObject, NSError *finalError) {
				apiResponse.responseObject = finalResponseObject;
				doCallback(apiResponse, finalError);
			};
			if ( dataMapper && responseObject && !error ) {
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					NSError *decodeError = nil;
					id decoded = [dataMapper performMappingWithSourceObject:responseObject route:route error:&decodeError];
					dispatch_async(dispatch_get_main_queue(), ^{
						handleResponse(decoded, decodeError);
					});
				});
			} else {
				handleResponse(responseObject, error);
			}
		}];
		[self setRoute:route forTask:task];
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:WebApiClientRequestWillBeginNotification object:route
															  userInfo:@{WebApiClientURLRequestNotificationKey : req}];
		});
		[task resume];
	});
}

@end
