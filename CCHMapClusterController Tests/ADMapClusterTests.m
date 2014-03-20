//
//  CCHMapTreeTests.m
//  CCHMapClusterController
//
//  Copyright (C) 2013 Claus Höfele
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "ADMapCluster.h"
#import "CCHMapClusterControllerUtils.h"

#import <XCTest/XCTest.h>

@interface Annotation : MKPointAnnotation
@property (nonatomic, copy) NSString *id;
@end

@implementation Annotation
- (BOOL)isEqual:(id)other
{
    BOOL isEqual;
    
    if (other == self) {
        isEqual = YES;
    } else if (!other || ![other isKindOfClass:self.class]) {
        isEqual = NO;
    } else {
        isEqual = [self isEqualToStolperstein:other];
    }
    
    return isEqual;
}

- (BOOL)isEqualToStolperstein:(Annotation *)annotation
{
    return [self.id isEqualToString:annotation.id];
}

- (NSUInteger)hash
{
    return self.id.hash;
}
@end

@interface ADMapClusterTests : XCTestCase

@property (nonatomic, strong) ADMapCluster *mapCluster;

@end

@implementation ADMapClusterTests

- (void)setUp
{
    [super setUp];
    
    self.mapCluster = [ADMapCluster rootClusterForAnnotations:[NSSet set] gamma:1 clusterTitle:@"Test" showSubtitle:NO];
}

- (void)testDealloc
{
    ADMapCluster *mapCluster = [ADMapCluster rootClusterForAnnotations:[NSSet set] gamma:1 clusterTitle:@"Test" showSubtitle:NO];
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = CLLocationCoordinate2DMake(52, 13);
    [mapCluster addAnnotations:[NSSet setWithObject:annotation]];
}

- (void)testAnnotationsInMapRectContainsRetain
{
    NSString *title = @"title";
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(52, 13);
    @autoreleasepool {
        MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
        annotation.coordinate = coordinate;
        annotation.title = title;
        
        [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation]]];
    }
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    if (annotations.count > 0) {
        XCTAssertEqualObjects(title, [[annotations anyObject] title]);
    }
}

- (void)testAnnotationsInMapRectEmpty
{
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)0);

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(CLLocationCoordinate2DMake(52, 13), 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)0);
}

- (void)testAnnotationsInMapRectContains
{
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = CLLocationCoordinate2DMake(52, 13);
    [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(annotation.coordinate, 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    if (annotations.count > 0) {
        XCTAssertEqual(annotation, [annotations anyObject]);
    }
}

- (void)testAnnotationsInMapRectContainsSamePosition
{
    MKPointAnnotation *annotation0 = [[MKPointAnnotation alloc] init];
    annotation0.coordinate = CLLocationCoordinate2DMake(52, 13);
    MKPointAnnotation *annotation1 = [[MKPointAnnotation alloc] init];
    annotation1.coordinate = annotation0.coordinate;
    [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation0, annotation1]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)2);
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(annotation0.coordinate, 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)2);
    if (annotations.count > 0) {
        XCTAssertTrue([annotations containsObject:annotation0]);
        XCTAssertTrue([annotations containsObject:annotation1]);
    }
}

- (void)testAnnotationsInMapRectDoesNotContain
{
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = CLLocationCoordinate2DMake(52, 13);
    [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);
    
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(50, 10);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)0);
}

- (void)testAnnotationsInMapRectContainsSome
{
    MKPointAnnotation *annotation0 = [[MKPointAnnotation alloc] init];
    annotation0.coordinate = CLLocationCoordinate2DMake(52, 13);
    MKPointAnnotation *annotation1 = [[MKPointAnnotation alloc] init];
    annotation1.coordinate = CLLocationCoordinate2DMake(50, 10);
    [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation0, annotation1]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)2);
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(annotation1.coordinate, 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    if (annotations.count > 0) {
        XCTAssertEqual(annotation1, annotations.anyObject);
    }
}

- (void)testRemoveAnnotations
{
    MKPointAnnotation *annotation0 = [[MKPointAnnotation alloc] init];
    annotation0.coordinate = CLLocationCoordinate2DMake(52, 13);
    MKPointAnnotation *annotation1 = [[MKPointAnnotation alloc] init];
    annotation1.coordinate = CLLocationCoordinate2DMake(50, 10);
    MKPointAnnotation *annotation2 = [[MKPointAnnotation alloc] init];
    annotation2.coordinate = annotation1.coordinate;
    [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation0, annotation1, annotation2]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)3);

    [self.mapCluster removeAnnotations:[NSSet setWithArray:@[annotation0]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)2);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(annotation0.coordinate, 1000, 1000);
    MKMapRect mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    NSSet *annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)0);

    [self.mapCluster removeAnnotations:[NSSet setWithArray:@[annotation2]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);
    region = MKCoordinateRegionMakeWithDistance(annotation1.coordinate, 1000, 1000);
    mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    if (annotations.count > 0) {
        XCTAssertEqual(annotation1, annotations.anyObject);
    }

    [self.mapCluster removeAnnotations:[NSSet setWithArray:@[annotation1]]];
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)0);
    region = MKCoordinateRegionMakeWithDistance(annotation1.coordinate, 1000, 1000);
    mapRect = CCHMapClusterControllerMapRectForCoordinateRegion(region);
    annotations = [self.mapCluster annotationsInMapRect:mapRect];
    XCTAssertEqual(annotations.count, (NSUInteger)0);
}

- (void)testAddRemoveAnnotationsUpdated
{
    // Add once
    Annotation *annotation0 = [[Annotation alloc] init];
    annotation0.id = @"123";
    BOOL updated = [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation0]]];
    XCTAssertTrue(updated);
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);
    
    // Add again
    updated = [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation0]]];
    XCTAssertFalse(updated);
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);
    
    // Add equal
    Annotation *annotation1 = [[Annotation alloc] init];
    annotation1.id = annotation0.id;
    updated = [self.mapCluster addAnnotations:[NSSet setWithArray:@[annotation1]]];
    XCTAssertFalse(updated);
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)1);
    
    // Remove equal
    updated = [self.mapCluster removeAnnotations:[NSSet setWithArray:@[annotation1]]];
    XCTAssertTrue(updated);
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)0);
    
    // Remove again
    updated = [self.mapCluster removeAnnotations:[NSSet setWithArray:@[annotation0]]];
    XCTAssertFalse(updated);
    XCTAssertEqual(self.mapCluster.numberOfChildren, (NSUInteger)0);
}

@end
