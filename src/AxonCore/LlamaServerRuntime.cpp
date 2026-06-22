//
//  ModelRuntime.hpp
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

#include "LlamaServerRuntime.hpp"

#include <curl/curl.h>
#include <string>

struct StreamContext {
    std::string buffer;
    IModelRuntime::TokenCallback onToken;
};

static void process_sse_line(const std::string &line,
    IModelRuntime::TokenCallback onToken)
{
    if (line.rfind("data: ", 0) != 0)
        return;

    std::string data = line.substr(6);

    if (data == "[DONE]")
        return;

    try {
        json parsed = json::parse(data);

        if (!parsed.contains("choices"))
            return;

        auto delta = parsed["choices"][0]["delta"];

        if (!delta.contains("content"))
            return;

        std::string token = delta["content"].get<std::string>();
        onToken(token);
    } catch (...) {
        return;
    }
}

static size_t stream_callback(void *contents, size_t size,
    size_t nmemb, void *userp)
{
    size_t total_size = size * nmemb;
    StreamContext *context = static_cast<StreamContext *>(userp);

    context->buffer.append(static_cast<char *>(contents), total_size);

    size_t pos = 0;

    while ((pos = context->buffer.find('\n')) != std::string::npos) {
        std::string line = context->buffer.substr(0, pos);

        if (!line.empty() && line.back() == '\r')
            line.pop_back();

        process_sse_line(line, context->onToken);
        context->buffer.erase(0, pos + 1);
    }

    return total_size;
}

static size_t write_callback(void *contents, size_t size,
    size_t nmemb, void *userp)
{
    size_t total_size = size * nmemb;
    std::string *response = static_cast<std::string *>(userp);

    response->append(static_cast<char *>(contents), total_size);
    return total_size;
}

LlamaServerRuntime::LlamaServerRuntime(const std::string &url)
    : _url(url)
{
}

std::string LlamaServerRuntime::generate(const std::string &prompt)
{
    CURL *curl = curl_easy_init();
    std::string response;

    if (!curl)
        return "Error: curl init failed";

    std::string endpoint = _url + "/v1/chat/completions";

    std::string body =
        "{"
        "\"model\":\"local\","
        "\"messages\":["
        "{\"role\":\"user\",\"content\":\"" + prompt + "\"}"
        "],"
        "\"temperature\":0.7,"
        "\"max_tokens\":512"
        "}";

    struct curl_slist *headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, endpoint.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

    CURLcode result = curl_easy_perform(curl);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK)
        return "Error: llama-server request failed";
    try {
        json parsed = json::parse(response);

        if (!parsed.contains("choices"))
            return "Error: missing choices in response";

        if (!parsed["choices"].is_array() || parsed["choices"].empty())
            return "Error: empty choices in response";
        
        json message = parsed["choices"][0]["message"];
        if (!message.contains("content"))
            return "Error: missing message content";

        return message["content"].get<std::string>();

    } catch (const std::exception &e) {
        return std::string("Error: failed to parse JSON: ") + e.what();
    }
}

std::string LlamaServerRuntime::generateFromConversation(
    const std::string &conversationJson)
{
    CURL *curl = curl_easy_init();
    std::string response;

    if (!curl)
        return "Error: curl init failed";

    std::string endpoint = _url + "/v1/chat/completions";

    std::string body =
        "{"
        "\"model\":\"local\","
        "\"messages\":" + conversationJson + ","
        "\"temperature\":0.7,"
        "\"max_tokens\":256"
        "}";

    struct curl_slist *headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, endpoint.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

    CURLcode result = curl_easy_perform(curl);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK)
        return "Error: llama-server request failed";

    try {
        json parsed = json::parse(response);

        return parsed["choices"][0]
                     ["message"]
                     ["content"]
                     .get<std::string>();
    } catch (const std::exception &e) {
        return std::string("Error: failed to parse JSON: ") + e.what();
    }
}

void LlamaServerRuntime::streamFromConversation(
    const std::string &conversationJson,
    TokenCallback onToken)
{
    CURL *curl = curl_easy_init();

    if (!curl) {
        onToken("Error: curl init failed");
        return;
    }

    std::string endpoint = _url + "/v1/chat/completions";

    std::string body =
        "{"
        "\"model\":\"local\","
        "\"messages\":" + conversationJson + ","
        "\"temperature\":0.7,"
        "\"max_tokens\":256,"
        "\"stream\":true"
        "}";

    StreamContext context;
    context.onToken = onToken;

    struct curl_slist *headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, endpoint.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, stream_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &context);

    CURLcode result = curl_easy_perform(curl);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (result != CURLE_OK)
        onToken("Error: llama-server streaming request failed");
}
