//
//  AxonBridge.mm
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#import "AxonBridge.h"
#include "AxonCore.hpp"
#include <unistd.h>

@implementation AxonBridge

+ (instancetype)shared
{
    static AxonBridge *instance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        instance = [[AxonBridge alloc] init];
    });

    return instance;
}

- (NSString *)sendMessage:(NSString *)message
{
    std::string input = std::string([message UTF8String]);
    std::string output = AxonCore::process(input);

    return [NSString stringWithUTF8String:output.c_str()];
}

- (NSString *)sendConversation:(NSString *)conversationJson
{
    std::string input = std::string([conversationJson UTF8String]);
    std::string output = AxonCore::processConversation(input);

    return [NSString stringWithUTF8String:output.c_str()];
}

- (void)streamConversation:(NSString *)conversationJson
                   onToken:(void (^)(NSString *token))onToken
                completion:(void (^)(void))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        std::string input = std::string([conversationJson UTF8String]);

        AxonCore::streamConversation(input, [onToken](const std::string &token) {
            NSString *nsToken =
                [NSString stringWithUTF8String:token.c_str()];

            dispatch_async(dispatch_get_main_queue(), ^{
                onToken(nsToken);
            });
        });

        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    });
}

@end
