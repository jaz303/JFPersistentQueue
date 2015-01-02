#import <Foundation/Foundation.h>

@class JFPersistentQueue;
@class JFPersistentQueueTask;

@protocol JFPersistentQueueDelegate <NSObject>

- (void)queue:(JFPersistentQueue *)queue didBeginTask:(JFPersistentQueueTask *)task;
- (void)queue:(JFPersistentQueue *)queue didCompleteTaskID:(NSInteger)taskID success:(BOOL)success;
- (void)queue:(JFPersistentQueue *)queue didCancelTaskID:(NSInteger)taskID;
- (void)queue:(JFPersistentQueue *)queue didUpdateTaskID:(NSInteger)taskID progress:(CGFloat)progress;

@end
