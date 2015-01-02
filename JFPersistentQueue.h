#import <Foundation/Foundation.h>

#import "JFPersistentQueueTask.h"
#import "JFPersistentQueueDelegate.h"

@interface JFPersistentQueue : NSObject

@property (nonatomic,readonly) NSString *queueName;
@property (nonatomic,readonly) JFPersistentQueueTask *activeTask;
@property (nonatomic,readwrite,weak) id context;
@property (nonatomic,readwrite,weak) id<JFPersistentQueueDelegate> delegate;

+ (JFPersistentQueue *)defaultQueue;
+ (JFPersistentQueue *)namedQueue:(NSString *)name;

- (id)initWithName:(NSString *)queueName;

- (void)start;

- (NSInteger)submitTask:(JFPersistentQueueTask *)task;
- (void)cancelTask:(NSInteger)taskID;

- (NSArray *)allTasks;

@end
