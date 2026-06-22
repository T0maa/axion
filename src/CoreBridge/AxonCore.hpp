//
//  AxonCore.hpp
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#pragma once

#include <string>
#include <functional>


class AxonCore {
public:
    static std::string process(const std::string &message);
    static std::string processConversation(const std::string &conversationJson);

    static void streamConversation(
        const std::string &conversationJson,
        std::function<void(const std::string &)> onToken
    );
};
