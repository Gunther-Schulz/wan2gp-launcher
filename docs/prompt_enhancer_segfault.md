# Prompt Enhancer Post-Generation Segfault

## Symptom

After using the Qwen3.5 prompt enhancer, the enhanced prompt appears in the webui normally, then the process crashes with a segfault a few seconds later:

```
Hooked to model 'prompt_enhancer_llm_model' (Qwen3_5ForCausalLM)
Generating: 100%|████...| 1/1 [00:06<00:00, 6.24s/steps, Prefill=1577tok/s, Decode=22tok/s]

./run-wan2gp-conda.sh: line 1794: 2248103 Segmentation fault (core dumped) "${python_cmd}" -u wgp.py ...
```

Generation completes successfully. The crash happens during cleanup, not during inference.

## Affected path

Qwen3.5 prompt enhancer (enhancer_enabled = 3 or 4) using the nanovllm engine with CUDA graphs enabled (the default).

Florence2 / Llama3.2 / JoyCaption enhancers (enhancer_enabled = 1 or 2) are not affected.

## Root cause analysis

### Execution flow

1. `enhance_prompt()` (wgp.py) calls `process_prompt_enhancer()` → `generate_cinematic_prompt()` → `model.generate_messages()` → `_generate_messages_vllm()` → `engine._llm.generate()`.
2. On the first call, `LLMEngine.generate()` calls `ModelRunner.ensure_runtime_ready()`, which:
   - Allocates the KV cache on GPU (`self.kv_cache = torch.empty(..., device="cuda")`)
   - Injects KV cache views into every attention module (`module.k_cache`, `module.v_cache`)
   - Captures CUDA graphs for all decode batch sizes via `capture_cudagraph()`
3. Generation runs to completion. The progress bar reaches 100%.
4. Back in `enhance_prompt()`, two cleanup calls are made in sequence:
   ```python
   unload_prompt_enhancer_runtime()   # wgp.py:5581
   enhancer_offloadobj.unload_all()   # wgp.py:5582
   ```

### What `unload_prompt_enhancer_runtime()` does

Calls `model.unload()` → `_unload_prompt_enhancer_text_runtime()` → `engine.close()`, which chains through:

1. `NanoVllmTextEngine.close()` → `LLMEngine.close()` → `ModelRunner.reset_runtime_state()`:
   - Replaces `module.k_cache` / `module.v_cache` with empty CPU tensors on every attention layer
   - `del self.kv_cache` — frees the KV cache allocation from GPU
   - `self.clear_graph_cache()` — drops all cached `CUDAGraph` objects
   - `torch.cuda.synchronize()` + `torch.cuda.empty_cache()`
2. `LLMEngine.exit()` → `ModelRunner.exit()`:
   - `_release_sample_buffers()` — frees pinned CPU tensors used for decode batching
   - `self.model = None`
   - `del self.graphs`, `del self.graph_pool` (if any remain)
   - `torch.cuda.synchronize()` + `torch.cuda.empty_cache()`
3. Back in `_unload_prompt_enhancer_text_runtime()`:
   - **`gc.collect()` is called** (qwen35_text.py:657)
   - *Then* `torch.cuda.synchronize()` — note: GC runs before sync

### Probable crash point: `enhancer_offloadobj.unload_all()`

After all nanovllm cleanup above, `enhancer_offloadobj.unload_all()` is called. This is mmgp's operation to move the Qwen model weights from GPU back to its pinned RAM block (the "35 large blocks / 8607.69 MB" shown at startup).

The crash most likely occurs here due to one or both of the following:

#### Issue 1 — CUDA graph memory pool vs mmgp offload ordering

During `capture_cudagraph()`, CUDA graphs are captured against specific GPU memory addresses. With `model._budget = 0` and `_offload_hooks = ["forward"]`, mmgp intercepts the model's `forward` method. If mmgp moves model weights to a different GPU address between the warmup pass and the capture pass (or between capture and the first decode replay), the captured addresses are stale. On replay, CUDA accesses those stale addresses → segfault.

This is a fundamental incompatibility between dynamic offloading hooks and CUDA graph capture: CUDA graphs require that all captured memory addresses remain valid and at the same location for the entire lifetime of the graph.

#### Issue 2 — gc.collect() before torch.cuda.synchronize()

In `_unload_prompt_enhancer_text_runtime` (qwen35_text.py:657):

```python
gc.collect()                     # ← runs first
if torch.cuda.is_available():
    torch.cuda.synchronize()     # ← runs after GC
```

Python's garbage collector may finalize CUDA-backed objects (`LLMEngine`, `CUDAGraph`, tensor views) before the CUDA device is fully synchronised with the host. If any CUDA operations triggered by object destruction (graph destruction, async D2H copies) race with mmgp's subsequent `unload_all()` DMA transfer, the result is a use-after-free on the device.

The `synchronize()` call should precede `gc.collect()`.

#### Issue 3 — Duplicate cleanup passes

`ModelRunner.reset_runtime_state()` is called twice: once via `LLMEngine.close()` and once via `ModelRunner.exit()`. The second call returns early (`_runtime_ready = False`) so it is harmless, but the pattern creates fragile ordering between the two passes and the subsequent mmgp `unload_all()`.

## Mitigation

### Workaround (implemented): `--no-cudagraph-enhancer`

Passing `--no-cudagraph-enhancer` to the launcher sets:

```bash
export WGP_QWEN35_PROMPT_ENHANCER_VLLM_CUDAGRAPH=0
```

This sets `enforce_eager=True` in the nanovllm engine for the prompt enhancer, skipping CUDA graph capture entirely. The model runs in eager mode — every decode step calls the model directly instead of replaying a graph. This removes the CUDA graph lifecycle from the cleanup path and eliminates the crash.

**Status: confirmed working.** The segfault no longer occurs with this flag set.

**Performance impact:** modest. CUDA graph replay saves ~1-2 ms per decode step. For a 512-token prompt enhancement this is on the order of a few seconds total throughput loss — acceptable given the alternative is a hard crash.

### Alternative workaround: `lm_decoder_engine = "legacy"`

Set in `wan2gp-content/server_config.json`:

```json
"lm_decoder_engine": "legacy"
```

This resolves to the same `enforce_eager=True` path as `--no-cudagraph-enhancer`.

### Proper fix (upstream)

A correct fix requires changes to the Wan2GP source in `shared/prompt_enhancer/qwen35_text.py` and `shared/llm_engines/nanovllm/engine/model_runner.py`:

1. **Swap gc/sync order** in `_unload_prompt_enhancer_text_runtime`:
   ```python
   # Before:
   gc.collect()
   if torch.cuda.is_available():
       torch.cuda.synchronize()

   # After:
   if torch.cuda.is_available():
       torch.cuda.synchronize()
   gc.collect()
   ```

2. **Pin model weights on GPU for CUDA graph lifetime.** If mmgp offload hooks are active, CUDA graph capture should be either disabled or the model weights should be locked to GPU (preventing offload) from the point of capture until the engine is closed. The `_budget = 0` setting conflicts with CUDA graph capture.

3. **Single cleanup pass.** Consolidate `reset_runtime_state()` + `exit()` so cleanup logic runs once, with a single `torch.cuda.synchronize()` at the end before any Python GC or mmgp operations.
