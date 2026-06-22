//
//  AxonBridge.h
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#import <Foundation/Foundation.h>

@interface AxonBridge : NSObject

+ (instancetype)shared;
- (NSString *)sendMessage:(NSString *)message;
- (NSString *)sendConversation:(NSString *)conversationJson;

- (void)streamConversation:(NSString *)conversationJson
                   onToken:(void (^)(NSString *token))onToken
                completion:(void (^)(void))completion;
@end
