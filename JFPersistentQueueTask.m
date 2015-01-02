#import "JFPersistentQueueTask.h"

@interface JFPersistentQueueTask ()
{
    BOOL    _isExecuting;
    BOOL    _isFinished;
}
@end

@implementation JFPersistentQueueTask

@synthesize context, taskID, shouldRetry, progressBlock, progress=_progress;

- (id)init {
    self = [super init];
    if (self) {
        _isExecuting = NO;
        _isFinished = NO;
        _progress = 0.0f;
        
        progressBlock = nil;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    return [self init];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {

}

- (BOOL)isExecuting { return _isExecuting; }
- (BOOL)isFinished { return _isFinished; }

- (void)taskIsComplete {
    
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    
    _isExecuting = NO;
    _isFinished = YES;
    
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
    
}

- (void)requestRetry {
    shouldRetry = YES;
}

- (void)updateProgress:(CGFloat)progress
{
    _progress = progress;
    if (progressBlock) {
        progressBlock(self);
    }
}

- (void)main {
    
}

- (void)start {
    
    if (self.isCancelled) {
        return;
    }
    
    shouldRetry = NO;
    
    [self willChangeValueForKey:@"isExecuting"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    [self main];
    
    if (self.isConcurrent) {
        do {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate distantFuture]];
        } while (!self.isFinished);
    } else {
        [self taskIsComplete];
    }
}

@end
