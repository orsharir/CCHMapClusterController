//
//  ADMapCluster.h
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
