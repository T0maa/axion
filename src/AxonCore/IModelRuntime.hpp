//
//  ModelRuntime.hpp
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#pragma once

#include <functional>
#include <string>

class IModelRuntime {
public:
    using TokenCallback = std::function<void(const std::string &)>;

    virtual ~IModelRuntime() = default;

    virtual std::string generate(const std::string &prompt) = 0;
};
