# CAI Community Runtime — OpenCode with Qwen via Cloudera AI Inference

Run [OpenCode](https://github.com/anomalyco/opencode) (open-source terminal coding agent) inside a **Cloudera AI (CAI)** workspace. The model runs on **Cloudera AI Inference service (CAII)** using its **OpenAI-compatible generative API** ([overview](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-use-caii.html)); this image does **not** bundle local GPU inference.

---

## What you can deploy on CAII (relevant to Qwen)

Per [Supported Model Artifact Formats](https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-supported-model-artifact-formats.html), CAII supports:

- **NVIDIA NIM**–packaged LLMs (and other modalities).
- **Hugging Face transformer** models served by the **vLLM** engine.
- **ONNX** predictive models from Cloudera AI Workbench (not applicable to Qwen chat).

You **cannot** assume arbitrary artifacts (for example **GGUF-only** checkpoints for llama.cpp) are importable into CAII; align with the formats above and your platform’s Model Hub entries.

To pull a Hugging Face model into the registry, use **Model Hub → Import** ([doc](https://docs.cloudera.com/machine-learning/cloud/model-hub/topics/ml-import-model-hugging-face.html), technical preview). Gated models need an HF token and license acceptance on huggingface.co.

---

## Recommended Qwen repos for coding (HF `Qwen` org)

Pick a repo that matches **your GPU / optimization profile** after import; these are coding-focused lines on [huggingface.co/Qwen](https://huggingface.co/Qwen):

1. **`Qwen/Qwen3-Coder-30B-A3B-Instruct`** — **Practical default** for CAII + vLLM: MoE coding model, strong quality, size that many enterprise GPU footprints can serve. Use the **`‑FP8`** variant from the same family if your operator recommends FP8 for throughput.

2. **`Qwen/Qwen3-Coder-Next`** — **Newest agent-oriented coding** release in the Qwen3-Coder line (aimed at coding agents / long context). It is **large (~80B parameters in the public card)**; only choose it if your CAII sizing and vLLM/transformers stack explicitly support it.

3. **`Qwen/Qwen2.5-Coder-32B-Instruct`** — **Conservative** choice if you need maximum compatibility with older vLLM stacks; still excellent for code.

Your **OpenCode `CAII_MODEL`** value must be whatever id your CAII **OpenAI** route expects (often the registered model name or Hugging Face repo id), not necessarily the HF URL alone.

---

## Using the image in CAI

### 1. Register the runtime

**Admin → Runtime Catalog → Add Runtime** and enter your built image tag.

### 2. Configure environment variables (project or session)

| Variable | Description |
|----------|-------------|
| `CAII_OPENAI_BASE_URL` | OpenAI-compatible **base URL including `/v1`** for your inference route (see CAII / KServe OpenAI docs for your deployment). |
| `CAII_API_TOKEN` | Bearer token your gateway expects (store as a secret in CML where possible). |
| `CAII_MODEL` | Model id string for `POST .../chat/completions` (must match the served model name). |

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

---

## Building the image

```bash
docker build --pull --rm \
  -f Dockerfile \
  -t <your-registry>/cai-opencode-qwen-caii:2.0.0 .
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
