//
//  AFNetworkingWebApiClient.m
//  WebApiClient
//
//  Created by Matt on 12/08/15.
//  Copyright (c) 2015 Blue Rocket. Distributable under the terms of the Apache License, Version 2.0.
//

#import "AFNetworkingWebApiClient.h"

#import <AFNetworking/AFHTTPSessionManager.h>
#import <AFgzipRequestSerializer/AFgzipRequestSerializer.h>
#import <BRCocoaLumberjack/BRCocoaLumberjack.h>
#import <BREnvironment/BREnvironment.h>
#import "DataWebApiResource.h"
#import "FileWebApiResource.h"
#import "WebApiDataMapper.h"
#import "WebApiResource.h"

@implementation AFNetworkingWebApiClient {
	AFHTTPSessionManager *manager;
	NSLock *lock;
	
	// a mapping of NSURLSessionTask identifiers to associated WebApiRoute objects, to support notifications
	NSMutableDictionary<NSNumber *, id<WebApiRoute>> *tasksToRoutes;
	
	// a mapping of NSURLSessionTask identifiers to associated NSProgress objects, to support notifications
	NSMutableDictionary<NSNumber *, NSProgress *> *tasksToProgress;
	
	// to support callbacks on arbitrary queues, our manager must NOT use the main thread
	dispatch_queue_t completionQueue;
}

- (id)initWithEnvironment:(BREnvironment *)environment {
	if ( (self = [super initWithEnvironment:environment]) ) {
		tasksToRoutes = [[NSMutableDictionary alloc] initWithCapacity:8];
		tasksToProgress = [[NSMutableDictionary alloc] initWithCapacity:8];
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
	[manager setTaskDidSendBodyDataBlock:[self taskDidSendBodyDataBlock]];
	[manager setDataTaskDidBecomeDownloadTaskBlock:[self dataTaskDidBecomeDownloadTaskBlock]];
	[manager setDataTaskDidReceiveDataBlock:[self dataTaskDidReceiveDataBlock]];
	[manager setDownloadTaskDidWriteDataBlock:[self downloadTaskDidWriteDataBlock]];
	
	// let us accept any and all responses!
	AFCompoundResponseSerializer *compoundResponseSerializer = [AFCompoundResponseSerializer compoundSerializerWithResponseSerializers:
																@[[AFJSONResponseSerializer serializer],
																  [AFImageResponseSerializer serializer],
																  [AFHTTPResponseSerializer serializer]]];
	manager.responseSerializer = compoundResponseSerializer;
}

- (void (^)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend))taskDidSendBodyDataBlock {
	return ^(NSURLSession * _Nonnull session, NSURLSessionTask * _Nonnull task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
		id<WebApiRoute> route;
		NSProgress *progress = [self progressForTask:task];
		if ( !progress ) {
			route = [self routeForTask:task];
			if ( route ) {
				NSProgress *prog = [NSProgress progressWithTotalUnitCount:totalBytesExpectedToSend];
				prog.completedUnitCount = totalBytesSent;
				[prog setUserInfoObject:route forKey:NSStringFromProtocol(@protocol(WebApiRoute))];
				[self setRoute:route progress:progress forTask:task];
				progress = prog;
			}
		} else {
			route = progress.userInfo[NSStringFromProtocol(@protocol(WebApiRoute))];
		}
		if ( route && progress ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[NSNotificationCenter defaultCenter] postNotificationName:WebApiClientRequestDidProgressNotification object:route
																  userInfo:@{WebApiClientURLRequestNotificationKey : task.originalRequest,
																			 WebApiClientProgressNotificationKey : progress}];
			});
		}
	};
}

- (void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask))dataTaskDidBecomeDownloadTaskBlock {
	return ^(NSURLSession * _Nonnull session, NSURLSessionDataTask * _Nonnull dataTask, NSURLSessionDownloadTask * _Nonnull downloadTask) {
		id<WebApiRoute> route = [self routeForTask:dataTask];
		[self setRoute:route progress:nil forTask:downloadTask];
		[self setRoute:nil progress:nil forTask:dataTask];
	};
}

- (void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data))dataTaskDidReceiveDataBlock {
	return ^(NSURLSession * _Nonnull session, NSURLSessionDataTask * _Nonnull task, NSData * _Nonnull data) {
		id<WebApiRoute> route;
		NSProgress *progress = [self progressForTask:task];
		if ( !progress ) {
			route = [self routeForTask:task];
			if ( route ) {
				NSProgress *prog = [NSProgress progressWithTotalUnitCount:task.countOfBytesExpectedToReceive];
				[prog setUserInfoObject:route forKey:NSStringFromProtocol(@protocol(WebApiRoute))];
				[self setRoute:route progress:progress forTask:task];
				progress = prog;
			}
		} else {
			route = progress.userInfo[NSStringFromProtocol(@protocol(WebApiRoute))];
		}
		progress.totalUnitCount = task.countOfBytesExpectedToReceive;
		progress.completedUnitCount = task.countOfBytesReceived;
		if ( route && progress ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[NSNotificationCenter defaultCenter] postNotificationName:WebApiClientResponseDidProgressNotification object:route
																  userInfo:@{WebApiClientURLRequestNotificationKey : task.originalRequest,
																			 WebApiClientProgressNotificationKey : progress}];
			});
		}
	};
}

- (void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite))downloadTaskDidWriteDataBlock {
	return ^(NSURLSession * _Nonnull session, NSURLSessionDownloadTask * _Nonnull task, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
		id<WebApiRoute> route;
		NSProgress *progress = [self progressForTask:task];
		if ( !progress ) {
			route = [self routeForTask:task];
			if ( route ) {
				NSProgress *prog = [NSProgress progressWithTotalUnitCount:task.countOfBytesExpectedToReceive];
				[prog setUserInfoObject:route forKey:NSStringFromProtocol(@protocol(WebApiRoute))];
				[self setRoute:route progress:progress forTask:task];
				progress = prog;
			}
		} else {
			route = progress.userInfo[NSStringFromProtocol(@protocol(WebApiRoute))];
		}
		progress.totalUnitCount = totalBytesExpectedToWrite;
		progress.completedUnitCount = totalBytesWritten;
		if ( route && progress ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[NSNotificationCenter defaultCenter] postNotificationName:WebApiClientResponseDidProgressNotification object:route
																  userInfo:@{WebApiClientURLRequestNotificationKey : task.originalRequest,
																			 WebApiClientProgressNotificationKey : progress}];
			});
		}
	};
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
		case WebApiSerializationNone:
		case WebApiSerializationURL:
			ser = [AFHTTPRequestSerializer serializer];
			break;
		
		case WebApiSerializationJSON:
			ser = [AFJSONRequestSerializer serializer];
			[ser setValue:@"application/json" forHTTPHeaderField:@"Accept"];
			break;
	}
	
	if ( ser && route.gzip ) {
		ser = [AFgzipRequestSerializer serializerWithSerializer:ser];
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

- (NSProgress *)progressForActiveTaskIdentifier:(NSUInteger)identifier {
	NSProgress *progress = nil;
	[lock lock];
	progress = tasksToProgress[@(identifier)];
	[lock unlock];
	return progress;
}

- (id<WebApiRoute>)routeForTask:(NSURLSessionTask *)task {
	return [self routeForActiveTaskIdentifier:task.taskIdentifier];
}

- (NSProgress *)progressForTask:(NSURLSessionTask *)task {
	return [self progressForActiveTaskIdentifier:task.taskIdentifier];
}

- (void)setRoute:(id<WebApiRoute>)route progress:(nullable NSProgress *)progress forTask:(NSURLSessionTask *)task {
	[lock lock];
	NSNumber *key = @(task.taskIdentifier);
	if ( route == nil ) {
		[tasksToRoutes removeObjectForKey:key];
		[tasksToProgress removeObjectForKey:key];
	} else {
		tasksToRoutes[key] = route;
		if ( progress ) {
			tasksToProgress[key] = progress;
		}
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
	[self setRoute:nil progress:nil forTask:task];
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
		id<WebApiResource> reqData = data;
		BOOL uploadStream = NO;
		if ( parameters ) {
			if ( dataMapper ) {
				id encoded = [dataMapper performEncodingWithObject:parameters route:route error:&error];
				if ( !encoded ) {
					return doCallback(nil, error);
				}
				if ( [encoded isKindOfClass:[NSDictionary class]] ) {
					reqParameters = encoded;
				} else if ( [encoded conformsToProtocol:@protocol(WebApiResource)] ) {
					reqData = encoded;
				} else if ( [encoded isKindOfClass:[NSData class]] ) {
					reqData = [[DataWebApiResource alloc] initWithData:encoded name:@"data" fileName:@"data.dat" MIMEType:@"application/octet-stream"];
				}
			} else {
				reqParameters = [self dictionaryForParametersObject:parameters];
			}
		}
		NSMutableURLRequest *req = nil;
		if ( ![route.method isEqualToString:@"GET"] && ![route.method isEqualToString:@"HEAD"] && (route.serialization == WebApiSerializationForm || (route.serialization != WebApiSerializationNone && reqData != nil)) ) {
			req = [ser multipartFormRequestWithMethod:route.method URLString:[url absoluteString] parameters:reqParameters constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
				if ( reqData ) {
					[formData appendPartWithInputStream:reqData.inputStream name:reqData.name fileName:reqData.fileName length:reqData.length mimeType:reqData.MIMEType];
				}
			} error:&error];
		} else {
			req = [ser requestWithMethod:route.method URLString:[url absoluteString] parameters:reqParameters error:&error];
			if ( reqData != nil ) {
				uploadStream = YES;
				req.HTTPBodyStream = reqData.inputStream;
				[req setValue:reqData.MIMEType forHTTPHeaderField:@"Content-Type"];
				[req setValue:[NSString stringWithFormat:@"%llu", (unsigned long long)reqData.length] forHTTPHeaderField:@"Content-Length"];
				if ( reqData.MD5 ) {
					[req setValue:reqData.MD5 forHTTPHeaderField:@"Content-MD5"];
				}
			}
		}
		
		[self addRequestHeadersToRequest:req forRoute:route];
		[self addAuthorizationHeadersToRequest:req forRoute:route];
		
		void (^responseHandler)(NSURLResponse *, id, NSError *) = ^(NSURLResponse *response, id responseObject, NSError *error) {
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
			
			// with compound serializer, empty response returned as NSData, but we want that as nil
			if ( [responseObject isKindOfClass:[NSData class]]  && [responseObject length] < 1 ) {
				responseObject = nil;
			}
			
			if ( [responseObject isKindOfClass:[NSURL class]] ) {
				NSURL *pointerURL = responseObject;
				if ( [pointerURL isFileURL] ) {
					responseObject = [[FileWebApiResource alloc] initWithURL:pointerURL name:[pointerURL lastPathComponent] MIMEType:response.MIMEType];
				}
				handleResponse(responseObject, error);
			} else if ( dataMapper && responseObject && !error ) {
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					NSError *decodeError = nil;
					id decoded = [dataMapper performMappingWithSourceObject:responseObject route:route error:&decodeError];
					handleResponse(decoded, decodeError);
				});
			} else {
				handleResponse(responseObject, error);
			}
		};
		
		NSProgress *progress = nil;
		NSURLSessionTask *task;
		if ( uploadStream ) {
			task = [manager uploadTaskWithStreamedRequest:req progress:&progress completionHandler:responseHandler];
			progress.totalUnitCount = reqData.length;
			[progress setUserInfoObject:route forKey:NSStringFromProtocol(@protocol(WebApiRoute))];
		} else if ( route.saveAsResource ) {
			task = [manager downloadTaskWithRequest:req progress:&progress destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
				NSString *fileName = [response suggestedFilename];
				if ( [fileName length] < 1 ) {
					fileName = @"download.dat";
				}
				NSString *tempFilePath = [[self class] temporaryPathWithPrefix:[fileName stringByDeletingPathExtension] suffix:[@"." stringByAppendingString:[fileName pathExtension]]];
				
				// remove our temp file, because AFNetworking will be moving the download file to there
				[[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];
				
				return [NSURL fileURLWithPath:tempFilePath];
			} completionHandler:responseHandler];
		} else {
			task = [manager dataTaskWithRequest:req completionHandler:responseHandler];
		}
		[self setRoute:route progress:progress forTask:task];
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:WebApiClientRequestWillBeginNotification object:route
															  userInfo:@{WebApiClientURLRequestNotificationKey : req}];
		});
		[task resume];
	});
}

+ (NSString *)temporaryPathWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
	NSString *nameTemplate = [NSString stringWithFormat:@"%@.XXXXXX%@", prefix, suffix];
	NSString *tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:nameTemplate];
	const char *tempFileTemplateCString = [tempFileTemplate fileSystemRepresentation];
	char *tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
	strcpy(tempFileNameCString, tempFileTemplateCString);
	int fileDescriptor = mkstemps(tempFileNameCString, (int)[suffix length]);
	if ( fileDescriptor == -1 ) {
		log4Error(@"Failed to create temp file %s", tempFileNameCString);
		free(tempFileNameCString);
		return nil;
	}
	
	NSString * result = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString
																					length:strlen(tempFileNameCString)];
	free(tempFileNameCString);
	return result;
}

@end
