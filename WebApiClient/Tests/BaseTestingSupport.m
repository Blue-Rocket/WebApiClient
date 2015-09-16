//
//  BaseTestingSupport.m
//  WebApiClient
//
//  Created by Matt on 18/08/15.
//  Copyright (c) 2015 Blue Rocket. Distributable under the terms of the Apache License, Version 2.0.
//

#import "BaseTestingSupport.h"

#import <BREnvironment/BREnvironment.h>

static NSBundle *bundle;
static BREnvironment *testEnvironment;

@interface ConfigEnvironmentProvider : NSObject <BREnvironmentProvider>
@property (nonatomic, strong) NSBundle *bundle;
@end

@implementation ConfigEnvironmentProvider

- (id)objectForKeyedSubscript:(id)key {
	NSDictionary *dict = [self config];
	// treat key as keyPath!
	return [dict valueForKeyPath:key];
}

- (NSDictionary *)config {
	NSString *path = [self.bundle pathForResource:@"config" ofType:@"json"];
	if ( !path ) {
		return nil;
	}
	NSData *data = [[NSData alloc] initWithContentsOfFile:path];
	NSError *error = nil;
	id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if ( error ) {
		NSLog(@"Error loading config.json: %@", [error localizedDescription]);
	}
	return result;
}

@end

@implementation BaseTestingSupport {
	ConfigEnvironmentProvider *provider;
}

- (NSBundle *)bundle {
	return bundle;
}

- (BREnvironment *)testEnvironment {
	return testEnvironment;
}

+ (void)setUp {
	bundle = [[NSBundle alloc] initWithURL:[NSBundle bundleForClass:[self class]].bundleURL];
	[BREnvironment setSharedEnvironmentBundle:bundle];
	testEnvironment = [BREnvironment sharedEnvironment];
}

- (void)setUp {
	[super setUp];
	// register a config.json provider from the unit test bundle
	provider = [[ConfigEnvironmentProvider alloc] init];
	provider.bundle = bundle;
	[BREnvironment registerEnvironmentProvider:provider];
}

- (void)tearDown {
	[BREnvironment unregisterEnvironmentProvider:provider];
	[super tearDown];
}

@end
