//
//  AxonCore.hpp
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#include "AxonCore.hpp"
#include "LlamaServerRuntime.hpp"

std::string AxonCore::process(const std::string &message)
{
    LlamaServerRuntime runtime("http://localhost:8080");

    return runtime.generate(message);
}

std::string AxonCore::processConversation(const std::string &conversationJson)
{
    LlamaServerRuntime runtime("http://localhost:8080");

    return runtime.generateFromConversation(conversationJson);
}

void AxonCore::streamConversation(
    const std::string &conversationJson,
    std::function<void(const std::string &)> onToken)
{
    LlamaServerRuntime runtime("http://localhost:8080");

    runtime.streamFromConversation(conversationJson, onToken);
}
