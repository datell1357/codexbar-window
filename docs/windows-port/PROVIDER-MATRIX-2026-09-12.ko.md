# 공급자 전수 대응표

[이차 감사](SECONDARY-AUDIT-2026-09-12.ko.md)에서 69개 Core/App 등록 chain과 조회 mode의 양방향 링크를 대조했다. 구현·실행 통과를 뜻하지 않는다.

69개 provider ID, 163개 source mode 선언을 원본 descriptor와 공용 apiToken factory에서 추출했다. `auto`를 포함한 설정 모드 수이며 API endpoint나 성공 경로의 개수가 아니다. 모드 이름과 transport를 혼동하지 않는다: JetBrains의 cli 모드는 로컬 파일 조회일 수 있다.

각 행의 모든 모드에 app/CLI, 명시/auto, 선택 계정/ambient, org/region/workspace, 성공/0/nil/stale/auth 실패/권한/429/네트워크/파싱/timeout/cancel fixture를 적용한다. 원본상 불가능한 조합은 원본 거부 결과를 검증하며 새 지원으로 부풀리지 않는다. 상세 strategy/credential/provider UI 경로와 source evidence는 JSON에 있다. 비용 true는 capability 선언이며 실제 금액 가용성/표시 조건까지 같아야 한다.

| ID | 필수 source 모드 | token cost 선언 | 원본 descriptor |
|---|---|---|---|
| codex | api, auto, cli, oauth, web | true | `Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift` |
| openai | api, auto | true | `Sources/CodexBarCore/Providers/OpenAI/OpenAIAPIProviderDescriptor.swift` |
| azureopenai | api, auto | false | `Sources/CodexBarCore/Providers/AzureOpenAI/AzureOpenAIProviderDescriptor.swift` |
| claude | api, auto, cli, oauth, web | true | `Sources/CodexBarCore/Providers/Claude/ClaudeProviderDescriptor.swift` |
| clinepass | api, auto | false | `Sources/CodexBarCore/Providers/ClinePass/ClinePassProviderDescriptor.swift` |
| cursor | auto, cli, web | true | `Sources/CodexBarCore/Providers/Cursor/CursorProviderDescriptor.swift` |
| opencode | auto, web | false | `Sources/CodexBarCore/Providers/OpenCode/OpenCodeProviderDescriptor.swift` |
| opencodego | api, auto, web | true | `Sources/CodexBarCore/Providers/OpenCodeGo/OpenCodeGoProviderDescriptor.swift` |
| alibaba | api, auto, web | false | `Sources/CodexBarCore/Providers/Alibaba/AlibabaCodingPlanProviderDescriptor.swift` |
| alibabatokenplan | auto, cli, web | false | `Sources/CodexBarCore/Providers/Alibaba/AlibabaTokenPlanProviderDescriptor.swift` |
| qwencloud | auto, web | false | `Sources/CodexBarCore/Providers/QwenCloud/QwenCloudProviderDescriptor.swift` |
| factory | api, auto, cli, web | false | `Sources/CodexBarCore/Providers/Factory/FactoryProviderDescriptor.swift` |
| fireworks | api, auto | false | `Sources/CodexBarCore/Providers/Fireworks/FireworksProviderDescriptor.swift` |
| gemini | api, auto | false | `Sources/CodexBarCore/Providers/Gemini/GeminiProviderDescriptor.swift` |
| antigravity | auto, cli, oauth | true | `Sources/CodexBarCore/Providers/Antigravity/AntigravityProviderDescriptor.swift` |
| copilot | api, auto | false | `Sources/CodexBarCore/Providers/Copilot/CopilotProviderDescriptor.swift` |
| devin | auto, web | false | `Sources/CodexBarCore/Providers/Devin/DevinProviderDescriptor.swift` |
| zai | api, auto | false | `Sources/CodexBarCore/Providers/Zai/ZaiProviderDescriptor.swift` |
| minimax | api, auto, web | false | `Sources/CodexBarCore/Providers/MiniMax/MiniMaxProviderDescriptor.swift` |
| manus | auto, web | false | `Sources/CodexBarCore/Providers/Manus/ManusProviderDescriptor.swift` |
| kimi | api, auto, web | false | `Sources/CodexBarCore/Providers/Kimi/KimiProviderDescriptor.swift` |
| kilo | api, auto, cli | false | `Sources/CodexBarCore/Providers/Kilo/KiloProviderDescriptor.swift` |
| kiro | auto, cli | false | `Sources/CodexBarCore/Providers/Kiro/KiroProviderDescriptor.swift` |
| vertexai | auto, oauth | true | `Sources/CodexBarCore/Providers/VertexAI/VertexAIProviderDescriptor.swift` |
| augment | auto, cli | false | `Sources/CodexBarCore/Providers/Augment/AugmentProviderDescriptor.swift` |
| jetbrains | auto, cli | false | `Sources/CodexBarCore/Providers/JetBrains/JetBrainsProviderDescriptor.swift` |
| moonshot | api, auto | false | `Sources/CodexBarCore/Providers/Moonshot/MoonshotProviderDescriptor.swift` |
| amp | api, auto, cli, web | false | `Sources/CodexBarCore/Providers/Amp/AmpProviderDescriptor.swift` |
| t3chat | auto, web | false | `Sources/CodexBarCore/Providers/T3Chat/T3ChatProviderDescriptor.swift` |
| ollama | api, auto, web | false | `Sources/CodexBarCore/Providers/Ollama/OllamaProviderDescriptor.swift` |
| synthetic | api, auto | false | `Sources/CodexBarCore/Providers/Synthetic/SyntheticProviderDescriptor.swift` |
| openrouter | api, auto | true | `Sources/CodexBarCore/Providers/OpenRouter/OpenRouterProviderDescriptor.swift` |
| elevenlabs | auto, api | false | `Sources/CodexBarCore/Providers/ElevenLabs/ElevenLabsProviderDescriptor.swift` |
| warp | auto, api | false | `Sources/CodexBarCore/Providers/Warp/WarpProviderDescriptor.swift` |
| windsurf | auto, cli, web | false | `Sources/CodexBarCore/Providers/Windsurf/WindsurfProviderDescriptor.swift` |
| zed | api, auto | false | `Sources/CodexBarCore/Providers/Zed/ZedProviderDescriptor.swift` |
| perplexity | auto, web | false | `Sources/CodexBarCore/Providers/Perplexity/PerplexityProviderDescriptor.swift` |
| mimo | auto, web | false | `Sources/CodexBarCore/Providers/MiMo/MiMoProviderDescriptor.swift` |
| doubao | api, auto, cli | false | `Sources/CodexBarCore/Providers/Doubao/DoubaoProviderDescriptor.swift` |
| sakana | auto, web | false | `Sources/CodexBarCore/Providers/Sakana/SakanaProviderDescriptor.swift` |
| abacus | auto, web | false | `Sources/CodexBarCore/Providers/Abacus/AbacusProviderDescriptor.swift` |
| mistral | auto, web | true | `Sources/CodexBarCore/Providers/Mistral/MistralProviderDescriptor.swift` |
| deepseek | api, auto, web | false | `Sources/CodexBarCore/Providers/DeepSeek/DeepSeekProviderDescriptor.swift` |
| deepinfra | auto, api | false | `Sources/CodexBarCore/Providers/DeepInfra/DeepInfraProviderDescriptor.swift` |
| codebuff | api, auto | false | `Sources/CodexBarCore/Providers/Codebuff/CodebuffProviderDescriptor.swift` |
| crof | api, auto | false | `Sources/CodexBarCore/Providers/Crof/CrofProviderDescriptor.swift` |
| venice | api, auto | false | `Sources/CodexBarCore/Providers/Venice/VeniceProviderDescriptor.swift` |
| commandcode | auto, web | false | `Sources/CodexBarCore/Providers/CommandCode/CommandCodeProviderDescriptor.swift` |
| qoder | auto, web | false | `Sources/CodexBarCore/Providers/Qoder/QoderProviderDescriptor.swift` |
| stepfun | auto, web | false | `Sources/CodexBarCore/Providers/StepFun/StepFunProviderDescriptor.swift` |
| bedrock | api, auto | true | `Sources/CodexBarCore/Providers/Bedrock/BedrockProviderDescriptor.swift` |
| grok | auto, cli, oauth, web | true | `Sources/CodexBarCore/Providers/Grok/GrokProviderDescriptor.swift` |
| groq | api, auto, web | false | `Sources/CodexBarCore/Providers/Groq/GroqProviderDescriptor.swift` |
| llmproxy | api, auto | false | `Sources/CodexBarCore/Providers/LLMProxy/LLMProxyProviderDescriptor.swift` |
| litellm | api, auto | false | `Sources/CodexBarCore/Providers/LiteLLM/LiteLLMProviderDescriptor.swift` |
| deepgram | api, auto | false | `Sources/CodexBarCore/Providers/Deepgram/DeepgramProviderDescriptor.swift` |
| poe | api, auto | false | `Sources/CodexBarCore/Providers/Poe/PoeProviderDescriptor.swift` |
| chutes | api, auto | false | `Sources/CodexBarCore/Providers/Chutes/ChutesProviderDescriptor.swift` |
| neuralwatt | auto, api | false | `Sources/CodexBarCore/Providers/NeuralWatt/NeuralWattProviderDescriptor.swift` |
| clawrouter | api, auto | false | `Sources/CodexBarCore/Providers/ClawRouter/ClawRouterProviderDescriptor.swift` |
| longcat | auto, web | false | `Sources/CodexBarCore/Providers/LongCat/LongCatProviderDescriptor.swift` |
| sub2api | api, auto | false | `Sources/CodexBarCore/Providers/Sub2API/Sub2APIProviderDescriptor.swift` |
| wayfinder | api, auto | false | `Sources/CodexBarCore/Providers/Wayfinder/WayfinderProviderDescriptor.swift` |
| zenmux | api, auto | false | `Sources/CodexBarCore/Providers/ZenMux/ZenMuxProviderDescriptor.swift` |
| aiand | api, auto | false | `Sources/CodexBarCore/Providers/AiAnd/AiAndProviderDescriptor.swift` |
| zoommate | auto, web | false | `Sources/CodexBarCore/Providers/ZoomMate/ZoomMateProviderDescriptor.swift` |
| xai | api, auto | true | `Sources/CodexBarCore/Providers/XAI/XAIProviderDescriptor.swift` |
| notion | auto, web | false | `Sources/CodexBarCore/Providers/Notion/NotionProviderDescriptor.swift` |
| ibmbob | auto, api | false | `Sources/CodexBarCore/Providers/IBMBob/IBMBobProviderDescriptor.swift` |

## 별도 확인한 조건부 분기

- DeepSeek: API key가 있으면 auto API, 없으면 platform web; optional platform 데이터와 profile scope 포함.
- Doubao: 저장된 API/AK-SK가 있으면 auto API, 없으면 arkcli. 명시 CLI/API는 다른 계정의 인증으로 fallback하지 않는다.
- Antigravity: app-local/agy CLI/IDE-local/OAuth/offline을 구분; 선택 계정과 live local 계정 불일치는 OAuth 소유권 경로로 처리한다.
- Grok: CLI/web/OAuth와 local session/cost 경로를 구분한다. Groq도 API뿐 아니라 console web source를 포함한다.
- Codex/Claude: app와 CLI의 auto 순서·외부 credential 소유권·PAT/admin key·재인증 조건이 다르므로 하나의 fallback 목록으로 평준화하지 않는다.
- Kilo org, Notion workspace, z.ai team, Copilot budgets, OpenCode Go scoped auto, 지역별 MiniMax/Moonshot/Bedrock 등은 provider editor 및 planner 계약과 함께 구현한다.
- OpenRouter/xAI/Grok/Antigravity를 포함한 12개 token-cost 선언을 보존한다. 금액이 알려지지 않는 로컬 token history를 0달러라고 표시하지 않는다.
