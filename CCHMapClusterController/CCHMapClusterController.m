//
//  CCHMapClusterController.m
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

// Based on https://github.com/MarcoSero/MSMapClustering by MarcoSero/WWDC 2011

#import "CCHMapClusterController.h"

#import "CCHMapClusterControllerUtils.h"
#import "CCHMapClusterAnnotation.h"
#import "CCHMapClusterControllerDelegate.h"
#import "CCHMapViewDelegateProxy.h"
#import "CCHMapClusterer.h"
#import "CCHFadeInOutMapAnimator.h"
#import "ADMapCluster.h"

#define NODE_CAPACITY 10
#define WORLD_MIN_LAT -85
#define WORLD_MAX_LAT 85
#define WORLD_MIN_LON -180
#define WORLD_MAX_LON 180

#define fequal(a, b) (fabs((a) - (b)) < __FLT_EPSILON__)

@interface CCHMapClusterController()<MKMapViewDelegate>

@property (nonatomic, strong) NSSet* allAnnotations;

@property (nonatomic, strong) ADMapCluster* rootMapCluster;
@property (nonatomic, strong) NSOperationQueue *backgroundQueue;
@property (nonatomic, strong) NSMutableArray *updateOperations;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) CCHMapViewDelegateProxy *mapViewDelegateProxy;
@property (nonatomic, strong) id<MKAnnotation> annotationToSelect;
@property (nonatomic, strong) CCHMapClusterAnnotation *mapClusterAnnotationToSelect;
@property (nonatomic, assign) MKCoordinateSpan regionSpanBeforeChange;
@property (nonatomic, assign, getter = isRegionChanging) BOOL regionChanging;
@property (nonatomic, strong) id<CCHMapClusterer> strongClusterer;
@property (nonatomic, strong) CCHMapClusterAnnotation *(^findVisibleAnnotation)(ADMapCluster* cluster, NSSet *visibleAnnotations);
@property (nonatomic, strong) id<CCHMapAnimator> strongAnimator;

@end

@implementation CCHMapClusterController

- (id)initWithMapView:(MKMapView *)mapView
{
    self = [super init];
    if (self) {
        _minMetersPerPointsForShowingClusters = 0;
        _gamma = 1.0;
        _allAnnotations = [NSSet set];
        _marginFactor = 0.5;
        _cellSize = 60;
        _mapView = mapView;
        _backgroundQueue = [[NSOperationQueue alloc] init];
        _updateOperations = [NSMutableArray array];
        
        if ([mapView.delegate isKindOfClass:CCHMapViewDelegateProxy.class]) {
            CCHMapViewDelegateProxy *delegateProxy = (CCHMapViewDelegateProxy *)mapView.delegate;
            [delegateProxy addDelegate:self];
            _mapViewDelegateProxy = delegateProxy;
        } else {
            _mapViewDelegateProxy = [[CCHMapViewDelegateProxy alloc] initWithMapView:mapView delegate:self];
        }
        
        // Keep strong reference to default instance because public property is weak
        id<CCHMapAnimator> animator = [[CCHFadeInOutMapAnimator alloc] init];
        _animator = animator;
        _strongAnimator = animator;
        
        [self setReuseExistingClusterAnnotations:YES];
    }
    
    return self;
}

- (NSSet *)annotations
{
    return self.allAnnotations;
}

- (void)setClusterer:(id<CCHMapClusterer>)clusterer
{
    _clusterer = clusterer;
    self.strongClusterer = nil;
}

- (void)setAnimator:(id<CCHMapAnimator>)animator
{
    _animator = animator;
    self.strongAnimator = nil;
}

- (void)setReuseExistingClusterAnnotations:(BOOL)reuseExistingClusterAnnotations
{
    _reuseExistingClusterAnnotations = reuseExistingClusterAnnotations;
    if (reuseExistingClusterAnnotations) {
        self.findVisibleAnnotation = ^CCHMapClusterAnnotation *(ADMapCluster *cluster, NSSet *visibleAnnotations) {

            for (CCHMapClusterAnnotation* annotation in visibleAnnotations) {
                if (!cluster.annotation && annotation.type == CCHClusterAnnotationTypeCluster && (annotation.cluster == cluster || [annotation.cluster isAncestorOf:cluster] || [cluster isAncestorOf:annotation.cluster])) {
                    return annotation;
                }
                if (cluster.annotation && annotation.type == CCHClusterAnnotationTypeLeaf && annotation.cluster == cluster) {
                    return annotation;
                }
            }
            return nil;
        };
    } else {
        self.findVisibleAnnotation = ^CCHMapClusterAnnotation *(ADMapCluster *cluster, NSSet *visibleAnnotations) {
            return nil;
        };
    }
}

- (void)sync
{
    for (NSOperation *operation in self.updateOperations) {
        [operation cancel];
    }
    [self.updateOperations removeAllObjects];
    [self.backgroundQueue waitUntilAllOperationsAreFinished];
}

- (void)addAnnotations:(NSArray *)annotations withCompletionHandler:(void (^)())completionHandler
{
    [self sync];
    
    [self.backgroundQueue addOperationWithBlock:^{
        BOOL updated;
        NSUInteger current = self.allAnnotations.count;
        NSSet* annotationsSet = [NSSet setWithArray:annotations];
        if (!self.rootMapCluster) {
            self.rootMapCluster = [ADMapCluster rootClusterForAnnotations:annotationsSet gamma:self.gamma clusterTitle:@"Test" showSubtitle:NO];
        } else {
            [self.rootMapCluster addAnnotations:annotationsSet];
        }
        self.allAnnotations = [self.allAnnotations setByAddingObjectsFromArray:annotations];
        updated = self.allAnnotations.count > current;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (updated && !self.isRegionChanging) {
                [self updateAnnotationsWithCompletionHandler:completionHandler];
            } else if (completionHandler) {
                completionHandler();
            }
        });
    }];
}

- (void)removeAnnotations:(NSArray *)annotations withCompletionHandler:(void (^)())completionHandler
{
    [self sync];
    
    [self.backgroundQueue addOperationWithBlock:^{
        BOOL updated;
        NSSet* annotationsSet = [NSSet setWithArray:annotations];
        NSUInteger current = self.allAnnotations.count;
        NSMutableSet* newSet = [self.allAnnotations mutableCopy];
        [newSet minusSet:annotationsSet];
        self.allAnnotations = [newSet copy];
        if (self.rootMapCluster) {
            [self.rootMapCluster removeAnnotations:annotationsSet];
        }
        
        updated = self.allAnnotations.count < current;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (updated && !self.isRegionChanging) {
                [self updateAnnotationsWithCompletionHandler:completionHandler];
            } else if (completionHandler) {
                completionHandler();
            }
        });
    }];
}

- (void)updateAnnotationsWithCompletionHandler:(void (^)())completionHandler
{
    [self sync];
    
    // World size is multiple of cell size so that cells wrap around at the 180th meridian
    double cellSize = CCHMapClusterControllerMapLengthForLength(_mapView, _mapView.superview, _cellSize);
    
    // Expand map rect and align to cell size to avoid popping when panning
    MKMapRect visibleMapRect = _mapView.visibleMapRect;
    MKMapRect gridMapRect = MKMapRectInset(visibleMapRect, -_marginFactor * visibleMapRect.size.width, -_marginFactor * visibleMapRect.size.height);
    NSArray* allMapViewAnnotations = self.mapView.annotations;
    NSMutableSet* visibleAnnotations = [[self.mapView annotationsInMapRect:gridMapRect] mutableCopy];
    [visibleAnnotations filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject isKindOfClass:[CCHMapClusterAnnotation class]] && [evaluatedObject mapClusterController] == self;
    }]];
    
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        // For each cell in the grid, pick one annotation to show
        NSMutableSet *clusters = [NSMutableSet set];
        NSSet* children = nil;
        if ([CCHMapClusterController zoomLevelForMapView:self.mapView] >= self.minMetersPerPointsForShowingClusters) {
            children = [self.rootMapCluster findChildrenInMapRect:gridMapRect minCellSize:cellSize] ?: [NSSet set];
//          NSSet* children = [self.rootMapCluster find:40 childrenInMapRect:gridMapRect] ?: [NSSet set];
        } else {
            children = [self.rootMapCluster singleClusterAnnotationsInMapRect:gridMapRect];
        }
        
        
        for (ADMapCluster* child in children) {
            NSSet* allAnnotationsInCell = [child originalAnnotations];
            CLLocationCoordinate2D coordinate = child.clusterCoordinate;
            if (allAnnotationsInCell.count > 0) {
                if (self.strongClusterer) {
                    coordinate = [self.strongClusterer mapClusterController:self coordinateForAnnotations:allAnnotationsInCell inMapRect:visibleMapRect];
                }
                // Select cluster representation
                CCHMapClusterAnnotation *annotationForCell = _findVisibleAnnotation(child, visibleAnnotations);
                
                if (annotationForCell == nil) {
                    annotationForCell = [[CCHMapClusterAnnotation alloc] init];
                    annotationForCell.mapClusterController = self;
                    if (child.annotation) {
                        annotationForCell.type = CCHClusterAnnotationTypeLeaf;
                    } else {
                        annotationForCell.type = CCHClusterAnnotationTypeCluster;
                    }
                    annotationForCell.cluster = child;
                    annotationForCell.coordinate = coordinate;
                    annotationForCell.delegate = _delegate;
                    annotationForCell.annotations = allAnnotationsInCell;
                } else {
                    [visibleAnnotations removeObject:annotationForCell];
                    // For existing annotations, this will implicitly update annotation views
                    dispatch_async(dispatch_get_main_queue(), ^{
                        annotationForCell.annotations = allAnnotationsInCell;
                        annotationForCell.title = nil;
                        annotationForCell.subtitle = nil;
                        annotationForCell.cluster = child;
                        annotationForCell.coordinate = coordinate;
                        if ([self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                            [self.delegate mapClusterController:self willReuseMapClusterAnnotation:annotationForCell];
                        }
                    });
                }
                
                // Collect clusters
                if (annotationForCell) {
                    [clusters addObject:annotationForCell];
                }
            }
        }
        
        // Figure out difference between new and old clusters
        NSSet *annotationsBeforeAsSet = CCHMapClusterControllerClusterAnnotationsForAnnotations(allMapViewAnnotations, self);
        NSMutableSet *annotationsToKeep = [annotationsBeforeAsSet mutableCopy];
        [annotationsToKeep intersectSet:clusters];
        NSMutableSet *annotationsToAddAsSet = [NSMutableSet setWithSet:clusters];
        [annotationsToAddAsSet minusSet:annotationsToKeep];
        NSArray *annotationsToAdd = [annotationsToAddAsSet allObjects];
        NSMutableSet *annotationsToRemoveAsSet = [NSMutableSet setWithSet:annotationsBeforeAsSet];
        [annotationsToRemoveAsSet minusSet:clusters];
        NSArray *annotationsToRemove = [annotationsToRemoveAsSet allObjects];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView addAnnotations:annotationsToAdd];
            [self.animator mapClusterController:self willRemoveAnnotations:annotationsToRemove withCompletionHandler:^{
                [self.mapView removeAnnotations:annotationsToRemove];
                
                if (completionHandler) {
                    completionHandler();
                }
            }];
        });
    }];
    __weak NSOperation *weakOperation = operation;
    operation.completionBlock = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updateOperations removeObject:weakOperation]; // also prevents retain cycle
        });
    };
    [self.updateOperations addObject:operation];
    [self.backgroundQueue addOperation:operation];
}

- (void)deselectAllAnnotations
{
    NSArray *selectedAnnotations = self.mapView.selectedAnnotations;
    for (id<MKAnnotation> selectedAnnotation in selectedAnnotations) {
        [self.mapView deselectAnnotation:selectedAnnotation animated:YES];
    }
}

- (void)selectAnnotation:(id<MKAnnotation>)annotation andZoomToRegionWithLatitudinalMeters:(CLLocationDistance)latitudinalMeters longitudinalMeters:(CLLocationDistance)longitudinalMeters
{
    // Check for valid annotation
    BOOL existingAnnotation = [self.annotations containsObject:annotation];
    NSAssert(existingAnnotation, @"Invalid annotation - can only select annotations previously added by calling addAnnotations:withCompletionHandler:");
    if (!existingAnnotation) {
        return;
    }
    
    // Deselect annotations
    [self deselectAllAnnotations];
    
    // Zoom to annotation
    self.annotationToSelect = annotation;
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(annotation.coordinate, latitudinalMeters, longitudinalMeters);
    [self.mapView setRegion:region animated:YES];
    if (CCHMapClusterControllerCoordinateEqualToCoordinate(region.center, self.mapView.centerCoordinate)) {
        // Manually call update methods because region won't change
        [self mapView:self.mapView regionWillChangeAnimated:YES];
        [self mapView:self.mapView regionDidChangeAnimated:YES];
    }
}
- (MKMapRect)mapRectForParentClusterOfAnnotation:(id<MKAnnotation>)annotation {
    ADMapCluster* cluster = [self.rootMapCluster parentClusterOfAnnotation:annotation];
    if (cluster) {
        return cluster.mapRect;
    }
    return MKMapRectNull;
}
+ (CLLocationDistance)zoomLevelForMapView:(MKMapView*)mapView {
    if (!mapView) {
        return NAN;
    }
    const CGFloat middleSectionFraction = 0.5;
    CGFloat viewWidth = CGRectGetWidth(mapView.bounds);
    CGFloat viewHeight = CGRectGetHeight(mapView.bounds);
    CGPoint p1 = CGPointMake(viewWidth * (0.5 - middleSectionFraction/2.0), viewHeight * 0.5);
    CGPoint p2 = CGPointMake(viewWidth * (0.5 + middleSectionFraction/2.0), viewHeight * 0.5);
    MKMapPoint mp1 = MKMapPointForCoordinate([mapView convertPoint:p1 toCoordinateFromView:mapView]);
    MKMapPoint mp2 = MKMapPointForCoordinate([mapView convertPoint:p2 toCoordinateFromView:mapView]);
    return MKMetersBetweenMapPoints(mp1, mp2) / (viewWidth * middleSectionFraction);
}
#pragma mark - Map view proxied delegate methods

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)annotationViews
{
    // Animate annotations that get added
    [self.animator mapClusterController:self didAddAnnotationViews:annotationViews];
}

- (void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated
{
    self.regionSpanBeforeChange = mapView.region.span;
    self.regionChanging = YES;
}
- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    self.regionChanging = NO;
    
    // Deselect all annotations when zooming in/out. Longitude delta will not change
    // unless zoom changes (in contrast to latitude delta).
    BOOL hasZoomed = !fequal(mapView.region.span.longitudeDelta, self.regionSpanBeforeChange.longitudeDelta);
    if (hasZoomed) {
        [self deselectAllAnnotations];
    }
    
    // Update annotations
    [self updateAnnotationsWithCompletionHandler:^{
        if (self.annotationToSelect) {
            // Map has zoomed to selected annotation; search for cluster annotation that contains this annotation
            CCHMapClusterAnnotation *mapClusterAnnotation = CCHMapClusterControllerClusterAnnotationForAnnotation(self.mapView, self.annotationToSelect, mapView.visibleMapRect);
            self.annotationToSelect = nil;
            
            if (CCHMapClusterControllerCoordinateEqualToCoordinate(self.mapView.centerCoordinate, mapClusterAnnotation.coordinate)) {
                // Select immediately since region won't change
                [self.mapView selectAnnotation:mapClusterAnnotation animated:YES];
            } else {
                // Actual selection happens in next call to mapView:regionDidChangeAnimated:
                self.mapClusterAnnotationToSelect = mapClusterAnnotation;
                
                // Dispatch async to avoid calling regionDidChangeAnimated immediately
                dispatch_async(dispatch_get_main_queue(), ^{
                    // No zooming, only panning. Otherwise, annotation might change to a different cluster annotation
                    [self.mapView setCenterCoordinate:mapClusterAnnotation.coordinate animated:NO];
                });
            }
        } else if (self.mapClusterAnnotationToSelect) {
            // Map has zoomed to annotation
            [self.mapView selectAnnotation:self.mapClusterAnnotationToSelect animated:YES];
            self.mapClusterAnnotationToSelect = nil;
        }
    }];
}

@end
