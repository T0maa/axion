//
//  ModelRuntime.hpp
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#pragma once

#include "IModelRuntime.hpp"

#include <nlohmann/json.hpp>
#include <string>

using json = nlohmann::json;

class LlamaServerRuntime : public IModelRuntime {
public:
    explicit LlamaServerRuntime(const std::string &url);

    std::string generate(const std::string &prompt) override;
    std::string generateFromConversation(const std::string &conversationJson);
    
    void streamFromConversation(
        const std::string &conversationJson,
        TokenCallback onToken
    );
private:
    std::string _url;
};
