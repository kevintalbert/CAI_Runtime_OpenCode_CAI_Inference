# CAI Community Runtime — OpenCode with Cloudera AI Inference

Run [OpenCode](https://github.com/anomalyco/opencode) (open-source terminal coding agent) inside a **Cloudera AI (CAI)** workspace. Point it at **Cloudera AI Inference (CAII)** using an **OpenAI-compatible** route ([overview](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-use-caii.html)). **You choose the model** your CAII deployment serves (Hugging Face + vLLM, NVIDIA NIM, or other supported formats); this image wires OpenCode to that endpoint and does **not** bundle local GPU inference.

---

## What you can deploy on CAII

Per [Supported Model Artifact Formats](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-supported-model-artifact-formats.html), CAII supports:

- **NVIDIA NIM**–packaged LLMs (and other modalities).
- **Hugging Face transformer** models served by the **vLLM** engine.
- **ONNX** predictive models from Cloudera AI Workbench (typically not used for chat-style coding agents).

You **cannot** assume arbitrary artifacts (for example **GGUF-only** checkpoints for llama.cpp) are importable into CAII; align with the formats above and your platform’s Model Hub entries.

To pull a Hugging Face model into the registry, use **Model Hub → Import** ([doc](https://docs.cloudera.com/machine-learning/cloud/model-hub/topics/ml-import-model-hugging-face.html), technical preview). Gated models need an HF token and license acceptance on huggingface.co.

---

## Choosing and sizing a model

1. **Register what CAII can serve** — Pick a checkpoint or NIM product that matches your **CAII Hugging Face / NIM runtime** versions (vLLM, transformers, CUDA). If the engine is too old for the model’s requirements, the endpoint will fail at startup regardless of GPU size.

2. **`CAII_MODEL` must match the route** — Use the exact model id your **OpenAI**-compatible route expects (often the Hugging Face repo id for HF imports, or the name shown in **Test Model** / your operator’s docs for NIM).

3. **Read the model card or vendor docs** — Note **tensor parallel** recommendations, **max context**, **precision** (e.g. FP8 variants), and whether the checkpoint is **multimodal** (vision encoder VRAM) vs **language-only**.

4. **Tool calling** — If you want OpenCode’s agent-style **function calling**, the server must expose OpenAI-compatible tools with matching **vLLM** (or NIM) flags. See [OpenCode error: tool choice](#opencode-error-auto-tool-choice-requires---enable-auto-tool-choice-and---tool-call-parser) below.

---

## Sizing tips (typical HF + vLLM on CAII)

These apply to **any** large language model you serve; substitute flags from **your** model’s documentation where examples use placeholders.

### If you have **2× GPU** (e.g. 2× L40S on `g6e.12xlarge`)

1. **Resource profile** — Request **2 GPUs** on the endpoint so the pod actually sees two devices.

2. **Tensor parallel** — Set **`--tensor-parallel-size 2`** in **vLLM Args** so weights shard across **both** GPUs. Without this, vLLM often loads on **one** GPU and you get **OOM** or unstable behavior.

3. **Context cap** — Do **not** start with the largest context the model card mentions unless you have verified KV cache headroom. Begin with a **moderate** **`--max-model-len`** (for example **32768** or **65536**) and **raise only after** `kserve-container` logs show stable headroom. KV cache grows with context; this is usually the first knob when 2× GPU is “enough for weights” but not for long chats.

4. **Precision** — Prefer an **FP8** (or other quantized) registry variant when Model Hub lists one; it often improves fit vs BF16 on **2×48 GB**-class setups.

5. **Multimodal models** — If you only need **text / code**, many vLLM builds support **`--language-model-only`** (or equivalent) so the vision stack is skipped and VRAM goes to the LM + KV. Confirm in your model card and vLLM version.

6. **OpenCode + tools** — When CAII allows vLLM args, set **`--enable-auto-tool-choice`** and a **`--tool-call-parser`** value that matches **your** model family (see [vLLM tool calling](https://docs.vllm.ai/en/latest/features/tool_calling/)). Example shape (values are illustrative—copy from your model card, not this README):

   ```text
   --tensor-parallel-size 2 --max-model-len 65536 --enable-auto-tool-choice --tool-call-parser <parser-from-model-card>
   ```

   Tune **`--max-model-len`** and precision flags per your OOM logs. If you **cannot** set server args, use this repo’s default **`tool_call: false`** (see below) so OpenCode still talks to the model.

7. **If it still does not fit** — Reduce **`max-model-len`**, use a smaller / more efficient checkpoint, or switch to **NIM** if your org offers a suitable curated bundle.

---

## When an HF + vLLM model stays **In-progress** (503 / 500 / restarts)

Adding **CPU/RAM** alone rarely fixes HF+vLLM startup failures. The predictor pod can still return **503** (not ready) or **500** (application error) while **`kserve-container`** crashes, restarts, or never finishes loading the engine.

### 1. Read **`kserve-container` logs** first

In CAII, open **Logs** for the main app container (not only `queue-proxy` / Istio). Search for **`CUDA out of memory`**, **`OOM`**, **`EngineDeadError`**, **`ImportError`**, **`ValueError`**, or **unsupported architecture**. That single source usually tells you whether the issue is **VRAM**, **vLLM/transformers compatibility**, or **model config**.

### 2. Two GPUs do not automatically split the model

If your **resource profile** requests **2× GPU**, vLLM still defaults to **tensor parallel size 1** unless you tell it otherwise. The server may keep loading the **full** weights onto **one** GPU (same failure mode as before).

In **Advanced Options → vLLM Args** (exact syntax depends on your CAII / Hugging Face server version—confirm in Cloudera docs), you typically need **tensor parallelism across both devices**, for example:

```text
--tensor-parallel-size 2
```

If your UI expects a different delimiter or multiple lines, follow the product documentation for **huggingface (KServe) vLLM arguments**.

Also consider capping context so KV cache fits after load, for example:

```text
--max-model-len 32768
```

(Tune down if you still hit OOM after weights load.)

### 3. Try a different **model artifact** (easier to serve or better match)

| Approach | Typical id / source | When to use |
|----------|---------------------|-------------|
| **Smaller HF checkpoint** | Any compact instruct or coder model your registry lists | Proves **HF + vLLM + OpenCode** end-to-end before scaling up. |
| **FP8 or other efficient variant** | Same model family with a lighter weight tag in Model Hub | When BF16/full weights do not fit your GPU profile. |
| **Newer stack or different checkpoint** | Another release that matches your pinned **vLLM** image | When logs show **version / architecture** mismatches. |
| **NVIDIA NIM** | Curated models your org exposes | If [NIM](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-supported-model-artifact-formats.html) is available, it can avoid “latest HF + pinned vLLM” mismatches. |

### 4. **500** vs **503** in readiness probes

- **503** often means “server not ready yet” **or** repeatedly failing readiness while the process restarts.
- **500** usually means the HTTP server answered but the **health / ready handler hit an internal error**—again, **`kserve-container` logs** are decisive.

### 5. OpenCode side

None of this changes how you set **`CAII_OPENAI_BASE_URL`**, **`CAII_API_TOKEN`**, and **`CAII_MODEL`** once the endpoint is **Ready** and **Test Model** succeeds. Until then, fix serving first; OpenCode is not the bottleneck.

---

## Using the image in CAI

### 1. Register the runtime

**Admin → Runtime Catalog → Add Runtime** and enter your built image tag.

### 2. Configure environment variables (project or session)

| Variable | Description |
|----------|-------------|
| `CAII_OPENAI_BASE_URL` | OpenAI-compatible **base URL including `/v1`** for your inference route (see CAII / KServe OpenAI docs for your deployment). |
| `CAII_API_TOKEN` | Bearer token your gateway expects (store as a secret in CML where possible). |
| `CAII_MODEL` | Model id for `POST .../chat/completions` (must match the served name—often the HF repo id or the NIM model name your route registers). |
| `CAII_MODEL_SUPPORTS_TOOLS` | Optional. Set to `true` / `1` / `yes` only if your CAII deployment enables tool calling (`--enable-auto-tool-choice` and a compatible `--tool-call-parser` for vLLM, or equivalent for NIM). If unset, this runtime writes **`"tool_call": false`** for the CAII model so OpenCode avoids `tool_choice: "auto"` (see below). |

### 3. Start OpenCode

In a terminal:

```bash
opencode-caii
```

That writes `~/.config/opencode/opencode.json` from the env vars (credentials stay in `{env:...}` indirection) and launches OpenCode. You can also run `opencode-sync-config` once, then `opencode` normally.

For non-interactive use:

```bash
opencode-caii run "Summarize this repository."
```

See [OpenCode install & config](https://opencode.ai/docs) and [providers / custom OpenAI-compatible endpoints](https://opencode.ai/docs/providers).

### OpenCode error: `"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser`

OpenCode is a **coding agent**: it sends **OpenAI tool / function-calling** traffic (`tool_choice: "auto"`). **vLLM** only accepts that if the server was started with **tool-call** flags. **NIM** endpoints often ship with this already wired; **Hugging Face + vLLM** deployments on CAII usually **do not**, so chat fails even when the endpoint is **Running**.

**Fix (CAII → model version → Advanced Options → vLLM Args):** add at least:

```text
--enable-auto-tool-choice --tool-call-parser hermes
```

The **`hermes`** parser is a common default for many instruction-tuned models on vLLM; it is **not** universal. For your exact checkpoint, use the **model card** and [vLLM tool calling](https://docs.vllm.ai/en/latest/features/tool_calling/) to pick the supported **`--tool-call-parser`** (and any **`--reasoning-parser`** or related flags your stack documents).

Exact flag names and supported parser values depend on the **vLLM version** inside your **huggingface** runtime image (`huggingfaceserver:…`). If a parser is rejected at startup, check that image’s vLLM release notes or try the closest option your version lists (`vllm serve --help` in a debug context). Redeploy the model after saving vLLM args.

#### If you **cannot** change CAII (OpenCode–only workaround)

This repository’s `opencode-sync-config` / `opencode-caii` writes `provider.caii.models.<CAII_MODEL>.**tool_call**: **false** by default. OpenCode uses that flag to treat the model as **not tool-capable**, which avoids sending the OpenAI **`tool_choice: "auto"`** pattern that triggers the vLLM error above.

**Trade-off:** you lose **agentic tool use** against that endpoint (no automatic `read` / `edit` / `bash` over the wire in the same way). You still get a useful **chat-style** assistant inside OpenCode for questions and explanations.

After someone enables tool calling on the server, set **`CAII_MODEL_SUPPORTS_TOOLS=true`**, run **`opencode-sync-config`** again, and restart OpenCode so the generated config **omits** `tool_call: false`.

---

## Building the image

The Dockerfile sets Cloudera runtime labels: **edition** `opencode`, **full-version** `2.0.1-opencode` (short **2.0**, maintenance **1**). Use any registry tag you prefer; the example below matches that release.

```bash
docker build --pull --rm \
  -f Dockerfile \
  -t <your-registry>/cai-opencode:2.0.1 .
```

---

## Repository structure

```
Dockerfile          CAI JupyterLab runtime + Node 20 + OpenCode + ttyd
scripts/startup.sh  Profile hook: CAII env banner, opencode-caii / opencode-sync-config
```

---

## License

MIT © 2026 Kevin Talbert
