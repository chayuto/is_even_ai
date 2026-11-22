# **Implementation Specification and API Research for is\_even\_ai**

This specification provides an implementation-ready technical reference (RESEARCH.md) for is\_even\_ai, a zero-runtime-dependency Ruby gem that evaluates integer parity through both discriminative System One decision models—with TypeSafe AI's Jev (jev-1.14.0) as a first-class provider—and generative LLM APIs (OpenAI, Anthropic, Google Gemini, and OpenAI-compatible endpoints)1. Every endpoint, header, model identifier, pricing rate, and JSON schema below is verified against primary documentation current as of November 2026, with non-primary benchmarks and pricing trackers explicitly attributed in text1. Under a modeled parity-check workload (100 input tokens for Jev vs. 80 input tokens and 8–110 output tokens for generative LLMs), TypeSafe AI's Jev costs \$4.20 per million checks with free output tokens and a 159-byte minimal JSON payload, compared with \$11.20 for legacy gemini-2.5-flash-lite, \$12.00 for current lean non-reasoning models (gpt-6-luna and claude-haiku-5-5), and up to \$5,040.00 per million checks when frontier reasoning models run with default thinking enabled1.  
Four upstream items could not be verified directly because their target endpoints were inaccessible during research and are explicitly marked \[UNVERIFIED\] throughout this specification: (1) the internal source code, gemspec, public API methods, configuration block, CLI, and README of chayuto/vibe-sort beyond indexed RubyGems and directory metadata13; (2) live RubyGems API confirmation that is\_even\_ai returns HTTP 404 (no indexed gem exists, though a live registry probe is still required prior to publishing)13; (3) the verbatim contents of https\://docs.typesafe.ai/llms.txt and the raw SKILL.md file in github.com/typesafe-ai/skills (offset by direct extraction of the underlying docs.typesafe.ai reference pages and a third-party skill mirror)16; and (4) undocumented vendor parameters including TypeSafe's official millisecond latency SLA, default per-organization rate limits, exact HTTP error JSON schemas on /v1/systemone, and official SDK retry/timeout defaults1.  
Implementing is\_even\_ai reliably in late 2026 requires designing around five breaking shifts across AI APIs and Ruby runtimes that cause ports of 2024–2025 clients to fail immediately with HTTP 400 or LoadError. Anthropic API version 2026-10-21 removes temperature, top\_p, and top\_k completely (returning HTTP 400 if sent) while making structured outputs generally available via output\_config.format with no beta header4; OpenAI's GPT-6 family rejects max\_tokens in favor of max\_completion\_tokens (Chat Completions) or max\_output\_tokens (Responses) and rejects temperature whenever reasoning effort is not none25; Google's Gemini 4 models reject legacy thinkingBudget with HTTP 400 and default to server-side retention on the GA Interactions API unless store: false is set28; TypeSafe's noul primitive returns no confidence field and its box primitive always returns coordinates even when an object is absent2; and Ruby 3.4/4.0 removed base64, logger, and ostruct from default gems while removing Net::HTTP's automatic Content-Type fallback9.

## **1\. Series Baseline Audit: vibe-sort and RubyGems Namespace Status**

### **Verified Metadata for vibe-sort**

The companion gem vibe-sort is authored by Chayut Orapinpatipat (chayut\_o) and hosted at https\://github.com/chayuto/vibe-sort13. Its latest published release is version 0.4.0 (July 12, 2026), expanding from an October 2025 OpenAI proof of concept into a multi-provider Ruby sorting library13.

| Attribute | Verified Value | Source / Verification Status |
| :---- | :---- | :---- |
| **Gem Name** | vibe-sort | Verified (RubyGems index)13 |
| **Author / Owner** | Chayut Orapinpatipat (chayut\_o) | Verified (RubyGems profile & gem index)13 |
| **GitHub Repository** | https\://github.com/chayuto/vibe-sort | Verified (RubyCoder.ai directory)35 |
| **Latest Version & Date** | 0.4.0 — July 12, 2026 (38.5 KB gem package) | Verified (RubyGems index)13 |
| **Release History** | 0.2.0 (Oct 16, 2025, 27 KB); 0.3.0 (Jul 10, 2026, 31.5 KB); 0.3.1 (Jul 11, 2026, 31.5 KB); 0.4.0 (Jul 12, 2026, 38.5 KB) | Verified (4 published versions)13 |
| **Published Summary** | *"A proof-of-concept Ruby gem that sorts arrays by leveraging LLM APIs (OpenAI Chat Completions, Anthropic Messages, Google Gemini, and the OpenAI-compatible..."* | Verified (RubyGems 0.4.0 index; RubyCoder.ai additionally lists Groq and SpaceXAI Grok)13 |
| **MFA Enforcement** | New versions require MFA: true | Verified (RubyGems index)13 |
| **Download Telemetry** | Gem page lists 57,294 total (53,805 for 0.4.0); author profile cache lists 4,152 | Verified with index counter discrepancy noted13 |
| **Public API, Config Block, Env Vars, Refinements, CLI** | \[UNVERIFIED\] | Direct retrieval of rubygems.org/gems/vibe-sort and github.com/chayuto/vibe-sort was inaccessible13 |
| **Provider Classes, Error Hierarchy, HTTP Client, Min Ruby Version, License, Dependencies** | \[UNVERIFIED\] | Gemspec and lib/ source files inaccessible13 |
| **README Structure, Badges, Benchmarks, Tone** | \[UNVERIFIED\] | Repository README.md inaccessible14 |

Because direct retrieval of github.com/chayuto/vibe-sort and the full rubygems.org/gems/vibe-sort page failed, none of vibe-sort's internal class names, module methods, refinement hooks, error classes, minimum Ruby version, or CLI flags should be inferred13. Section 5 therefore specifies an idiomatic Ruby design for is\_even\_ai aligned with vibe-sort's verified multi-provider scope (OpenAI, Anthropic, Google Gemini, and OpenAI-compatible endpoints) while elevating TypeSafe AI's Jev to a first-class provider13. Before writing code, execute gem fetch vibe-sort \-v 0.4.0 && gem unpack vibe-sort-0.4.0.gem locally to harmonize is\_even\_ai's configuration DSL, error hierarchy, CLI conventions, and README badge layout directly with vibe-sort 0.4.0.

### **Ecosystem Prior Art and RubyGems Namespace Status**

Parody parity and sorting libraries exist across neighboring language ecosystems and provide reference points for scope and comedic framing. On npm, Calvin-LL/is-even-ai (485 GitHub stars) exposes isEven(n), isOdd(n), areEqual(a, b), areNotEqual(a, b), isGreaterThan(a, b), isLessThan(a, b), setApiKey, and IsEvenAiOpenAi backed by OpenAI's gpt-3.5-turbo38; a Go counterpart (volodymyrkatkalov/go-ai-iseven) is also cited in community threads39. For sorting, Python's abyesilyurt/vibesort (510 stars) wraps openai and pydantic structured outputs40, while Rust's vibesort (v0.3.0) targets Llama 4 Maverick on Cerebras Cloud41.  
On RubyGems.org, the deterministic gem is\_even (0.1.0, published March 11, 2016 by philnash, MIT license, 8 KB, 3,474 downloads) already occupies the base name15. Indexed searches across RubyGems return no Ruby gem named is\_even\_ai or is-even-ai15. Because direct HTTP access to RubyGems.org was unavailable during research, availability of the is\_even\_ai gem name remains \[UNVERIFIED\] until confirmed locally via curl \-i https\://rubygems.org/api/v1/gems/is\_even\_ai.json (expecting HTTP 404 Not Found)13.

## **2\. TypeSafe AI (Jev) Complete System One API Specification**

TypeSafe AI develops **System One** models—named after Daniel Kahneman's fast, intuitive System 1 cognition—built to supply structured, machine-native judgments directly to application code rather than generating human-readable prose44. Its flagship model, **Jev**, ingests a single state once and evaluates any combination of typed decision primitives (noul, choice, score, box) against that state in parallel and in isolation, returning calibrated probabilities without text generation1.  
Documentation verification status: direct fetches of https\://docs.typesafe.ai/llms.txt and https\://raw.githubusercontent.com/typesafe-ai/skills/main/skills/typesafe-ai/SKILL.md in github.com/typesafe-ai/skills (MIT license, 2.9k stars, release v0.6.2 on October 23, 2026\) failed, leaving their verbatim markdown \[UNVERIFIED\]16. Every wire schema, header, limit, formula, and failure mode below was instead extracted directly from TypeSafe's primary documentation pages (/introduction, /models, /api/system-one, /api/list-models, /api/errors, /primitives/\*, /images, /confidence, /patterns/\*, /model-jaggedness, /changelog, and /agent-skill) and cross-checked against a third-party mirror of the typesafe-ai skill (skills.cowagent.ai)1.

### **2.1 Endpoints, Authentication, and Headers**

TypeSafe's official API reference defines two REST endpoints under https\://api.typesafe.ai; no additional public REST endpoints are documented2. All official SDKs and Bash quickstarts standardize on reading the Bearer token from the TYPESAFE\_API\_KEY environment variable21.

| Endpoint | Method | Purpose | Auth Header |
| :---- | :---- | :---- | :---- |
| https\://api.typesafe.ai/v1/systemone | POST | Evaluate one or more mixed decision primitives against a single state2 | Authorization: Bearer \<token\>2 |
| https\://api.typesafe.ai/v1/models | GET | List model names and aliases available to the authenticated account50 | Authorization: Bearer \<token\>50 |

Request headers accepted by POST /v1/systemone are strictly scoped; no other opt-in API headers appear in the official reference2. (Third-party release coverage notes an organization-level console opt-in permitting TypeSafe to inspect weak queries without training on them, which is a console setting rather than an HTTP request header54.)

| Header | Required | Allowed Values / Rules | Purpose & Failure Mode |
| :---- | :---- | :---- | :---- |
| Authorization | Yes | Bearer \<TYPESAFE\_API\_KEY\> | Bearer token authentication; missing or invalid returns 401 Unauthorized2 |
| Content-Type | Yes | application/json or multipart/form-data | JSON for text/base64; multipart strongly recommended for image uploads2 |
| Content-Encoding | Optional | gzip, x-gzip, or zstd (max 8 MiB window) | Single-layer request body compression; unsupported or nested encoding returns 4152 |
| TypeSafe-Danger-Zone-Images | Conditional | "true" | Opt-in header required whenever assets or box questions are included; omitting returns 400 Bad Request2 |
| TypeSafe-Danger-Zone-Long-Context | Conditional | "true" | Raises both per\_request\_context (64k) and per\_question\_context (32k) to **262k tokens** on jev-1.13.0 and jev-1.14.0; slower and less accurate1 |

The GET /v1/models endpoint returns HTTP 200 OK with a models array whose objects contain three required string fields—name, description, and release\_date (YYYY-MM-DD)—and TypeSafe's models page notes that it currently lists aliases1:

JSON  
{  
  "models": \[  
    {  
      "description": "General-purpose system one model.",  
      "name": "jev-latest",  
      "release\_date": "2026-09-15"  
    }  
  \]  
}

### **2.2 State Input and Multimodal Asset Specification**

Every POST /v1/systemone JSON body carries three required top-level fields (model, state, questions) and one optional field (assets)2. Per the API specification, state accepts a plain string (best for single passages), a JSON object (recommended for most calls so questions can reference named subfields with backticks such as \`value\` or \`photo\`), or a JSON array (for ordered sequences of messages or records)2. Every structured field (instructions, criteria values/entries, and advanced structured fields) is an EntryType accepting string, object, array, or null55. All requests must respect four hard structural boundaries: total body size ≤32 MiB excluding headers (413), JSON nesting depth ≤64 levels across state, instructions, and criteria (400), valid UTF-8 encoding (400), and strictly finite numeric literals—rejecting NaN, Infinity, and overflowed numbers like 1e400 (400)2.  
Inside questions, keys are user-chosen identifiers echoed verbatim in answers and never shown to the model49. There is no fixed ceiling on the number of questions per call provided both context-token budgets hold, and all questions execute in parallel without visibility into one another's outputs1.  
For multimodal inputs, Jev supports still PNG and JPEG images only (no animated PNG/GIF, audio, or video)1. Each image is declared once in the top-level assets map under an opaque placeholder string (TypeSafe recommends a per-image UUID) and referenced anywhere in state, instructions, or criteria values—either standalone or embedded mid-sentence2. Object keys (such as choice option names or question IDs) are never substituted with images49. Every asset declared in assets must be referenced at least once or the API returns 400 Bad Request; referencing the same placeholder multiple times sends duplicate image copies to the model, multiplying both token usage and expanded request size49.

| Asset / Image Parameter | Verified Rule or Limit |
| :---- | :---- |
| **Asset Object Fields** | type (optional; must be "image" if present); format ("png", "jpg", or "jpeg" lowercase; required with data\_base64, optional with part); data\_base64 (standard base64 with \= padding, **no whitespace or line breaks**, **no data: URI prefix**; ignored if part is provided); part (multipart form field name)2 |
| **Multipart Wire Layout** | First form part **must** be named request (Content-Type: application/json); each image is a separate file part (image/png, image/jpeg, image/jpg, or application/octet-stream); avoids \~33% base64 bloat49 |
| **Image Dimensions** | **280 to 1,568 pixels** per side (width and height); out-of-range images return 40049. (One secondary article cited 256 px56; enforce primary docs.typesafe.ai/images's **280 px** minimum.) |
| **Metadata & Orientation** | EXIF and color profiles are stripped; EXIF orientation tags are **not** applied—clients must pre-rotate pixel data upright49 |
| **Size Caps** | Single image: **16 MiB** (post-base64 decode); combined images: **32 MiB**; expanded request (text \+ structure \+ expanded references): **32 MiB**; HTTP body: **32 MiB** (413 on breach)49 |
| **Reference String Caps** | Max **1,024 UTF-8 bytes** per reference; max **65,536 bytes** combined across all references; cannot be empty or whitespace-only49 |

### **2.3 Decision Primitives: Exact Wire Schemas**

All four primitives return the same 200 OK top-level response envelope containing model (resolved version string, which may differ from a requested alias), answers (map keyed by request question IDs), and usage (input\_tokens and output\_tokens)2. The JSON responses below illustrate exact verified response schemas populated with synthetic parity values and formula-consistent probabilities for is\_even\_ai.

#### **Primitive 1: noul (Binary Yes/No Judgment — Primary Parity Mode)**

A noul evaluates a yes/no question or statement and returns a single float in 0..1 representing the probability that the answer is yes/true2. Supplying instructions alone (without criteria) is explicitly valid and recommended as a baseline; optional criteria adds true and false descriptions (string, object, or array) when decision boundaries are nuanced2. Crucially, a noul answer returns **only** type and noul—there is **no confidence**, **no probabilities**, and **no legend** key in the response2.

JSON  
// Minimal valid noul request (159 bytes minified)  
{  
  "model": "jev-latest",  
  "state": "42",  
  "questions": {  
    "is\_even": {  
      "type": "noul",  
      "instructions": "Is this integer an even number (divisible by 2 with no remainder)?"  
    }  
  }  
}

// Structured noul request with optional criteria (271 bytes minified)  
{  
  "model": "jev-latest",  
  "state": { "value": 42 },  
  "questions": {  
    "is\_even": {  
      "type": "noul",  
      "instructions": "Is \`value\` an even integer?",  
      "criteria": {  
        "true": "An integer divisible by 2 with remainder 0 (last digit 0, 2, 4, 6, or 8)",  
        "false": "An odd integer or a non-integer value"  
      }  
    }  
  }  
}

// Illustrative 200 OK Response (exact verified schema keys)  
{  
  "model": "jev-1.14.0",  
  "answers": {  
    "is\_even": {  
      "type": "noul",  
      "noul": 0.99  
    }  
  },  
  "usage": {  
    "input\_tokens": 120,  
    "output\_tokens": 12  
  }  
}

#### **Primitive 2: choice (Closed-Set Classification — Three-Way Parity Mode)**

A choice picks one key from an unordered criteria map containing **up to 255 options**, where keys are option identifier strings and values are descriptions (string, object, array, or null when keys are self-explanatory)2. Both option keys and values are visible to the model49. Whether the API enforces a strict 2-option minimum server-side is \[UNVERIFIED\] in primary docs, though choice semantically requires competing options49. The response always returns four keys: type, choice (highest-probability key), confidence, and probabilities (summing to 1.0)2. When non-integer inputs might otherwise split probability across an other option, TypeSafe's Companion Noul pattern recommends keeping choice focused on even/odd and adding a parallel noul checking whether value is a valid integer59.

JSON  
// Choice request (291 bytes minified)  
{  
  "model": "jev-latest",  
  "state": { "value": 42 },  
  "questions": {  
    "parity": {  
      "type": "choice",  
      "instructions": "What is the parity of \`value\`?",  
      "criteria": {  
        "even": "An integer evenly divisible by 2",  
        "odd": "An integer not divisible by 2",  
        "not\_an\_integer": "A float, non-numeric string, or invalid number"  
      }  
    }  
  }  
}

// Illustrative 200 OK Response (exact verified schema keys; formula-exact confidence \= 0.985)  
{  
  "model": "jev-1.14.0",  
  "answers": {  
    "parity": {  
      "type": "choice",  
      "choice": "even",  
      "confidence": 0.985,  
      "probabilities": {  
        "even": 0.99,  
        "odd": 0.01,  
        "not\_an\_integer": 0.0  
      }  
    }  
  },  
  "usage": {  
    "input\_tokens": 156,  
    "output\_tokens": 24  
  }  
}

#### **Primitive 3: score (Ordered Rubric Rating — "Vibe Evenness" Spectrum Mode)**

A score rates state along an ordered criteria array of **2 to 10 level descriptions** (each a string, object, or array), implicitly 0-indexed from 0 to criteria.length \- 1 with **no** min or max fields2. Each level is judged independently against state without seeing array indices or neighboring wording, so entries should describe concrete conditions rather than bare numerals or relative phrasing49. The HTTP response returns five keys: type, score (probability-weighted expectation Σ(i·pᵢ)), confidence, probabilities (keyed by **stringified** indices "0", "1", ...), and legend (echoing each level string or structured object under stringified indices)2.

JSON  
// Score request (224 bytes minified)  
{  
  "model": "jev-latest",  
  "state": { "value": 42 },  
  "questions": {  
    "evenness": {  
      "type": "score",  
      "instructions": "How even is \`value\`?",  
      "criteria": \[  
        "Definitely odd integer",  
        "Not an integer or ambiguous parity",  
        "Definitely even integer"  
      \]  
    }  
  }  
}

// Illustrative 200 OK Response (exact verified schema keys; formula-exact score \= 1.98, confidence \= 0.97)  
{  
  "model": "jev-1.14.0",  
  "answers": {  
    "evenness": {  
      "type": "score",  
      "score": 1.98,  
      "confidence": 0.97,  
      "legend": {  
        "0": "Definitely odd integer",  
        "1": "Not an integer or ambiguous parity",  
        "2": "Definitely even integer"  
      },  
      "probabilities": {  
        "0": 0.0,  
        "1": 0.02,  
        "2": 0.98  
      }  
    }  
  },  
  "usage": {  
    "input\_tokens": 148,  
    "output\_tokens": 22  
  }  
}

#### **Primitive 4: box (Spatial Localization — "Locate the Even Number in This Image" Mode)**

Classified as **"Dreamer-ready"** (pre-production/experimental), box locates a single visual target in an image and returns normalized bounding-box edges (top, bottom, left, right, each in 0..1 measured from the top-left corner with left \< right and top \< bottom) plus confidence30. It **requires jev-1.14.0** (or jev-latest/jev-preview; jev-1.13.0 returns HTTP 400\) and **requires header TypeSafe-Danger-Zone-Images: true**1. It takes only type: "box" and instructions with no criteria field49. Because box unconditionally returns four coordinates even when the target is missing from the image, is\_even\_ai must bundle a **Companion noul** in the same parallel request and ignore the bounding box when the Noul score falls below threshold30:

JSON  
// Multipart part 1 ("request", Content-Type: application/json) \+ Header: TypeSafe-Danger-Zone-Images: true  
{  
  "model": "jev-1.14.0",  
  "state": { "photo": "9f2a4c10-whiteboard" },  
  "assets": {  
    "9f2a4c10-whiteboard": {  
      "type": "image",  
      "part": "whiteboard-img"  
    }  
  },  
  "questions": {  
    "has\_even\_number": {  
      "type": "noul",  
      "instructions": "Is there at least one even integer visible in \`photo\`?"  
    },  
    "even\_number\_location": {  
      "type": "box",  
      "instructions": "the even integer in \`photo\`"  
    }  
  }  
}

// Illustrative 200 OK Response (exact verified schema keys)  
{  
  "model": "jev-1.14.0",  
  "answers": {  
    "has\_even\_number": {  
      "type": "noul",  
      "noul": 0.96  
    },  
    "even\_number\_location": {  
      "type": "box",  
      "box": { "top": 0.22, "bottom": 0.41, "left": 0.58, "right": 0.74 },  
      "confidence": 0.89  
    }  
  },  
  "usage": {  
    "input\_tokens": 874,  
    "output\_tokens": 28  
  }  
}  
http://googleusercontent.com/visual\_element\_0json  
// Recommended OpenAI Responses API Request (POST https\://api.openai.com/v1/responses, 399 bytes minified)  
{  
  "model": "gpt-6-luna",  
  "store": false,  
  "reasoning": { "effort": "none" },  
  "max\_output\_tokens": 32,  
  "instructions": "Determine if the given integer is even. Respond strictly using the JSON schema.",  
  "input": "42",  
  "text": {  
    "format": {  
      "type": "json\_schema",  
      "name": "parity\_check",  
      "strict": true,  
      "schema": {  
        "type": "object",  
        "properties": { "is\_even": { "type": "boolean" } },  
        "required": \["is\_even"\],  
        "additionalProperties": false  
      }  
    }  
  }  
}

OpenAI error responses use {"error": {"type": "...", "code": "...", "message": "...", "param": ...}} across 400, 401, 403, 404, 409, 429 (including credit\_balance\_exhausted and slow\_down; honor Retry-After), 500, and 50362. Diagnostics headers returned on responses include x-request-id, openai-processing-ms, and x-ratelimit-remaining-requests / x-ratelimit-remaining-tokens3.

### **3.2 Anthropic Claude (Messages API, Version 2026-10-21)**

Anthropic serves Claude via POST https\://api.anthropic.com/v1/messages requiring headers anthropic-version: 2026-10-21, content-type: application/json, and authentication via Authorization: Bearer \$ANTHROPIC\_API\_KEY (the new standard in 2026-10-21, with x-api-key remaining accepted server-side as a fallback)23.  
Three verified 2026-10-21 Messages API rules shape the Anthropic adapter. First, temperature, top\_p, and top\_k have been completely removed: sending any of them—even with default values—triggers **HTTP 400** on every model23. Second, grammar-constrained JSON Schema structured outputs are generally available across **all** Claude models via output\_config.format (type: "json\_schema", schema: {...}) with **no anthropic-beta header required**4. Every object in the schema requires additionalProperties: false, while numeric bounds (minimum/maximum), string lengths, oneOf, not, recursive schemas, citations, and assistant prefill are unsupported or return HTTP 4004. Third, current Claude models enable adaptive thinking by default and reject legacy manual budget\_tokens with HTTP 4006. claude-haiku-5-5 accepts thinking: {"type": "disabled"} at effort high or below (returning 400 at xhigh/max), claude-sonnet-5-5 rejects "disabled" (lowest mode is {"type": "between\_tools"}), and claude-opus-5-5 / claude-fable-5-2 keep adaptive thinking permanently on6. Because thinking blocks can precede text blocks and thinking tokens count toward the required max\_tokens ceiling, the adapter must select content.find { \|b\| b\["type"\] \== "text" }, raise max\_tokens (e.g., 1,024) when thinking is active, and trap stop\_reason: "refusal" or "max\_tokens"4.

| Model ID | Standard Input / Output (per 1M) | Context / Max Output | Thinking Control | Recommended Role |
| :---- | :---- | :---- | :---- | :---- |
| claude-haiku-5-5 | **\$0.10 / \$0.50** (≤100K prompt; \$0.50 / \$2.50 \>100K)6 | 1M / 128K6 | Adaptive default (medium); accepts thinking: {"type": "disabled"}6 | **Default Anthropic model** |
| claude-sonnet-5-5 | \$2.00 / \$10.006 | 1M / 128K6 | Adaptive default (high); lowest between\_tools6 | Mid-tier generative check |
| claude-opus-5-5 | \$4.00 / \$20.006 | 1M / 128K6 | Adaptive always on (medium default)6 | High-cost reasoning check |
| claude-fable-5-2 | \$8.00 / \$40.006 | 1M / 128K6 | Adaptive always on (high default)6 | Frontier parity extravagance |

JSON  
// Anthropic Messages Request (POST https\://api.anthropic.com/v1/messages, 383 bytes minified)  
{  
  "model": "claude-haiku-5-5",  
  "max\_tokens": 64,  
  "thinking": { "type": "disabled" },  
  "system": "Determine if the given integer is even. Respond strictly using the JSON schema.",  
  "messages": \[  
    { "role": "user", "content": "42" }  
  \],  
  "output\_config": {  
    "format": {  
      "type": "json\_schema",  
      "schema": {  
        "type": "object",  
        "properties": { "is\_even": { "type": "boolean" } },  
        "required": \["is\_even"\],  
        "additionalProperties": false  
      }  
    }  
  }  
}

Anthropic errors return {"type": "error", "error": {"type": "\<error\_type\>", "message": "\<msg\>"}, "request\_id": "req\_..."} paired with a request-id HTTP header73. Status mappings cover 400 (invalid\_request\_error), 401 (authentication\_error), 402 (billing\_error), 403 (permission\_error), 404 (not\_found\_error), 409 (conflict\_error), 413 (request\_too\_large, 128 MB Messages limit), 429 (rate\_limit\_error—honor retry-after, noting monthly spend-cap 429s carry no retry-after header), 500 (api\_error), 504 (timeout\_error), and 529 (overloaded\_error—retry with exponential backoff and jitter)73.

### **3.3 Google Gemini (Interactions API and Legacy generateContent)**

Google serves Gemini under https\://generativelanguage.googleapis.com and authenticates REST calls through the x-goog-api-key header (preventing URL query-string leakage and supporting post-June 2026 AQ. service-account-bound keys)74. Matching Google AI Studio client libraries, is\_even\_ai checks GOOGLE\_API\_KEY first and falls back to GEMINI\_API\_KEY74.  
Two Gemini REST interfaces operate concurrently as of November 2026\. The legacy **generateContent** endpoint (POST /v1beta/models/{model}:generateContent) remains fully supported and is recommended as the v0.1 default because its response schema—candidates\[0\].content.parts\[0\].text, finishReason (STOP, MAX\_TOKENS, SAFETY, etc.), promptFeedback.blockReason, and usageMetadata (promptTokenCount, candidatesTokenCount, thoughtsTokenCount, totalTokenCount)—is completely verified in primary reference docs29. Structured outputs configure generationConfig.responseMimeType: "application/json" paired with generationConfig.responseJsonSchema (standard lowercase JSON Schema; verified via Google's official js-genai SDK and Cloud/AI Studio docs, omitting responseSchema when set)28. Crucially, setting legacy thinkingConfig.thinkingBudget on Gemini 4 models returns HTTP 400 INVALID\_ARGUMENT; use thinkingLevel (LOW, MEDIUM, HIGH; MINIMAL is supported on gemini-3.5-flash-lite but rejected on Gemini 4\)28.  
Google's newer **Interactions API** (POST /v1beta/interactions), generally available since June 2026, accepts header Api-Revision: 2026-05-20 and body keys model, input, system\_instruction, store: false, generation\_config, and response\_format: {type: "text", mime\_type: "application/json", schema: {...}}5. Because Interactions stores requests server-side by default (55 days on Paid Tier, 1 day on Free Tier), stateless adapters must always send "store": false29. Exact raw REST outputs/steps and token-usage field names on /v1beta/interactions responses remain \[UNVERIFIED\] from the retrieved primary docs, so :interactions should ship as an opt-in transport pending a single live response capture5.

JSON  
// Gemini generateContent Request (POST .../v1beta/models/gemini-3.5-flash-lite:generateContent, 392 bytes minified)  
{  
  "systemInstruction": {  
    "parts": \[{ "text": "Determine if the given integer is even. Respond strictly using the JSON schema." }\]  
  },  
  "contents": \[  
    { "role": "user", "parts": \[{ "text": "42" }\] }  
  \],  
  "generationConfig": {  
    "responseMimeType": "application/json",  
    "responseJsonSchema": {  
      "type": "object",  
      "properties": { "is\_even": { "type": "boolean" } },  
      "required": \["is\_even"\],  
      "additionalProperties": false  
    },  
    "maxOutputTokens": 32  
  }  
}  
http://googleusercontent.com/visual\_element\_1ruby  
req.set\_form(  
  \[  
    \["request", StringIO.new(JSON.generate(payload)), { content\_type: "application/json" }\],  
    \[part\_name, file\_io, { filename: File.basename(path), content\_type: mime\_type }\]  
  \],  
  "multipart/form-data"  
)

Third, because Ruby 4.0 removed Net::HTTP's implicit Content-Type: application/x-www-form-urlencoded fallback on requests with bodies, every JSON POST must set req\["Content-Type"\] \= "application/json" explicitly33. Fourth, Configuration and provider client objects should implement Ruby 4.0's \#instance\_variables\_to\_inspect hook alongside a custom \#inspect fallback (for Ruby 3.2–3.4) so API keys are redacted in IRB sessions and exception logs85.

### **5.2 Public API, Parity Modes, Configuration, and Precedence**

To stay concise and deadpan while preserving TypeSafe's calibrated probability telemetry, is\_even\_ai separates boolean predicates from rich immutable Result objects:

Ruby  
\# 1\. Deadpan boolean predicates (true / false; raises UncertainParityError when uncertain in strict mode)  
IsEvenAI.even?(42)                                 \# \=\> true  
IsEvenAI.odd?(42)                                  \# \=\> false  
IsEvenAI.even?(42, provider: :typesafe)            \# \=\> true (via Jev noul)  
IsEvenAI.even?(42, provider: :openai, model: "gpt-6-luna")

\# 2\. Full calibrated inspection (returns immutable IsEvenAI::Result)  
result \= IsEvenAI.parity(42, provider: :typesafe, primitive: :noul)  
result.even?        \# \=\> true  
result.odd?         \# \=\> false  
result.probability  \# \=\> 0.99 (raw noul or winning choice probability; nil on generative LLMs)  
result.confidence   \# \=\> 0.98 (\|2p \- 1\| for noul; native API confidence for choice/score/box)  
result.uncertain?   \# \=\> false (true when noul is in no\_threshold..yes\_threshold, default 0.3..0.7)  
result.usage        \# \=\> { input\_tokens: 100, output\_tokens: 12 }  
result.model        \# \=\> "jev-1.14.0"

\# 3\. TypeSafe multimodal Box \+ Companion Noul gag mode (requires jev-1.14.0 \+ Danger-Zone header)  
box\_result \= IsEvenAI.even\_in\_image("whiteboard.png", provider: :typesafe)  
box\_result.present?   \# \=\> true (gated by companion noul \> yes\_threshold)  
box\_result.box        \# \=\> { top: 0.22, bottom: 0.41, left: 0.58, right: 0.74 }  
box\_result.confidence \# \=\> 0.89

\# 4\. Opt-in scoped Integer refinement (zero global monkey-patching)  
using IsEvenAI::Refinements  
42.ai\_even?           \# \=\> true  
42.ai\_odd?            \# \=\> false

\# 5\. Global configuration block \+ isolated Client instances (thread-safe)  
IsEvenAI.configure do \|c\|  
  c.provider       \= :typesafe       \# :typesafe \| :openai \| :anthropic \| :gemini \| :openai\_compatible  
  c.model          \= nil             \# defaults per provider (see table below)  
  c.primitive      \= :noul           \# TypeSafe only: :noul \| :choice \| :score  
  c.yes\_threshold  \= 0.7             \# TypeSafe Noul YES cutoff  
  c.no\_threshold   \= 0.3             \# TypeSafe Noul NO cutoff  
  c.on\_uncertain   \= :raise          \# :raise (UncertainParityError) \| :fallback\_bool (p \>= 0.5)  
  c.timeout        \= 30              \# read\_timeout seconds (open\_timeout: 5, write\_timeout: 10\)  
  c.max\_retries    \= 2               \# exponential backoff \+ jitter on 429/503/529  
  c.danger\_zone\_images       \= false \# auto-enabled on even\_in\_image unless forbidden  
  c.danger\_zone\_long\_context \= false  
end

Configuration resolves in strict precedence order: (1) per-call keyword arguments (provider:, model:, api\_key:, primitive:, timeout:) override (2) IsEvenAI::Client.new(...) instance configuration, which overrides (3) global IsEvenAI.configure settings, which override (4) provider environment variables, falling back to (5) gem defaults.

| Provider Key | Default Model | Env Var Precedence | Default Transport Endpoint |
| :---- | :---- | :---- | :---- |
| :typesafe | jev-latest (jev-1.14.0)1 | TYPESAFE\_API\_KEY53 | POST https\://api.typesafe.ai/v1/systemone2 |
| :openai | gpt-6-luna3 | OPENAI\_API\_KEY3 | POST https\://api.openai.com/v1/responses (opt-in :chat\_completions)87 |
| :anthropic | claude-haiku-5-56 | ANTHROPIC\_API\_KEY24 | POST https\://api.anthropic.com/v1/messages (anthropic-version: 2026-10-21)23 |
| :gemini | gemini-3.5-flash-lite81 | GOOGLE\_API\_KEY, then GEMINI\_API\_KEY74 | POST https\://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent (opt-in :interactions)76 |
| :openai\_compatible | *(required by caller)* | OPENAI\_COMPATIBLE\_API\_KEY (optional) | POST {base\_url}/chat/completions89 |

When provider is unset, auto-detection checks TYPESAFE\_API\_KEY → OPENAI\_API\_KEY → ANTHROPIC\_API\_KEY → GOOGLE\_API\_KEY / GEMINI\_API\_KEY, raising IsEvenAI::ConfigurationError with actionable setup guidance if none are present. On .even? and .odd?, non-Integer inputs (Float, nil, arbitrary objects) raise ArgumentError to match Integer\#even? semantics unless allow\_non\_integer: true is passed to .parity for TypeSafe's 3-option choice or score primitives; arbitrarily large Ruby Integers serialize cleanly without float precision loss. The optional CLI (exe/is-even-ai) uses optparse (a Ruby default gem since Ruby 3.0 and absent from Ruby 3.4/4.0 removal lists34; verify on Ruby 4.0 CI or parse ARGV directly to keep zero gemspec dependencies), supporting is-even-ai 42 \--provider typesafe \--primitive noul \--json and is-even-ai \--image whiteboard.png \--provider typesafe with exit codes 0 (even), 1 (odd), and 2 (uncertain/error).

### **5.3 Provider Abstraction, Error Hierarchy, and HTTP Retry Contract**

Every adapter subclasses IsEvenAI::Providers::Base implementing \#check\_parity(value, \*\*opts) \-\> IsEvenAI::Result (with Providers::TypeSafe also implementing \#locate\_even\_in\_image(path, \*\*opts) and \#list\_models). All network traffic flows through a single IsEvenAI::Transport::HTTP wrapper configured with http.use\_ssl \= (uri.scheme \== "https"), http.verify\_mode \= OpenSSL::SSL::VERIFY\_PEER (never pinning deprecated ssl\_version, which disables TLS 1.3), http.open\_timeout \= 5, http.read\_timeout \= config.timeout, http.write\_timeout \= 10, and **http.max\_retries \= 0** so Net::HTTP's internal socket retry does not double-stack beneath the gem's retry policy91.  
The transport retries strictly on transient socket errors (Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, EOFError) and retryable HTTP status codes (429, 500, 502, 503, 504, 529\) up to config.max\_retries (default 2\)1. When a numeric Retry-After response header is present, the client sleeps for that duration (clamped to a safe cap such as 30 seconds); otherwise it applies truncated exponential backoff with full jitter. Client errors (400, 401, 402, 403, 404, 409, 413, 415, 422\) and billing-exhausted 429 responses (credit\_balance\_exhausted on OpenAI or spend-cap 429 responses lacking retry-after on Anthropic) fail immediately without retry63.

| Error Class (inherits IsEvenAI::Error \< StandardError) | Triggering Conditions Across Providers | Attributes Exposed |
| :---- | :---- | :---- |
| ConfigurationError | Missing API key, unknown provider/primitive, box requested on jev-1.13.01 | provider |
| AuthenticationError | HTTP 401 / 403 (authentication\_error, PERMISSION\_DENIED)20 | status, request\_id, body |
| BillingError | HTTP 402 (Anthropic) or 429 credit\_balance\_exhausted (OpenAI)63 | status, code, request\_id |
| BadRequestError | HTTP 400, 415, 422 (validation, max\_tokens\_exceeded, missing Danger-Zone header, removed Anthropic sampling param)20 | status, code, param, body |
| PayloadTooLargeError | HTTP 413 (\>32 MiB TypeSafe, \>128 MB Anthropic)20 | status, body |
| RateLimitError | HTTP 429 (rate\_limit\_error, RESOURCE\_EXHAUSTED) after retry budget exhausted20 | status, retry\_after, request\_id |
| OverloadedError | HTTP 529 (TypeSafe / Anthropic) or 503 (OpenAI / Gemini) after retries20 | status, request\_id |
| ServerError | HTTP 500, 502, 504 after retries73 | status, request\_id, body |
| ConnectionError / TimeoutError | Socket failures, SSL errors, Net::OpenTimeout/ReadTimeout/WriteTimeout63 | cause |
| RefusalError | OpenAI refusal block/field, Anthropic stop\_reason: "refusal", Gemini SAFETY/PROHIBITED\_CONTENT68 | provider, reason, raw\_response |
| ParseError | Truncated output (max\_tokens/incomplete) or invalid/non-boolean JSON payload4 | raw\_text, raw\_response |
| UncertainParityError | TypeSafe noul inside no\_threshold..yes\_threshold (or choice/score below confidence floor) when on\_uncertain: :raise49 | result (IsEvenAI::Result) |

### **5.4 Pre-Release Verification Backlog (\[UNVERIFIED\] Resolution Checklist)**

Before tagging is\_even\_ai v0.1.0, execute these six local verification steps to close every \[UNVERIFIED\] item:

> 1. **RubyGems Name Availability:** Run curl \-i https\://rubygems.org/api/v1/gems/is\_even\_ai.json to confirm 404 Not Found before reserving the name.  
> 2. **vibe-sort Series Parity Audit:** Run gem fetch vibe-sort \-v 0.4.0 && gem unpack vibe-sort-0.4.0.gem to inspect Chayut Orapinpatipat's exact gemspec, Ruby version floor, configuration block, error hierarchy, CLI, badges, and README tone so is\_even\_ai aligns seamlessly13.  
> 3. **TypeSafe Raw Docs & Error Envelope Probe:** Fetch https\://docs.typesafe.ai/llms.txt and https\://raw.githubusercontent.com/typesafe-ai/skills/main/skills/typesafe-ai/SKILL.md from a development host, and trigger live 400/401/422 calls against POST https\://api.typesafe.ai/v1/systemone to capture exact error JSON keys and test whether a 1-option choice returns 42216.  
> 4. **TypeSafe Parity Accuracy & Jaggedness Eval:** Run a live harness against jev-1.14.0 testing small integers (-10..10), zero (0), negative integers (-42, \-7), large Bignums (2\*\*100, 2\*\*100 \+ 1), noul with vs. without criteria, choice option-order swaps (even/odd vs. odd/even), and box \+ companion noul on sample images45; log empirical p50/p95 latency and actual usage.input\_tokens for the README benchmark table.  
> 5. **Gemini Interactions REST Capture & Decisions API Watch:** Execute a live request against POST https\://generativelanguage.googleapis.com/v1beta/interactions with store: false to record exact raw REST outputs/steps and usage JSON keys before promoting :interactions out of opt-in status5, and monitor primary Google REST docs for gemini-decision-1 ahead of v0.2.099.  
> 6. **Zero-Dependency Ruby Matrix CI:** Execute the full test suite under bundle exec across Ruby 3.2, 3.3, 3.4, and 4.0 with zero runtime dependencies in is\_even\_ai.gemspec to verify that no demoted default gem (base64, logger, ostruct, cgi) leaks into runtime code9.

#### **Works cited**

> 1. Models \- TypeSafe docs, [https\://docs.typesafe.ai/models](https://docs.typesafe.ai/models)  
> 2. System One \- TypeSafe docs, [https\://docs.typesafe.ai/api/system-one](https://docs.typesafe.ai/api/system-one)  
> 3. [https\://developers.openai.com/api/docs/guides/structured-outputs](https://developers.openai.com/api/docs/guides/structured-outputs)  
> 4. Structured outputs \- Claude Platform Docs, [https\://platform.claude.com/docs/en/build-with-claude/structured-outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)  
> 5. [https\://aistudio.google.com/docs/structured-output](https://aistudio.google.com/docs/structured-output)  
> 6. Models overview \- Claude Platform Docs, [https\://platform.claude.com/docs/en/models/overview](https://platform.claude.com/docs/en/models/overview)  
> 7. [https\://developers.openai.com/api/docs/models/compare](https://developers.openai.com/api/docs/models/compare)  
> 8. [https\://aistudio.google.com/docs/pricing](https://aistudio.google.com/docs/pricing)  
> 9. [https\://stdgems.org/compare/supported/](https://stdgems.org/compare/supported/)  
> 10. Pricing \- Claude Platform Docs, [https\://platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing)  
> 11. Gemini 2.5 Flash Lite API Pricing \- LiteLLM Model, [https\://models.litellm.ai/models/gemini-2.5-flash-lite](https://models.litellm.ai/models/gemini-2.5-flash-lite)  
> 12. [unknown\_url](http://docs.google.com/unknown_url)  
> 13. vibe-sort \| RubyGems.org \| your community gem host, [https\://rubygems.org/gems/vibe-sort](https://rubygems.org/gems/vibe-sort)  
> 14. [https\://github.com/chayuto/vibe-sort](https://github.com/chayuto/vibe-sort)  
> 15. is\_even \| RubyGems.org \| your community gem host, [https\://rubygems.org/gems/is\_even/versions/0.1.0](https://rubygems.org/gems/is_even/versions/0.1.0)  
> 16. [https\://docs.typesafe.ai/llms.txt](https://docs.typesafe.ai/llms.txt)  
> 17. [https\://raw.githubusercontent.com/typesafe-ai/skills/main/skills/typesafe-ai/SKILL.md](https://raw.githubusercontent.com/typesafe-ai/skills/main/skills/typesafe-ai/SKILL.md)  
> 18. [https\://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md](https://github.com/typesafe-ai/skills/blob/main/skills/typesafe-ai/SKILL.md)  
> 19. [https\://skills.cowagent.ai/en/typesafe-ai](https://skills.cowagent.ai/en/typesafe-ai)  
> 20. [https\://docs.typesafe.ai/api/errors](https://docs.typesafe.ai/api/errors)  
> 21. typesafe-ai/typesafe-sdk-python: The official Python library ... \- GitHub, [https\://github.com/typesafe-ai/typesafe-sdk-python](https://github.com/typesafe-ai/typesafe-sdk-python)  
> 22. [https\://docs.typesafe.ai/sdk](https://docs.typesafe.ai/sdk)  
> 23. API versions \- Claude Platform Docs, [https\://platform.claude.com/docs/en/api/versioning](https://platform.claude.com/docs/en/api/versioning)  
> 24. [https\://platform.claude.com/docs/en/api/migration-2026-10-21](https://platform.claude.com/docs/en/api/migration-2026-10-21)  
> 25. Function tools with reasoning\_effort are not supported \- AIVAX, [https\://aivax.net/blog/function-tools-reasoning-effort-not-supported-chat-completions/](https://aivax.net/blog/function-tools-reasoning-effort-not-supported-chat-completions/)  
> 26. Provider test fails on official OpenAI preset: chat probe sends, [https\://github.com/yetone/magpie/issues/4454](https://github.com/yetone/magpie/issues/4454)  
> 27. GPT-6 models (gpt-6.1-sol, gpt-6-luna) fail with "max\_tokens not, [https\://github.com/ITSpecialist111/ai\_automation\_suggester/issues/192](https://github.com/ITSpecialist111/ai_automation_suggester/issues/192)  
> 28. Generate content with the Gemini API \- Google Cloud Documentation, [https\://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/models/inference](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/models/inference)  
> 29. Interactions API \- Gemini API \- Google AI Studio, [https\://aistudio.google.com/docs/interactions-overview](https://aistudio.google.com/docs/interactions-overview)  
> 30. Box \- TypeSafe docs, [https\://docs.typesafe.ai/primitives/box](https://docs.typesafe.ai/primitives/box)  
> 31. Jev Choice vs Score vs Noul: the three primitives \| OpenTweet, [https\://opentweet.io/jev/choice-score-noul](https://opentweet.io/jev/choice-score-noul)  
> 32. bug: Ruby 3.4 removed base64 from standard library \#82 \- GitHub, [https\://github.com/cloudevents/sdk-ruby/issues/82](https://github.com/cloudevents/sdk-ruby/issues/82)  
> 33. Ruby 4.0.0 Released, [https\://www\.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/](https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/)  
> 34. Ruby Standard Gems, [https\://stdgems.org/changelog/](https://stdgems.org/changelog/)  
> 35. [https\://rubycoder.ai/item/nu-agent](https://rubycoder.ai/item/nu-agent)  
> 36. Profile of chayut\_o \| RubyGems.org \| your community gem host, [https\://rubygems.org/profiles/chayut\_o](https://rubygems.org/profiles/chayut_o)  
> 37. Ruby AI News \- October 18th, 2025 \- RoboRuby, [https\://rubyai.beehiiv.com/p/ruby-ai-news-october-18th-2025](https://rubyai.beehiiv.com/p/ruby-ai-news-october-18th-2025)  
> 38. Calvin-LL/is-even-ai: Check if a number is even with the power of AI, [https\://github.com/calvin-ll/is-even-ai](https://github.com/calvin-ll/is-even-ai)  
> 39. vibesort : r/ProgrammerHumor \- Reddit, [https\://www\.reddit.com/r/ProgrammerHumor/comments/1mm1i1a/vibesort/](https://www.reddit.com/r/ProgrammerHumor/comments/1mm1i1a/vibesort/)  
> 40. abyesilyurt/vibesort: GPT powered sorting using structured output, [https\://github.com/abyesilyurt/vibesort](https://github.com/abyesilyurt/vibesort)  
> 41. vibesort \- crates.io: Rust Package Registry, [https\://crates.io/crates/vibesort](https://crates.io/crates/vibesort)  
> 42. Profile of philnash \| RubyGems.org \| your community gem host, [https\://rubygems.org/profiles/philnash](https://rubygems.org/profiles/philnash)  
> 43. Posts for 'javascript' \- linksfor.dev(s), [https\://linksfor.dev/tags/javascript](https://linksfor.dev/tags/javascript)  
> 44. TypeSafe \- GitHub, [https\://github.com/typesafe-ai](https://github.com/typesafe-ai)  
> 45. [https\://docs.typesafe.ai/model-jaggedness](https://docs.typesafe.ai/model-jaggedness)  
> 46. Introduction \- TypeSafe, [https\://docs.typesafe.ai/introduction](https://docs.typesafe.ai/introduction)  
> 47. Agent skills for building with TypeSafe's System One API \- GitHub, [https\://github.com/typesafe-ai/skills](https://github.com/typesafe-ai/skills)  
> 48. Commits · typesafe-ai/skills \- GitHub, [https\://github.com/typesafe-ai/skills/commits](https://github.com/typesafe-ai/skills/commits)  
> 49. [https\://docs.typesafe.ai/primitives/choice](https://docs.typesafe.ai/primitives/choice)  
> 50. List models \- TypeSafe docs, [https\://docs.typesafe.ai/api/list-models](https://docs.typesafe.ai/api/list-models)  
> 51. [https\://docs.typesafe.ai/changelog](https://docs.typesafe.ai/changelog)  
> 52. [https\://docs.typesafe.ai/agent-skill](https://docs.typesafe.ai/agent-skill)  
> 53. Quick start \- TypeSafe docs, [https\://docs.typesafe.ai/introduction/quickstart](https://docs.typesafe.ai/introduction/quickstart)  
> 54. Jev 1.14 can look at photos, point at things and read long books, [https\://ai.sulat.com/jev-1-14-can-look-at-photos-point-at-things-and-read-long-books-aeed9151166d](https://ai.sulat.com/jev-1-14-can-look-at-photos-point-at-things-and-read-long-books-aeed9151166d)  
> 55. [https\://docs.typesafe.ai/primitives/advanced](https://docs.typesafe.ai/primitives/advanced)  
> 56. TypeSafe AI Releases Jev 1.14 With Images, Box Type and 262k, [https\://www\.marktechpost.com/2026/10/14/typesafe-ai-jev-1-14-images-box-long-context/](https://www.marktechpost.com/2026/10/14/typesafe-ai-jev-1-14-images-box-long-context/)  
> 57. TypeSafe \- Bifrost AI Gateway, [https\://docs.getbifrost.ai/providers/supported-providers/typesafe](https://docs.getbifrost.ai/providers/supported-providers/typesafe)  
> 58. Noul \- TypeSafe docs, [https\://docs.typesafe.ai/primitives/noul](https://docs.typesafe.ai/primitives/noul)  
> 59. [https\://docs.typesafe.ai/patterns/companion-noul](https://docs.typesafe.ai/patterns/companion-noul)  
> 60. Score \- TypeSafe docs, [https\://docs.typesafe.ai/primitives/score](https://docs.typesafe.ai/primitives/score)  
> 61. Day 0 Support: TypeSafe Jev 1.14: Adds images, box questions, and, [https\://docs.litellm.ai/blog/typesafe\_jev\_images](https://docs.litellm.ai/blog/typesafe_jev_images)  
> 62. [https\://developers.openai.com/api/docs/guides/agents-api/errors](https://developers.openai.com/api/docs/guides/agents-api/errors)  
> 63. [https\://developers.openai.com/api/docs/guides/error-codes](https://developers.openai.com/api/docs/guides/error-codes)  
> 64. [https\://platform.claude.com/docs/en/api/messages](https://platform.claude.com/docs/en/api/messages)  
> 65. [https\://platform.claude.com/docs/en/api/overview](https://platform.claude.com/docs/en/api/overview)  
> 66. [https\://platform.claude.com/docs/en/api/messages/create](https://platform.claude.com/docs/en/api/messages/create)  
> 67. Increase output consistency \- Claude Platform Docs, [https\://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/increase-consistency](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/increase-consistency)  
> 68. Prompting Claude Haiku 5.5 \- Claude Platform Docs, [https\://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5)  
> 69. Claude Adaptive Thinking & Effort 2026: Off Rules by Model, [https\://qcode.cc/en/claude-adaptive-thinking-effort-guide](https://qcode.cc/en/claude-adaptive-thinking-effort-guide)  
> 70. Thinking \- Claude Platform Docs, [https\://platform.claude.com/docs/en/build-with-claude/thinking](https://platform.claude.com/docs/en/build-with-claude/thinking)  
> 71. Claude Haiku 5.5 migration guide, [https\://platform.claude.com/docs/en/models/haiku-5-5/migration-guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide)  
> 72. Effort \- Claude Platform Docs, [https\://platform.claude.com/docs/en/build-with-claude/effort](https://platform.claude.com/docs/en/build-with-claude/effort)  
> 73. [https\://platform.claude.com/docs/en/api/errors](https://platform.claude.com/docs/en/api/errors)  
> 74. Using Gemini API keys \- Google AI Studio, [https\://aistudio.google.com/docs/api-key](https://aistudio.google.com/docs/api-key)  
> 75. Gemini API returns 401 ACCESS\_TOKEN\_TYPE\_UNSUPPORTED, [https\://discuss.ai.google.dev/t/gemini-api-returns-401-access-token-type-unsupported-with-valid-aq-key/188360](https://discuss.ai.google.dev/t/gemini-api-returns-401-access-token-type-unsupported-with-valid-aq-key/188360)  
> 76. Gemini API reference \- Google AI Studio, [https\://aistudio.google.com/api-reference](https://aistudio.google.com/api-reference)  
> 77. [https\://ai.google.dev/api/generate-content](https://ai.google.dev/api/generate-content)  
> 78. Intro to Structured Output with the Gemini API \- Google Colab, [https\://colab.research.google.com/github/GoogleCloudPlatform/generative-ai/blob/main/gemini/controlled-generation/intro\_controlled\_generation.ipynb](https://colab.research.google.com/github/GoogleCloudPlatform/generative-ai/blob/main/gemini/controlled-generation/intro_controlled_generation.ipynb)  
> 79. \`responseSchema\` should be \`response\_json\_schema\` for Google, [https\://github.com/vercel/ai/issues/7689](https://github.com/vercel/ai/issues/7689)  
> 80. A schema in GenerationConfig in the request exceeds the maximum, [https\://github.com/googleapis/js-genai/issues/882](https://github.com/googleapis/js-genai/issues/882)  
> 81. Latest Gemini models \- Gemini API \| Google AI Studio, [https\://aistudio.google.com/docs/latest-model](https://aistudio.google.com/docs/latest-model)  
> 82. Text generation \- Gemini API \| Google AI Studio, [https\://aistudio.google.com/docs/text-generation](https://aistudio.google.com/docs/text-generation)  
> 83. Gemini Interactions API \- Google AI Studio, [https\://aistudio.google.com/api-reference/interactions-api](https://aistudio.google.com/api-reference/interactions-api)  
> 84. Interactions API developer guide \| Gemini Enterprise Agent Platform, [https\://docs.cloud.google.com/gemini-enterprise-agent-platform/models/capabilities/interactions/developer-guide](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/capabilities/interactions/developer-guide)  
> 85. Ruby 4.0.0 preview3 Released, [https\://www\.ruby-lang.org/en/news/2025/12/18/ruby-4-0-0-preview3-released/](https://www.ruby-lang.org/en/news/2025/12/18/ruby-4-0-0-preview3-released/)  
> 86. [https\://developers.openai.com/api/docs/models/gpt-6-luna](https://developers.openai.com/api/docs/models/gpt-6-luna)  
> 87. Create a model response \| OpenAI API Reference, [https\://developers.openai.com/api/reference/resources/responses/methods/create/](https://developers.openai.com/api/reference/resources/responses/methods/create/)  
> 88. Migrate to the Responses API \- OpenAI Developers, [https\://developers.openai.com/api/docs/guides/migrate-to-responses](https://developers.openai.com/api/docs/guides/migrate-to-responses)  
> 89. json\_schema fallback doesn't trigger on Ollama's "structured output, [https\://github.com/houtini-ai/houtini-lm/issues/47](https://github.com/houtini-ai/houtini-lm/issues/47)  
> 90. Gemified in 3.4 \- Ruby Standard Gems, [https\://stdgems.org/new-in/3.4/](https://stdgems.org/new-in/3.4/)  
> 91. the-ultimate-guide-to-ruby-timeouts/README.md at master \- GitHub, [https\://github.com/ankane/the-ultimate-guide-to-ruby-timeouts/blob/master/README.md](https://github.com/ankane/the-ultimate-guide-to-ruby-timeouts/blob/master/README.md)  
> 92. How to specify a read timeout for a Net::HTTP::Post.new request in, [https\://stackoverflow.com/questions/19547184/how-to-specify-a-read-timeout-for-a-nethttppost-new-request-in-ruby-2](https://stackoverflow.com/questions/19547184/how-to-specify-a-read-timeout-for-a-nethttppost-new-request-in-ruby-2)  
> 93. Class: Net::HTTP – Documentation for net (4.0.0) \- RubyDoc.info, [https\://www\.rubydoc.info/stdlib/net/Net/HTTP](https://www.rubydoc.info/stdlib/net/Net/HTTP)  
> 94. Project: rack-proxy \- The Ruby Toolbox, [https\://www\.ruby-toolbox.com/projects/rack-proxy](https://www.ruby-toolbox.com/projects/rack-proxy)  
> 95. [https\://platform.claude.com/docs/en/manage-claude/compliance-errors](https://platform.claude.com/docs/en/manage-claude/compliance-errors)  
> 96. API errors \| Gemini Enterprise Agent Platform, [https\://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/models/api-errors](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/models/api-errors)  
> 97. Introducing Structured Outputs in the API \- OpenAI, [https\://openai.com/index/introducing-structured-outputs-in-the-api/](https://openai.com/index/introducing-structured-outputs-in-the-api/)  
> 98. OpenAI Responses API vs Chat Completions: Migrate and Test, [https\://benchlm.ai/blog/posts/chat-completions-to-responses-api](https://benchlm.ai/blog/posts/chat-completions-to-responses-api)  
> 99. Gemini Decision 1 at \$0.10 per 1M input tokens, free output, [https\://www\.datastudios.org/post/google-gemini-decisions-api-gemini-decision-1-0-10-input-free-output](https://www.datastudios.org/post/google-gemini-decisions-api-gemini-decision-1-0-10-input-free-output)

