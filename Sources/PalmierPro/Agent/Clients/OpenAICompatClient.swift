import Foundation

/// Streams from an OpenAI-compatible chat endpoint (a local model server or a LiteLLM
/// gateway). Conforms to the same `AgentClient` seam as `BYOKClient`, so the agent
/// loop is unchanged — only the wire format differs (see `OpenAICompatTypes`).
/// Speaks chat-completions, not the OpenAI Responses API `OpenAIProvider` targets.
struct OpenAICompatClient: AgentClient {
    let baseURL: URL
    let apiKey: String
    let model: String
    var maxTokens: Int = 8192

    func stream(
        system: String,
        tools: [AgentToolSchema],
        messages: [AgentRequestMessage],
        context: AgentRequestContext
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        makeAgentStream { continuation in
            try await run(system: system, tools: tools, messages: messages, continuation: continuation)
        }
    }

    private func run(
        system: String,
        tools: [AgentToolSchema],
        messages: [AgentRequestMessage],
        continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws {
        let endpoint = baseURL.appendingPathComponent("chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // A local gateway often needs no key; only send Authorization when set.
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: GatewayChatRequestBody.build(
                model: model, maxTokens: maxTokens, system: system, tools: tools, messages: messages
            ),
            options: [.sortedKeys]
        )

        let bytes = try await AgentHTTP.bytes(for: request) { status, body in
            OpenAICompatError.httpError(status: status, body: body)
        }
        try await GatewayChatSSE.parse(bytes: bytes, continuation: continuation)
    }
}
