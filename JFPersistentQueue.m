#import "JFPersistentQueue.h"
#import <sqlite3.h>

@interface JFPersistentQueue ()
{
    sqlite3*                        _qDB;           // SQLite DB handle
    __weak JFPersistentQueueTask*   _activeTask;    // Currently executing task
    NSThread*                       _mainThread;    // Thread in which queue was created
    NSOperationQueue*               _opQueue;       // Operation queue for executing tasks
}

- (void)setup;
- (void)wakeup;
- (JFPersistentQueueTask *)findNextTask;
- (void)markTaskCompleted:(NSInteger)taskID;
- (JFPersistentQueueTask *)decodeTaskFromStatement:(sqlite3_stmt *)stmt;
@end

@implementation JFPersistentQueue

@synthesize queueName=_queueName, context=_context, delegate=_delegate;

static NSMutableDictionary *activeQueues = nil;

//
// Class methods

+ (void)initialize {
    activeQueues = [[NSMutableDictionary alloc] init];
}

+ (JFPersistentQueue *)defaultQueue {
    return [self namedQueue:@"Default"];
}

+ (JFPersistentQueue *)namedQueue:(NSString *)name {
    JFPersistentQueue *queue = [activeQueues objectForKey:name];
    if (!queue) {
        queue = [[JFPersistentQueue alloc] initWithName:name];
        [activeQueues setObject:queue forKey:name];
    }
    return queue;
}

//
// Initializers

- (id)initWithName:(NSString *)queueName {
    self = [super init];
    if (self) {
        
        _queueName = queueName;
        _qDB = NULL;
        _activeTask = nil;
        _mainThread = [NSThread currentThread];
        
        _opQueue = [[NSOperationQueue alloc] init];
        [_opQueue setMaxConcurrentOperationCount:1];
        
        [self setup];
    }
    return self;
}

- (void)dealloc {
    if (_qDB) {
        sqlite3_close(_qDB);
    }
}

//
// Properties

- (JFPersistentQueueTask *)activeTask {
    return _activeTask;
}

//
// Public API

- (void)start {
    [self wakeup];
}

- (NSInteger)submitTask:(JFPersistentQueueTask *)task {
    
    NSInteger result        = -1;
    const char *stmt_sql    = "INSERT INTO tasks (task_archive, active) VALUES (?1, 0);";
    sqlite3_stmt *stmt      = NULL;
    
    do {
        
        if (sqlite3_prepare_v2(_qDB, stmt_sql, strlen(stmt_sql), &stmt, NULL) != SQLITE_OK) {
            NSLog(@"[JFPersistentQueue] error preparing SQL statement for task submission");
            break;
        }
        
        NSData *taskArchive = [NSKeyedArchiver archivedDataWithRootObject:task];
        sqlite3_bind_blob(stmt, 1, [taskArchive bytes], [taskArchive length], NULL);
        
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            NSLog(@"[JFPersistentQueue] error inserting task into database");
            break;
        }
        
        result = sqlite3_last_insert_rowid(_qDB);
        
        [self wakeup];
        
    } while (0);
    
    if (stmt) {
        sqlite3_finalize(stmt);
    }
    
    [self wakeup];
    
    return result;

}

- (void)cancelTask:(NSInteger)taskID {
    if (_activeTask && _activeTask.taskID == taskID) {
        [_activeTask cancel];
    } else {
        [self markTaskCompleted:taskID];
        if (_delegate) {
            [_delegate queue:self didCancelTaskID:taskID];
        }
    }
}

- (NSArray *)allTasks {
    
    const char *sql = "SELECT id, task_archive FROM tasks ORDER BY id ASC";
    sqlite3_stmt *stmt = NULL;
    NSMutableArray *tasks = [[NSMutableArray alloc] init];
    
    do {
        
        if (sqlite3_prepare_v2(_qDB, sql, strlen(sql), &stmt, NULL) != SQLITE_OK) {
            NSLog(@"[JFPersistentQueue] error preparing SQL statement for task retrieval");
            break;
        }
        
        int status;
        while ((status = sqlite3_step(stmt)) == SQLITE_ROW) {
            [tasks addObject:[self decodeTaskFromStatement:stmt]];
        }
        
    } while (0);
    
    return tasks;
    
}

//
// Private

- (void)setup {
    
    NSString *queueFile = [NSString stringWithFormat:@"%@.queuedb", _queueName];
    NSString *queueDir  = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *queuePath = [queueDir stringByAppendingPathComponent:queueFile];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL dbExists = [fileManager fileExistsAtPath:queuePath];
    
    if (sqlite3_open([queuePath UTF8String], &_qDB) == SQLITE_OK) {
        
        NSLog(@"[JFPersistentQueue] Connection opened to queue `%@`", _queueName);
        
        const char *createTable = ""
            "CREATE TABLE IF NOT EXISTS tasks ("
            "  id           INTEGER PRIMARY KEY AUTOINCREMENT,"
            "  task_archive BLOB,"
            "  active       INTEGER"
            ")";
        
        if (!dbExists) {
            if (sqlite3_exec(_qDB, createTable, NULL, NULL, NULL) != SQLITE_OK) {
                NSLog(@"[JFPersistentQueue] Error creating task table for queue `%@`", _queueName);
            } else {
                NSLog(@"[JFPersistentQueue] Task table created for queue `%@`", _queueName);
            }
        }
        
    } else {
        NSLog(@"[JFPersistentQueue] Error opening queue DB %@", queuePath);
    }

}

- (JFPersistentQueueTask *)findNextTask {
    
    JFPersistentQueueTask *task = nil;
    const char *sql = "SELECT id, task_archive FROM tasks ORDER BY id ASC LIMIT 1";
    sqlite3_stmt *stmt = NULL;
    
    do {
        
        if (sqlite3_prepare_v2(_qDB, sql, strlen(sql), &stmt, NULL) != SQLITE_OK) {
            NSLog(@"[JFPersistentQueue] error preparing SQL statement for task retrieval");
            break;
        }
        
        int status = sqlite3_step(stmt);
        
        if (status == SQLITE_ROW) {
            task = [self decodeTaskFromStatement:stmt];
        } else if (status == SQLITE_DONE) {
            // do nothing; no rows
        } else {
            NSLog(@"[JFPersistentQueue] unknown error retrieving task");
        }
        
    } while (0);
    
    return task;
    
}

- (void)wakeup {
    
    if (_activeTask) {
        return;
    }
    
    JFPersistentQueueTask *task = [self findNextTask];
    if (task) {

        _activeTask = task;
        if (_delegate) {
            [_delegate queue:self didBeginTask:task];
        }
        
        [task setProgressBlock:^(JFPersistentQueueTask* task){
            [self performSelector:@selector(taskProgressUpdated:)
                         onThread:_mainThread
                       withObject:task
                    waitUntilDone:YES];
        }];
        
        [task setCompletionBlock:^{
            if (task.shouldRetry) {
                [self performSelector:@selector(scheduleRetry)
                             onThread:_mainThread
                           withObject:nil
                        waitUntilDone:NO];
            } else if (task.isCancelled) {
                [self performSelector:@selector(taskCancelled:)
                             onThread:_mainThread
                           withObject:[NSNumber numberWithInt:task.taskID]
                        waitUntilDone:NO];
            } else if (task.isFinished) {
                [self performSelector:@selector(taskFinished:)
                             onThread:_mainThread
                           withObject:[NSNumber numberWithInt:task.taskID]
                        waitUntilDone:NO];
            } else {
                NSLog(@"[JFPersistentQueue] unknown task state for task ID %d", task.taskID);
            }
        }];
        
        [_opQueue addOperation:task];
    }
    
}
         
- (void)scheduleRetry {
    //NSLog(@"RETRY REQUESTED");
    [self performSelector:@selector(retry) withObject:nil afterDelay:5.0];
}

- (void)retry {
    _activeTask = nil;
    [self wakeup];
}

- (void)taskProgressUpdated:(JFPersistentQueueTask*)task {
    if (_delegate) {
        [_delegate queue:self didUpdateTaskID:task.taskID progress:task.progress];
    }
}

- (void)taskCancelled:(NSNumber *)taskID {
    _activeTask = nil;
    [self markTaskCompleted:[taskID integerValue]];
    if (_delegate) {
        [_delegate queue:self didCancelTaskID:taskID.integerValue];
    }
    [self wakeup];
}

- (void)taskFinished:(NSNumber *)taskID {
    _activeTask = nil;
    [self markTaskCompleted:[taskID integerValue]];
    if (_delegate) {
        [_delegate queue:self didCompleteTaskID:taskID.integerValue success:YES];
    }
    [self wakeup];
}

- (JFPersistentQueueTask *)decodeTaskFromStatement:(sqlite3_stmt *)stmt {
    
    NSInteger taskID        = sqlite3_column_int(stmt, 0);
    NSInteger archiveLength = sqlite3_column_bytes(stmt, 1);
    const void *archive     = sqlite3_column_blob(stmt, 1);
    NSData *archiveData     = [NSData dataWithBytesNoCopy:(void*)archive
                                                   length:archiveLength
                                             freeWhenDone:NO];
    
    JFPersistentQueueTask *task = [NSKeyedUnarchiver unarchiveObjectWithData:archiveData];
    task.taskID = taskID;
    task.context = _context;
    
    return task;

}

- (void)markTaskCompleted:(NSInteger)taskID {
    
    const char *sql = "DELETE FROM tasks WHERE id = ?1";
    sqlite3_stmt *stmt = NULL;
    
    do {
        
        if (sqlite3_prepare_v2(_qDB, sql, strlen(sql), &stmt, NULL) != SQLITE_OK) {
            NSLog(@"[JFPersistentQueue] error preparing SQL statement for task deletion");
            break;
        }
        
        sqlite3_bind_int(stmt, 1, taskID);
        
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            NSLog(@"[JFPersistentQueue] error deleting task from database");
            break;
        }
        
    } while (0);
    
    sqlite3_finalize(stmt);
    
}

@end
