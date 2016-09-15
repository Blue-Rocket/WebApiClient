//
//  RestKitWebApiDataMapperTests.m
//  WebApiClient
//
//  Created by Matt on 15/09/16.
//  Copyright © 2016 Blue Rocket, Inc. All rights reserved.
//

#import "BaseTestingSupport.h"

#import <RestKit/ObjectMapping.h>
#import "RestKitWebApiDataMapper.h"
#import "WebApiClient.h"

@interface TestRestKitMappingObject : NSObject
@property (nonatomic, strong) NSString *name;
@end

@implementation TestRestKitMappingObject
@end

@interface RestKitWebApiDataMapperTests : BaseTestingSupport

@end

@implementation RestKitWebApiDataMapperTests {
	RestKitWebApiDataMapper *mapper;
}

- (void)setUp {
	[super setUp];
	mapper = [RestKitWebApiDataMapper new];
}

- (RKObjectMapping *)testMapping {
	RKObjectMapping* mapping = [RKObjectMapping mappingForClass:[TestRestKitMappingObject class]];
	[mapping addAttributeMappingsFromArray:@[@"name"]];
	return mapping;
}

- (void)testResponseMapping {
	[mapper registerResponseObjectMapping:[self testMapping] forRouteName:@"test"];
	NSError *error = nil;
	id result = [mapper performMappingWithSourceObject:@{@"name" : @"foo"} route:@{@"name" : @"test"} error:&error];
	assertThat(result, isA([TestRestKitMappingObject class]));
	assertThat([result name], equalTo(@"foo"));
}

- (void)testResponseMappingWithRoot {
	[mapper registerResponseObjectMapping:[self testMapping] forRouteName:@"test"];
	NSError *error = nil;
	id result = [mapper performMappingWithSourceObject:@{@"tester" : @{@"name" : @"foo"}} route:@{@"name" : @"test", @"dataMapperResponseRootKeyPath" : @"tester"} error:&error];
	assertThat(result, isA([TestRestKitMappingObject class]));
	assertThat([result name], equalTo(@"foo"));
}

- (void)testResponseMappingWithMissingRoot {
	[mapper registerResponseObjectMapping:[self testMapping] forRouteName:@"test"];
	NSError *error = nil;
	id result = [mapper performMappingWithSourceObject:@{@"name" : @"foo"} route:@{@"name" : @"test", @"dataMapperResponseRootKeyPath" : @"tester"} error:&error];
	assertThat(result, nilValue());
	assertThatInteger(error.code, equalToInteger(RestKitWebApiDataMapperErrorResponseRootKeyPathMissing));
}

@end
