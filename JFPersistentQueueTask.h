#import <Foundation/Foundation.h>

@interface JFPersistentQueueTask : NSOperation <NSCoding>

@property (readwrite,weak) id context;
@property (readwrite) NSInteger taskID;
@property (readonly) BOOL shouldRetry;
@property (readwrite,strong) void(^progressBlock)(JFPersistentQueueTask*);
@property (readonly) CGFloat progress;

- (void)taskIsComplete;
- (void)requestRetry;
- (void)updateProgress:(CGFloat)progress;

@end