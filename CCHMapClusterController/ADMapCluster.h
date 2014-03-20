//
//  ADMapCluster.h
//  ADClusterMapView
//
//  Created by Patrick Nollet on 27/06/11.
//  Copyright 2011 Applidium. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

@interface ADMapCluster : NSObject {
    CLLocationCoordinate2D _clusterCoordinate;
    ADMapCluster *         _leftChild;
    ADMapCluster *         _rightChild;
    MKMapRect              _mapRect;
    id<MKAnnotation>       _annotation;
    NSString *             _clusterTitle;
    NSInteger              _depth;
}
@property (nonatomic) CLLocationCoordinate2D clusterCoordinate;
@property (nonatomic, strong, readonly) NSString * title;
@property (nonatomic, strong, readonly) NSString * subtitle;
@property (nonatomic, readonly) double gamma;
@property (nonatomic, strong) id<MKAnnotation> annotation;
@property (nonatomic, readonly) NSSet * originalAnnotations;
@property (nonatomic, readonly) NSInteger depth;
@property (nonatomic, assign) BOOL showSubtitle;
@property (nonatomic, readonly) NSUInteger numberOfChildren;

- (id)initWithAnnotations:(NSSet *)annotations atDepth:(NSInteger)depth inMapRect:(MKMapRect)mapRect gamma:(double)gamma clusterTitle:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle;
+ (ADMapCluster *)rootClusterForAnnotations:(NSSet *)annotations gamma:(double)gamma clusterTitle:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle;
- (BOOL)addAnnotations:(NSSet*)annotations;
- (BOOL)removeAnnotations:(NSSet*)annotations;
- (NSSet *)find:(NSInteger)N childrenInMapRect:(MKMapRect)mapRect;
- (NSSet *)findChildrenInMapRect:(MKMapRect)mapRect minCellSize:(double)size;
- (NSSet *)annotationsInMapRect:(MKMapRect)mapRect;
- (NSArray *)children;
- (BOOL)isAncestorOf:(ADMapCluster *)mapCluster;
- (BOOL)isRootClusterForAnnotation:(id<MKAnnotation>)annotation;
- (NSArray *)namesOfChildren;
@end
