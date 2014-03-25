//
//  ADMapCluster.m
//  ADClusterMapView
//
//  Created by Patrick Nollet on 27/06/11.
//  Copyright 2011 Applidium. All rights reserved.
//
//  Original license taken from ADClusterMapView repository: https://github.com/applidium/ADClusterMapView
//    * Copyright (c) 2012, Applidium
//    * All rights reserved.
//    * Redistribution and use in source and binary forms, with or without
//    * modification, are permitted provided that the following conditions are met:
//    *
//    *     * Redistributions of source code must retain the above copyright
//    *       notice, this list of conditions and the following disclaimer.
//    *     * Redistributions in binary form must reproduce the above copyright
//    *       notice, this list of conditions and the following disclaimer in the
//    *       documentation and/or other materials provided with the distribution.
//    *     * Neither the name of Applidium nor the names of its contributors may
//    *       be used to endorse or promote products derived from this software
//    *       without specific prior written permission.
//    *
//    * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
//    * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//    * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//    * DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
//    * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//    * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//       * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//    * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//    * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//    * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "ADMapCluster.h"

#define ADMapClusterDiscriminationPrecision 1E-4

@interface ADMapCluster ()
@property (assign) double aX, aY, YMean, XMean;
@property (nonatomic, assign, readwrite) double gamma;
@property (assign) BOOL sameCoordinate;
@property (assign) NSUInteger annotationsCountAtCreation;
@property (nonatomic, assign, readwrite) NSUInteger numberOfChildren;
@property (nonatomic, assign, readwrite) MKMapRect mapRect;
@end

@interface ADMapCluster (Private)
- (MKMapRect)_mapRect;
- (void)_cleanClusters:(NSMutableArray *)clusters fromAncestorsOfClusters:(NSArray *)referenceClusters;
- (void)_cleanClusters:(NSMutableArray *)clusters outsideMapRect:(MKMapRect)mapRect;
@end

@implementation ADMapCluster
@synthesize clusterCoordinate = _clusterCoordinate;
@synthesize annotation = _annotation;
@synthesize depth = _depth;

- (id)initWithAnnotations:(NSSet *)annotations atDepth:(NSInteger)depth inMapRect:(MKMapRect)mapRect gamma:(double)gamma clusterTitle:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle {
    self = [super init];
    if (self) {
        _annotationsCountAtCreation = annotations.count;
        _gamma = gamma;
        _depth = depth;
        _mapRect = mapRect;
        _clusterTitle = clusterTitle;
        _showSubtitle = showSubtitle;
        self.numberOfChildren = annotations.count;
        
        if (annotations.count == 0) {
            _leftChild = nil;
            _rightChild = nil;
            self.annotation = nil;
            self.clusterCoordinate = kCLLocationCoordinate2DInvalid;
        } else if (annotations.count == 1) {
            _leftChild = nil;
            _rightChild = nil;
            self.annotation = [annotations anyObject];
            self.clusterCoordinate = self.annotation.coordinate;
        } else {
            self.annotation = nil;
            
            // Principal Component Analysis
            // If cov(x,y) = ∑(x-x_mean) * (y-y_mean) != 0 (covariance different from zero), we are looking for the following principal vector:
            // a (aX)
            //   (aY)
            //
            // x_ = x - x_mean ; y_ = y - y_mean
            //
            // aX = cov(x_,y_)
            // 
            //
            // aY = 0.5/n * ( ∑(x_^2) + ∑(y_^2) + sqrt( (∑(x_^2) + ∑(y_^2))^2 + 4 * cov(x_,y_)^2 ) ) 
            
            // compute the means of the coordinate
            double XSum = 0.0;
            double YSum = 0.0;
            
            for (id<MKAnnotation> annotation in annotations) {
                const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                XSum += point.x;
                YSum += point.y;
            }
            double XMean = XSum / (double)annotations.count;
            double YMean = YSum / (double)annotations.count;
            
            _clusterCoordinate = MKCoordinateForMapPoint(MKMapPointMake(XMean, YMean));
            
            if (gamma != 1.0) {
                // take gamma weight into account
                double gammaSumX = 0.0;
                double gammaSumY = 0.0;
                
                double maxDistance = 0.0;
                MKMapPoint meanCenter = MKMapPointMake(XMean, YMean);
                for (id<MKAnnotation> annotation in annotations) {
                    const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                    const double distance = MKMetersBetweenMapPoints(point, meanCenter);
                    if (distance > maxDistance) {
                        maxDistance = distance;
                    }
                }
                
                double totalWeight = 0.0;
                for (id<MKAnnotation> annotation in annotations) {
                    const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                    const double distance = MKMetersBetweenMapPoints(point, meanCenter);
                    const double normalizedDistance = maxDistance != 0.0 ? distance/maxDistance : 1.0;
                    const double weight = pow(normalizedDistance, gamma-1.0);
                    gammaSumX += point.x * weight;
                    gammaSumY += point.y * weight;
                    totalWeight += weight;
                }
                XMean = gammaSumX/totalWeight;
                YMean = gammaSumY/totalWeight;
            }
            
            self.XMean = XMean;
            self.YMean = YMean;
            
            // compute coefficients
            
            double sumXsquared = 0.0;
            double sumYsquared = 0.0;
            double sumXY = 0.0;

            for (id<MKAnnotation> annotation in annotations) {
                const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                const double x = point.x - XMean;
                const double y = point.y - YMean;
                sumXsquared += x * x;
                sumYsquared += y * y;
                sumXY += x * y;
            }
            
            double aX = 0.0;
            double aY = 0.0;
            
            if (fabs(sumXY)/annotations.count > ADMapClusterDiscriminationPrecision) {
                aX = sumXY;
                double lambda = 0.5 * ((sumXsquared + sumYsquared) + sqrt((sumXsquared + sumYsquared) * (sumXsquared + sumYsquared) + 4 * sumXY * sumXY));
                aY = lambda - sumXsquared;
            } else {
                aX = sumXsquared > sumYsquared ? 1.0 : 0.0;
                aY = sumXsquared > sumYsquared ? 0.0 : 1.0;
            }
            self.aX = aX;
            self.aY = aY;
            
            NSSet * leftAnnotations = nil;
            NSSet * rightAnnotations = nil;
            
            if (fabs(sumXsquared)/annotations.count < ADMapClusterDiscriminationPrecision && fabs(sumYsquared)/annotations.count < ADMapClusterDiscriminationPrecision) { // all X and Y are the same => same coordinates
                // then every x equals XMean and we have to arbitrarily choose where to put the pivotIndex
                self.sameCoordinate = YES;
                NSArray* annotationsArray = [annotations allObjects];
                NSInteger pivotIndex = annotationsArray.count /2;
                leftAnnotations = [NSSet setWithArray:[annotationsArray subarrayWithRange:NSMakeRange(0, pivotIndex)]];
                rightAnnotations = [NSSet setWithArray:[annotationsArray subarrayWithRange:NSMakeRange(pivotIndex, annotationsArray.count-pivotIndex)]];
            } else {
                // compute scalar product between the vector of this regression line and the vector
                // (x - x(mean))
                // (y - y(mean))
                // the sign of this scalar product determines which cluster the point belongs to
                self.sameCoordinate = NO;
                leftAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count/2.0];
                rightAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count/2.0];
                for (id<MKAnnotation> annotation in annotations) {
                    const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                    BOOL positivityConditionOfScalarProduct = YES;
                    if (YES) {
                        positivityConditionOfScalarProduct = (point.x - XMean) * aX + (point.y - YMean) * aY > 0.0;
                    } else {
                        positivityConditionOfScalarProduct = (point.y - YMean) > 0.0;
                    }
                    if (positivityConditionOfScalarProduct) {
                        [(NSMutableSet *)leftAnnotations addObject:annotation];
                    } else {
                        [(NSMutableSet *)rightAnnotations addObject:annotation];
                    }
                }
            }
            
            MKMapRect leftMapRect = MKMapRectNull;
            MKMapRect rightMapRect = MKMapRectNull;
            
            // compute map rects
            double XMin = MAXFLOAT, XMax = 0.0, YMin = MAXFLOAT, YMax = 0.0;
            for (id<MKAnnotation> annotation in leftAnnotations) {
                const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                if (point.x > XMax) {
                    XMax = point.x;
                }
                if (point.y > YMax) {
                    YMax = point.y;
                }
                if (point.x < XMin) {
                    XMin = point.x;
                }
                if (point.y < YMin) {
                    YMin = point.y;
                }
            }
            leftMapRect = MKMapRectMake(XMin, YMin, XMax - XMin, YMax - YMin);
            
            XMin = MAXFLOAT, XMax = 0.0, YMin = MAXFLOAT, YMax = 0.0;
            for (id<MKAnnotation> annotation in rightAnnotations) {
                const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                if (point.x > XMax) {
                    XMax = point.x;
                }
                if (point.y > YMax) {
                    YMax = point.y;
                }
                if (point.x < XMin) {
                    XMin = point.x;
                }
                if (point.y < YMin) {
                    YMin = point.y;
                }
            }
            rightMapRect = MKMapRectMake(XMin, YMin, XMax - XMin, YMax - YMin);
            
            _leftChild = [[ADMapCluster alloc] initWithAnnotations:leftAnnotations atDepth:depth+1 inMapRect:leftMapRect gamma:gamma clusterTitle:clusterTitle showSubtitle:showSubtitle];
            _rightChild = [[ADMapCluster alloc] initWithAnnotations:rightAnnotations atDepth:depth+1 inMapRect:rightMapRect gamma:gamma clusterTitle:clusterTitle showSubtitle:showSubtitle];
        }
    }
    return self;
}

+ (ADMapCluster *)rootClusterForAnnotations:(NSSet *)initialAnnotations gamma:(double)gamma clusterTitle:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle {
    // KDTree
    MKMapRect boundaries = [self mapRectForAnnotations:initialAnnotations];
    
    NSLog(@"Computing KD-tree...");
    ADMapCluster * cluster = [[ADMapCluster alloc] initWithAnnotations:initialAnnotations atDepth:0 inMapRect:boundaries gamma:gamma clusterTitle:clusterTitle showSubtitle:showSubtitle];
    NSLog(@"Computation done !");
    if (!cluster) {
        return nil;
    }
    return cluster;
}
+ (MKMapRect)mapRectForAnnotations:(NSSet*)annotations {
    MKMapRect boundaries = MKMapRectWorld;
    
    // This is optional
    boundaries = MKMapRectMake(HUGE_VALF, HUGE_VALF, 0.0, 0.0);
    for (id<MKAnnotation> annotation in annotations) {
        MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
        if (point.x < boundaries.origin.x) {
            boundaries.origin.x = point.x;
        }
        if (point.y < boundaries.origin.y) {
            boundaries.origin.y = point.y;
        }
        if (point.x > boundaries.origin.x + boundaries.size.width) {
            boundaries.size.width = point.x - boundaries.origin.x;
        }
        if (point.y > boundaries.origin.y + boundaries.size.height) {
            boundaries.size.height = point.y - boundaries.origin.y;
        }
    }
    
    return boundaries;
}
- (BOOL)addAnnotations:(NSSet*)annotations {
    return [self _addAnnotations:annotations] > 0;
}
- (NSUInteger)_addAnnotations:(NSSet *)annotations {
    if (!annotations || annotations.count == 0) {
        return 0;
    }
    NSUInteger additions = 0;
    if (2 * self.annotationsCountAtCreation > self.numberOfChildren + annotations.count) {
        NSSet* leftAnnotations;
        NSSet* rightAnnotations;
        if (self.sameCoordinate) {
            NSMutableSet* annotationsToAdd = [annotations mutableCopy];
            [annotationsToAdd minusSet:self.originalAnnotations];
            if (annotationsToAdd.count == 1) {
                if (arc4random_uniform(2) == 0) {
                    leftAnnotations = annotationsToAdd;
                    rightAnnotations = [NSSet set];
                } else {
                    leftAnnotations = [NSSet set];
                    rightAnnotations = annotationsToAdd;
                }
            } else {
                NSArray* annotationsArray = [annotationsToAdd allObjects];
                NSInteger pivotIndex = annotationsArray.count /2;
                leftAnnotations = [NSSet setWithArray:[annotationsArray subarrayWithRange:NSMakeRange(0, pivotIndex)]];
                rightAnnotations = [NSSet setWithArray:[annotationsArray subarrayWithRange:NSMakeRange(pivotIndex, annotationsArray.count-pivotIndex)]];
            }
        } else {
            // compute scalar product between the vector of this regression line and the vector
            // (x - x(mean))
            // (y - y(mean))
            // the sign of this scalar product determines which cluster the point belongs to
            leftAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count/2.0];
            rightAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count/2.0];
            for (id<MKAnnotation> annotation in annotations) {
                const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
                BOOL positivityConditionOfScalarProduct = YES;
                if (YES) {
                    positivityConditionOfScalarProduct = (point.x - self.XMean) * self.aX + (point.y - self.YMean) * self.aY > 0.0;
                } else {
                    positivityConditionOfScalarProduct = (point.y - self.YMean) > 0.0;
                }
                if (positivityConditionOfScalarProduct) {
                    [(NSMutableSet *)leftAnnotations addObject:annotation];
                } else {
                    [(NSMutableSet *)rightAnnotations addObject:annotation];
                }
            }
        }
        if (_leftChild) {
            additions += [_leftChild _addAnnotations:leftAnnotations];
        } else {
            _leftChild = [[ADMapCluster alloc] initWithAnnotations:leftAnnotations atDepth:self.depth+1 inMapRect:[ADMapCluster mapRectForAnnotations:leftAnnotations] gamma:self.gamma clusterTitle:self.title showSubtitle:self.showSubtitle];
            additions += leftAnnotations.count;
        }
        if (_rightChild) {
            additions += [_rightChild _addAnnotations:rightAnnotations];
        } else {
            _rightChild = [[ADMapCluster alloc] initWithAnnotations:rightAnnotations atDepth:self.depth+1 inMapRect:[ADMapCluster mapRectForAnnotations:rightAnnotations] gamma:self.gamma clusterTitle:self.title showSubtitle:self.showSubtitle];
            additions += rightAnnotations.count;
        }
        self.numberOfChildren += additions;
    } else if (annotations.count == 1 && self.annotation && [[annotations anyObject] isEqual:self.annotation]) {
        return 0;
    } else {
        //        NSLog(@"Recreated Node at depth %d", self.depth);
        NSSet* original = self.originalAnnotations;
        NSSet* allAnnotations = [original setByAddingObjectsFromSet:annotations];
        additions = allAnnotations.count - original.count;
        if (additions == 0) {
            return additions;
        }
        
        MKMapRect boundaries = [ADMapCluster mapRectForAnnotations:allAnnotations];
        
        ADMapCluster* newMapCluster = [[ADMapCluster alloc] initWithAnnotations:allAnnotations atDepth:self.depth inMapRect:boundaries gamma:self.gamma clusterTitle:self.title showSubtitle:self.showSubtitle];
        _leftChild = newMapCluster->_leftChild;
        _rightChild = newMapCluster->_rightChild;
        _clusterCoordinate = newMapCluster.clusterCoordinate;
        _mapRect = newMapCluster->_mapRect;
        self.annotationsCountAtCreation = newMapCluster.annotationsCountAtCreation;
        self.aX = newMapCluster.aX;
        self.aY = newMapCluster.aY;
        self.XMean = newMapCluster.XMean;
        self.YMean = newMapCluster.YMean;
        self.sameCoordinate = newMapCluster.sameCoordinate;
        self.annotation = newMapCluster.annotation;
        self.numberOfChildren = newMapCluster.numberOfChildren;
        //        NSLog(@"Recreation done at depth %d", self.depth);
    }
    return additions;
}
- (BOOL)removeAnnotations:(NSSet*)annotations {
    return [self _removeAnnotations:annotations] > 0;
}
- (NSUInteger)_removeAnnotations:(NSSet*)annotations {
    if (!annotations && annotations.count == 0) {
        return 0;
    }
    
    if (self.annotation && [annotations containsObject:self.annotation]) {
        self.annotation = 0;
        self.numberOfChildren = 0;
        return 1;
    }
    
    NSUInteger removals = 0;
    if (self.sameCoordinate) {
        removals += [_leftChild _removeAnnotations:annotations];
        if (_leftChild.numberOfChildren == 0) {
            _leftChild = nil;
        }
        removals += [_rightChild _removeAnnotations:annotations];
        if (_rightChild.numberOfChildren == 0) {
            _rightChild = nil;
        }
    } else {
        // compute scalar product between the vector of this regression line and the vector
        // (x - x(mean))
        // (y - y(mean))
        // the sign of this scalar product determines which cluster the point belongs to
        NSMutableSet* leftAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count/2.0];
        NSMutableSet* rightAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count/2.0];
        for (id<MKAnnotation> annotation in annotations) {
            const MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
            BOOL positivityConditionOfScalarProduct = YES;
            if (YES) {
                positivityConditionOfScalarProduct = (point.x - self.XMean) * self.aX + (point.y - self.YMean) * self.aY > 0.0;
            } else {
                positivityConditionOfScalarProduct = (point.y - self.YMean) > 0.0;
            }
            if (positivityConditionOfScalarProduct) {
                [(NSMutableSet *)leftAnnotations addObject:annotation];
            } else {
                [(NSMutableSet *)rightAnnotations addObject:annotation];
            }
        }
        removals += [_leftChild _removeAnnotations:leftAnnotations];
        if (_leftChild.numberOfChildren == 0) {
            _leftChild = nil;
        }
        removals += [_rightChild _removeAnnotations:rightAnnotations];
        if (_rightChild.numberOfChildren == 0) {
            _rightChild = nil;
        }
    }
    
    self.numberOfChildren -= removals;
    return removals;
}

- (NSSet *)find:(NSInteger)N childrenInMapRect:(MKMapRect)mapRect {
    // Start from the root (self)
    // Adopt a breadth-first search strategy
    // If MapRect intersects the bounds, then keep this element for next iteration
    // Stop if there are N elements or more
    // Or if the bottom of the tree was reached (d'oh!)    
    NSMutableArray * clusters = [[NSMutableArray alloc] initWithObjects:self, nil];
    NSMutableArray * annotations = [[NSMutableArray alloc] init];
    NSMutableArray * previousLevelClusters = nil;
    NSMutableArray * previousLevelAnnotations = nil;
    BOOL clustersDidChange = YES; // prevents infinite loop at the bottom of the tree
    while (clusters.count + annotations.count < N && clusters.count > 0 && clustersDidChange) {
        previousLevelAnnotations = [annotations mutableCopy];
        previousLevelClusters = [clusters mutableCopy];
        
        clustersDidChange = NO;
        NSMutableArray * nextLevelClusters = [[NSMutableArray alloc] init];
        for (ADMapCluster * cluster in clusters) {
            if (cluster.annotation) {
                if (MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate([cluster.annotation coordinate]))) {
                    [annotations addObject:cluster];
                }
                continue;
            }
            for (ADMapCluster * child in [cluster children]) {
                if (MKMapRectIntersectsRect(mapRect, [child _mapRect])) {
                    [nextLevelClusters addObject:child];
                }
            }
        }  
        if (nextLevelClusters.count > 0) {
            clusters = nextLevelClusters;
            clustersDidChange = YES;
        }
    }
    [self _cleanClusters:clusters fromAncestorsOfClusters:annotations];
    
    if (clusters.count + annotations.count > N) { // if there are too many clusters and annotations, that means that we went one level too far in depth
        clusters = previousLevelClusters;
        annotations = previousLevelAnnotations;
        [self _cleanClusters:clusters fromAncestorsOfClusters:annotations];
    }
    [self _cleanClusters:clusters outsideMapRect:mapRect];
    [annotations addObjectsFromArray:clusters];
    
    return [NSSet setWithArray:annotations];
}
- (NSSet *)findChildrenInMapRect:(MKMapRect)mapRect minCellSize:(double)cellSize {
    // Start from the root (self)
    // Adopt a breadth-first search strategy
    // If MapRect intersects the bounds, then keep this element for next iteration
    // Stop if there are N elements or more
    // Or if the bottom of the tree was reached (d'oh!)
    NSMutableArray * clusters = [[NSMutableArray alloc] initWithObjects:self, nil];
    NSMutableArray * annotations = [[NSMutableArray alloc] init];
    NSMutableArray * previousLevelClusters = nil;
    NSMutableArray * previousLevelAnnotations = nil;
    BOOL clustersDidChange = YES; // prevents infinite loop at the bottom of the tree
    while (clusters.count > 0 && clustersDidChange) {
        previousLevelAnnotations = [annotations mutableCopy];
        previousLevelClusters = [clusters mutableCopy];
        
        clustersDidChange = NO;
        NSMutableArray * nextLevelClusters = [NSMutableArray new];
        for (ADMapCluster * cluster in clusters) {
            if (cluster.annotation) {
                if (MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate([cluster.annotation coordinate]))) {
                    [annotations addObject:cluster];
                }
                continue;
            }
            if ([cluster numberOfChildren] > 1 && [cluster minDistanceBetweenChildren] < cellSize && MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(cluster.clusterCoordinate))) {
                [annotations addObject:cluster];
                continue;
            }
            for (ADMapCluster * child in [cluster children]) {
                if (MKMapRectIntersectsRect(mapRect, [child _mapRect])) {
                    [nextLevelClusters addObject:child];
                    clustersDidChange = YES;
                }
            }
        }
        
        clusters = nextLevelClusters;
    }
    [self _cleanClusters:clusters fromAncestorsOfClusters:annotations];
    [self _cleanClusters:clusters outsideMapRect:mapRect];
    [annotations addObjectsFromArray:clusters];
    
    return [NSSet setWithArray:annotations];
}
- (NSSet *)singleClusterAnnotationsInMapRect:(MKMapRect)mapRect {
    NSArray* clusters = @[self];
    NSMutableArray* annotations = [NSMutableArray new];
    while (clusters.count > 0) {
        NSMutableArray* nextClusters = [NSMutableArray new];
        for (ADMapCluster* cluster in clusters) {
            if (cluster.annotation) {
                if (MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate([cluster.annotation coordinate]))) {
                    [annotations addObject:cluster];
                }
            } else {
                for (ADMapCluster* child in [cluster children]) {
                    if (MKMapRectIntersectsRect(mapRect, [child _mapRect])) {
                        [nextClusters addObject:child];
                    }
                }
            }
        }
        clusters = nextClusters;
    }
    return [NSSet setWithArray:annotations];
}
- (NSSet *)annotationsInMapRect:(MKMapRect)mapRect {
    NSSet* clusters = [self singleClusterAnnotationsInMapRect:mapRect];
    NSMutableSet* annotations = [NSMutableSet setWithCapacity:clusters.count];
    for (ADMapCluster* cluster in clusters) {
        [annotations addObject:cluster.annotation];
    }
    return [annotations copy];
}
- (CLLocationDistance)minDistanceBetweenChildren {
    if (_leftChild == nil || _rightChild == nil) {
        return 0;
    }
    MKMapPoint p1 = MKMapPointForCoordinate(_leftChild.clusterCoordinate);
    MKMapPoint p2 = MKMapPointForCoordinate(_rightChild.clusterCoordinate);
    return sqrt(pow(p1.x-p2.x, 2.0)+ pow(p1.y-p2.y, 2.0));
}
- (NSArray *)children {
    NSMutableArray * children = [[NSMutableArray alloc] initWithCapacity:2];
    if (_leftChild) {
        [children addObject:_leftChild];
    }
    if (_rightChild) {
        [children addObject:_rightChild];
    }
    return children;
}

- (BOOL)isAncestorOf:(ADMapCluster *)mapCluster {
    return _depth < mapCluster.depth && (_leftChild == mapCluster || _rightChild == mapCluster || [_leftChild isAncestorOf:mapCluster] || [_rightChild isAncestorOf:mapCluster]);
}

- (BOOL)isRootClusterForAnnotation:(id<MKAnnotation>)annotation {
    return _annotation == annotation || [_leftChild isRootClusterForAnnotation:annotation] || [_rightChild isRootClusterForAnnotation:annotation];
}

- (NSString *)title {
    if (!self.annotation) {
        return [NSString stringWithFormat:_clusterTitle, [self numberOfChildren]];
    } else {
        if ([self.annotation respondsToSelector:@selector(title)]) {
            return self.annotation.title;
        } else {
            return nil;
        }
    }
}

- (NSString *)subtitle {
    if (!self.annotation && self.showSubtitle) {
        return [[self namesOfChildren] componentsJoinedByString:@", "];
    } else if ([self.annotation respondsToSelector:@selector(subtitle)]) {
        return self.annotation.subtitle;
    }
    return nil;
}

- (NSArray *)namesOfChildren {
    if (self.annotation) {
        return @[self.annotation.title];
    } else {
        NSMutableArray* names = [NSMutableArray new];
        if (_leftChild) {
            [names addObjectsFromArray:_leftChild.namesOfChildren];
        }
        if (_rightChild) {
            [names addObjectsFromArray:_rightChild.namesOfChildren];
        }
        return [names copy];
    }
}
- (ADMapCluster*)parentClusterOfAnnotation:(id<MKAnnotation>)annotation {
    if (!annotation) {
        return nil;
    }
    if (_leftChild.annotation == annotation || _rightChild.annotation == annotation) {
        return self;
    }
    if (_leftChild) {
        ADMapCluster* cluster = [_leftChild parentClusterOfAnnotation:annotation];
        if (cluster) {
            return cluster;
        }
    }
    if (_rightChild) {
        ADMapCluster* cluster = [_rightChild parentClusterOfAnnotation:annotation];
        if (cluster) {
            return cluster;
        }
    }
    return nil;
}
- (NSString *)description {
    return [self title];
}

- (NSSet *)originalAnnotations {
    if (self.annotation) {
        return [NSSet setWithObject:self.annotation];
    } else {
        NSMutableSet* annotations = [NSMutableSet new];
        if (_leftChild) {
            [annotations unionSet:_leftChild.originalAnnotations];
        }
        if (_rightChild) {
            [annotations unionSet:_rightChild.originalAnnotations];
        }
        return [annotations copy];
    }
}
@end

@implementation ADMapCluster (Private)

- (MKMapRect)_mapRect {
    return _mapRect;
}

- (void)_cleanClusters:(NSMutableArray *)clusters fromAncestorsOfClusters:(NSArray *)referenceClusters {
    NSMutableArray * clustersToRemove = [[NSMutableArray alloc] init];
    for (ADMapCluster * cluster in clusters) {
        for (ADMapCluster * referenceCluster in referenceClusters) {
            if ([cluster isAncestorOf:referenceCluster]) {
                [clustersToRemove addObject:cluster];
                break;
            }
        }
    }
    [clusters removeObjectsInArray:clustersToRemove];
}
- (void)_cleanClusters:(NSMutableArray *)clusters outsideMapRect:(MKMapRect)mapRect {
    NSMutableArray * clustersToRemove = [[NSMutableArray alloc] init];
    for (ADMapCluster * cluster in clusters) {
        if (!MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(cluster.clusterCoordinate))) {
            [clustersToRemove addObject:cluster];
        }
    }
    [clusters removeObjectsInArray:clustersToRemove];
}
@end