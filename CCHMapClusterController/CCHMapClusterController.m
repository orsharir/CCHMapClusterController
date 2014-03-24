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
@property (atomic, assign) BOOL isAnimatingAnnotations;
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
@property (nonatomic, strong) CCHMapClusterAnnotation *(^findVisibleAnnotation)(NSSet *annotations, NSSet *visibleAnnotations);
@property (nonatomic, strong) id<CCHMapAnimator> strongAnimator;

@end

@implementation CCHMapClusterController

- (id)initWithMapView:(MKMapView *)mapView
{
    self = [super init];
    if (self) {
        _isAnimatingAnnotations = NO;
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
        self.findVisibleAnnotation = ^CCHMapClusterAnnotation *(NSSet *annotations, NSSet *visibleAnnotations) {
            return CCHMapClusterControllerFindVisibleAnnotation(annotations, visibleAnnotations);
        };
    } else {
        self.findVisibleAnnotation = ^CCHMapClusterAnnotation *(NSSet *annotations, NSSet *visibleAnnotations) {
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
            self.rootMapCluster = [ADMapCluster rootClusterForAnnotations:annotationsSet gamma:1 clusterTitle:@"Test" showSubtitle:NO];
        } else {
            [self.rootMapCluster addAnnotations:annotationsSet];
        }
        self.allAnnotations = [self.allAnnotations setByAddingObjectsFromArray:annotations];
        updated = self.allAnnotations.count > current;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (updated && !self.isRegionChanging && !self.isAnimatingAnnotations) {
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
        NSUInteger current = self.allAnnotations.count;
        NSMutableSet* newSet = [self.allAnnotations mutableCopy];
        [newSet minusSet:[NSSet setWithArray:annotations]];
        self.allAnnotations = [newSet copy];
        self.rootMapCluster = [ADMapCluster rootClusterForAnnotations:self.allAnnotations gamma:1 clusterTitle:@"Test" showSubtitle:NO];
        updated = self.allAnnotations.count < current;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (updated && !self.isRegionChanging && self.isAnimatingAnnotations) {
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
    NSArray* allMapViewAnnotations = [self.mapView.annotations filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject isKindOfClass:[CCHMapClusterAnnotation class]] && [evaluatedObject mapClusterController] == self;
    }]];
    NSMutableSet* visibleAnnotations = [[self.mapView annotationsInMapRect:gridMapRect] mutableCopy];
    [visibleAnnotations filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject isKindOfClass:[CCHMapClusterAnnotation class]] && [evaluatedObject mapClusterController] == self;
    }]];
    
    
    NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
//        NSSet* clustersToShowOnMap = [self.rootMapCluster find:15 childrenInMapRect:visibleMapRect] ?: [NSSet set];
        NSSet* clustersToShowOnMap = [self.rootMapCluster findChildrenInMapRect:gridMapRect minCellSize:cellSize] ?: [NSSet set];
        
        // Build an array with available annotations (eg. not moving or not staying at the same place on the map)
        NSMutableArray * availableSingleAnnotations = [[NSMutableArray alloc] init];
        NSMutableArray * availableClusterAnnotations = [[NSMutableArray alloc] init];
        NSMutableArray * selfDividingAnnotations = [NSMutableArray new];
        NSMutableArray * animatedAnnotations = [NSMutableArray new];
        for (CCHMapClusterAnnotation * annotation in allMapViewAnnotations) {
            BOOL isAncestor = NO;
            if (annotation.cluster) { // if there is a cluster associated to the current annotation
                for (ADMapCluster * cluster in clustersToShowOnMap) { // is the current annotation cluster an ancestor of one of the clustersToShowOnMap?
                    if ([annotation.cluster isAncestorOf:cluster]) {
                        [selfDividingAnnotations addObject:annotation];
//                        [animatedAnnotations addObject:annotation];
                        isAncestor = YES;
                        break;
                    }
                }
            }
            if (!isAncestor) { // if not an ancestor
                BOOL belongsToClusters = NO; // is the annotation a descendant of one of the clusters to be shown on the map
                if (annotation.cluster) {
                    for (ADMapCluster * cluster in clustersToShowOnMap) {
                        if ([cluster isAncestorOf:annotation.cluster] || [cluster isEqual:annotation.cluster]) {
                            belongsToClusters = YES;
                            break;
                        }
                    }
                }
                if (!belongsToClusters) { // check if this annotation will be used later. If not, it is flagged as "available".
                    if (annotation.type == CCHClusterAnnotationTypeLeaf) {
                        [availableSingleAnnotations addObject:annotation];
                    } else {
                        [availableClusterAnnotations addObject:annotation];
                    }
                }
            }
        }
        self.isAnimatingAnnotations = YES;
//        [self.backgroundQueue setSuspended:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Let ancestor annotations divide themselves
            NSMutableArray* newAnnotationsToBeAddedToMapView = [NSMutableArray new];
            for (CCHMapClusterAnnotation * annotation in selfDividingAnnotations) {
                BOOL willNeedAnAvailableAnnotation = NO;
                CLLocationCoordinate2D originalAnnotationCoordinate = annotation.coordinate;
                ADMapCluster * originalAnnotationCluster = annotation.cluster;
                for (ADMapCluster * cluster in clustersToShowOnMap) {
                    if ([originalAnnotationCluster isAncestorOf:cluster]) {
                        BOOL isReusingAnnotation = NO;
                        if (!willNeedAnAvailableAnnotation) {
                            willNeedAnAvailableAnnotation = YES;
                            annotation.cluster = cluster;
                            if (cluster.annotation) { // replace this annotation by a leaf one
                                NSAssert(annotation.type != CCHClusterAnnotationTypeLeaf, @"Inconsistent annotation type!");
                                CCHMapClusterAnnotation * singleAnnotation = [availableSingleAnnotations lastObject];
                                if (singleAnnotation) {
                                    isReusingAnnotation = YES;
                                    [availableSingleAnnotations removeLastObject];
                                } else {
                                    singleAnnotation = [[CCHMapClusterAnnotation alloc] init];
                                    singleAnnotation.type = CCHClusterAnnotationTypeLeaf;
                                    singleAnnotation.mapClusterController = self;
                                    [newAnnotationsToBeAddedToMapView addObject:singleAnnotation];
                                }
                                
                                singleAnnotation.cluster = annotation.cluster;
                                singleAnnotation.annotations = cluster.originalAnnotations;
                                singleAnnotation.coordinate = originalAnnotationCoordinate;
                                [animatedAnnotations addObject:singleAnnotation];
                                [availableClusterAnnotations addObject:annotation];
                                if (isReusingAnnotation && [self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                                    [self.delegate mapClusterController:self willReuseMapClusterAnnotation:singleAnnotation];
                                }
                            }
                        } else {
                            CCHMapClusterAnnotation * availableAnnotation = nil;
                            if (cluster.annotation) {
                                availableAnnotation = [availableSingleAnnotations lastObject];
                                if (availableAnnotation) {
                                    isReusingAnnotation = YES;
                                    [availableSingleAnnotations removeLastObject];
                                } else {
                                    availableAnnotation = [[CCHMapClusterAnnotation alloc] init];
                                    availableAnnotation.type = CCHClusterAnnotationTypeLeaf;
                                    availableAnnotation.mapClusterController = self;
                                    [newAnnotationsToBeAddedToMapView addObject:availableAnnotation];
                                }
                            } else {
                                availableAnnotation = [availableClusterAnnotations lastObject];
                                if (availableAnnotation) {
                                    isReusingAnnotation = YES;
                                    [availableClusterAnnotations removeLastObject];
                                } else {
                                    availableAnnotation = [[CCHMapClusterAnnotation alloc] init];
                                    availableAnnotation.type = CCHClusterAnnotationTypeCluster;
                                    availableAnnotation.mapClusterController = self;
                                    [newAnnotationsToBeAddedToMapView addObject:availableAnnotation];
                                }
                            }
                            availableAnnotation.cluster = cluster;
                            availableAnnotation.annotations = cluster.originalAnnotations;
                            availableAnnotation.coordinate = originalAnnotationCoordinate;
                            [animatedAnnotations addObject:availableAnnotation];
                            if (isReusingAnnotation && [self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                                [self.delegate mapClusterController:self willReuseMapClusterAnnotation:availableAnnotation];
                            }
                        }
                    }
                }
            }
            
            
            // Converge annotations to ancestor clusters
            for (ADMapCluster * cluster in clustersToShowOnMap) {
                BOOL didAlreadyFindAChild = NO;
                for (CCHMapClusterAnnotation * annotation in allMapViewAnnotations) {
                    if (annotation.cluster) {
                        if ([cluster isAncestorOf:annotation.cluster]) {
                            BOOL isReusingAnnotation = NO;
                            CCHMapClusterAnnotation* annotation1 = annotation;
                            if (annotation1.type == CCHClusterAnnotationTypeLeaf) { // replace this annotation by a cluster one
                                CCHMapClusterAnnotation * clusterAnnotation = [availableClusterAnnotations lastObject];
                                if (clusterAnnotation) {
                                    isReusingAnnotation = YES;
                                    [availableClusterAnnotations removeLastObject];
                                } else {
                                    clusterAnnotation = [[CCHMapClusterAnnotation alloc] init];
                                    clusterAnnotation.type = CCHClusterAnnotationTypeCluster;
                                    clusterAnnotation.mapClusterController = self;
                                    [newAnnotationsToBeAddedToMapView addObject:clusterAnnotation];
                                }
                                
                                clusterAnnotation.cluster = cluster;
                                clusterAnnotation.annotations = cluster.originalAnnotations;
                                // Setting the coordinate makes us call viewForAnnotation: right away, so make sure the cluster is set
                                clusterAnnotation.coordinate = annotation.coordinate;
                                [availableSingleAnnotations addObject:annotation];
                                annotation1 = clusterAnnotation;
                                if (isReusingAnnotation && [self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                                    [self.delegate mapClusterController:self willReuseMapClusterAnnotation:annotation1];
                                }
                            } else {
                                annotation1.cluster = cluster;
                                annotation1.annotations = cluster.originalAnnotations;
                                if ([self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                                    [self.delegate mapClusterController:self willReuseMapClusterAnnotation:annotation1];
                                }
                            }
                            if (annotation1) {
                                [animatedAnnotations addObject:annotation1];
                            }
                            if (didAlreadyFindAChild) {
                                annotation1.shouldBeRemovedAfterAnimation = YES;
                            }
                            didAlreadyFindAChild = YES;
                        }
                    }
                }
            }
            
            
            // Add not-yet-annotated clusters
            NSArray* existingWithToBeAddedAnnotations = [allMapViewAnnotations arrayByAddingObjectsFromArray:newAnnotationsToBeAddedToMapView];
            for (ADMapCluster * cluster in clustersToShowOnMap) {
                BOOL isAlreadyAnnotated = NO;
                for (CCHMapClusterAnnotation * annotation in existingWithToBeAddedAnnotations) {
                    if ([cluster isEqual:annotation.cluster]) {
                        annotation.annotations = cluster.originalAnnotations;
                        isAlreadyAnnotated = YES;
                        break;
                    }
                }
                if (!isAlreadyAnnotated) {
                    BOOL isReusingAnnotation = NO;
                    CCHMapClusterAnnotation* annotation = nil;
                    if (cluster.annotation) {
                        annotation = [availableSingleAnnotations lastObject];
                        if (annotation) {
                            isReusingAnnotation = YES;
                            [availableSingleAnnotations removeLastObject];
                        } else {
                            annotation = [[CCHMapClusterAnnotation alloc] init];
                            annotation.type = CCHClusterAnnotationTypeLeaf;
                            annotation.mapClusterController = self;
                            [newAnnotationsToBeAddedToMapView addObject:annotation];
                        }
                    } else {
                        annotation = [availableClusterAnnotations lastObject];
                        if (annotation) {
                            isReusingAnnotation = YES;
                            [availableClusterAnnotations removeLastObject];
                        } else {
                            annotation = [[CCHMapClusterAnnotation alloc] init];
                            annotation.type = CCHClusterAnnotationTypeCluster;
                            annotation.mapClusterController = self;
                            [newAnnotationsToBeAddedToMapView addObject:annotation];
                        }
                    }
                    annotation.cluster = cluster; // the order here is important: because of KVO, the cluster property must be set before the coordinate property (change of coordinate -> refresh of the view -> refresh of the title -> the cluster can't be nil)
                    annotation.annotations = cluster.originalAnnotations;
                    annotation.coordinate = cluster.clusterCoordinate;
                    if (isReusingAnnotation && [self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                        [self.delegate mapClusterController:self willReuseMapClusterAnnotation:annotation];
                    }
                }
            }

            
            NSMutableArray* annotationsToRemove = [[availableSingleAnnotations arrayByAddingObjectsFromArray:availableClusterAnnotations] mutableCopy];
            
            [self.mapView addAnnotations:newAnnotationsToBeAddedToMapView];
            
            NSArray* updatedAllMapViewAnnotations = [self.mapView.annotations filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
                return [evaluatedObject isKindOfClass:[CCHMapClusterAnnotation class]] && [evaluatedObject mapClusterController] == self;
            }]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                    for (CCHMapClusterAnnotation * annotation in updatedAllMapViewAnnotations) {
                        if (annotation.cluster) {
                            //                NSAssert(!ADClusterCoordinate2DIsOffscreen(annotation.coordinate), @"annotation.coordinate not valid! Can't animate from an invalid coordinate (inconsistent result)!");
                            annotation.coordinate = annotation.cluster.clusterCoordinate;
                        }
                    }
                } completion:^(BOOL finished) {
                    for (CCHMapClusterAnnotation * annotation in updatedAllMapViewAnnotations) {
                        if (annotation.shouldBeRemovedAfterAnimation) {
                            [annotationsToRemove addObject:annotation];
                        }
                    }
                    void (^animationCompletionBlock)(void) = ^{
                        [self.mapView removeAnnotations:annotationsToRemove];
                        [self.mapView.annotations enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                            if ([obj isKindOfClass:[CCHMapClusterAnnotation class]] && [obj mapClusterController] == self) {
                                if ([self.delegate respondsToSelector:@selector(mapClusterController:willReuseMapClusterAnnotation:)]) {
                                    [self.delegate mapClusterController:self willReuseMapClusterAnnotation:obj];
                                }
                            }
                        }];
                        //                    [self.backgroundQueue setSuspended:NO];
                        self.isAnimatingAnnotations = NO;
                        if (completionHandler) {
                            completionHandler();
                        }
                    };
                    //                if (self.animator) {
                    //                    [self.animator mapClusterController:self willRemoveAnnotations:annotationsToRemove withCompletionHandler:animationCompletionBlock];
                    //                } else {
                    animationCompletionBlock();
                    //                }
                }];
            });
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
