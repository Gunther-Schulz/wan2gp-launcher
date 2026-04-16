# Qwen3.5 VL Image Captioning: CPU Device Bug

## Symptom

When using the Qwen3.5 prompt enhancer in image ("I") or text+image ("TI") mode, the output is
completely unrelated to the input image. The text-only ("T") mode works correctly. Florence2
works correctly in all modes.

## Affected path

Qwen3.5 VL prompt enhancer (enhancer_enabled = 3 or 4) in any mode that includes an image
("I" or "TI"). Triggered whenever `_use_vllm_prompt_enhancer` returns True, which is any time
the nanovllm engine is active — including when `--no-cudagraph-enhancer` is set.

## Root cause

### Bug location

`shared/prompt_enhancer/qwen35_vl.py` — `_resolve_execution_device()` (line 305).

```python
def _resolve_execution_device(self, model_inputs=None) -> torch.device:
    if model_inputs is not None:
        for value in model_inputs.values():
            if torch.is_tensor(value):
                return value.device   # ← Returns CPU immediately (processor outputs CPU tensors)
    if torch.cuda.is_available():
        return torch.device("cuda", ...)  # ← Never reached in vllm path
```

The HuggingFace processor (`Qwen2VLProcessor`) always returns CPU tensors. The function finds
the first tensor and returns its device — CPU — before reaching the CUDA fallback. All image
inputs are then processed on CPU.

### Execution trace

1. `_generate_image_captions_vllm()` (qwen35_vl.py:680):
   - Calls `processor(text=..., images=..., return_tensors="pt")` → CPU tensors
   - Calls `_prepare_multimodal_vllm_prompt(self, model_inputs)` with CPU model_inputs

2. `_prepare_multimodal_vllm_prompt()` (qwen35_vl.py:633):
   - Line 635: `_move_batch_to_device(model_inputs, _resolve_execution_device(self, model_inputs))`
     → moves all inputs to CPU (they're already there)
   - Calls `runtime_model.model.get_image_features(pixel_values, ...)` with CPU `pixel_values`
   - Computes `inputs_embeds` on CPU
   - Returns `prompt_embeds` as a CPU tensor

3. `generate_embedded()` (vllm_support.py:434):
   - Receives CPU `prompt_embeds`, passes through to `LLMEngine.generate_embedded()` without
     any device transfer

4. `LLMEngine.generate_embedded()` (llm_engine.py:296):
   - Calls `add_request(..., prompt_embeds=embeds)` — stores CPU embeds in the Sequence object

5. `ModelRunner.prepare_prefill()` (model_runner.py:589):
   ```python
   inputs_embeds = torch.cat(prompt_embeds, dim=0).unsqueeze(0).contiguous()
   ```
   No `.cuda()` call. CPU `inputs_embeds` returned.

6. `ModelRunner.run_model()` (model_runner.py:661):
   ```python
   if inputs_embeds is not None:
       model_kwargs["inputs_embeds"] = inputs_embeds   # CPU tensor passed to GPU model
   ```
   Model weights are on GPU (mmgp loads them for the forward pass). CPU `inputs_embeds` is
   passed to a GPU model → either an error (if PyTorch catches the mismatch) or silent
   incorrect computation (if `inputs_embeds` somehow runs on CPU while model weights are on GPU,
   producing garbage activations).

### Why the non-vllm path works

`_generate_image_captions()` (qwen35_vl.py:744) — the non-vllm fallback:

```python
device = torch.device("cuda", torch.cuda.current_device()) if torch.cuda.is_available() else torch.device("cpu")
model_inputs = _move_batch_to_device(model_inputs, device)
```

This explicitly moves all inputs to CUDA before running the model. This path is only used when
`_use_vllm_prompt_enhancer` returns False (engine_name not in `("cg", "vllm")`), which does
not happen under normal configurations.

### Why the "T" mode is unaffected

Text-only mode (`_generate_t2v_prompt`) never calls `_generate_image_captions_vllm` and never
goes through `generate_embedded`. It calls `engine._llm.generate()` with token IDs only
(no `inputs_embeds`), so there is no device mismatch.

### Why `--no-cudagraph-enhancer` does not fix this

`--no-cudagraph-enhancer` sets `WGP_QWEN35_PROMPT_ENHANCER_VLLM_CUDAGRAPH=0`, which sets
`enforce_eager=True` but leaves `engine_name = "cg"`. `_use_vllm_prompt_enhancer()` checks
`engine_name in ("cg", "vllm")` → still True → the vllm image captioning path is still used.
The flag only disables CUDA graph capture; it does not change the image captioning device.

## Effect on output

The IT2V system prompt (`IT2V_CINEMATIC_PROMPT`) explicitly prioritizes the image caption:

> "Image description should be in first priority! Align to the image caption if it contradicts
> the user text input."

When the image caption is garbage (from CPU-mode inference) or empty, the text model generates
output based on that garbage caption, completely ignoring both the image and the user's text.
The result appears random and unrelated to either input.

## Proper fix (upstream)

Change `_resolve_execution_device()` to always return CUDA when available, regardless of what
device the input tensors are currently on:

```python
# In shared/prompt_enhancer/qwen35_vl.py

def _resolve_execution_device(self, model_inputs=None) -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda", torch.cuda.current_device())
    return torch.device("cpu")
```

Or, more targeted: in `_generate_image_captions_vllm()`, replace the call to
`_resolve_execution_device` with an explicit CUDA device (mirroring the non-vllm path at
line 744):

```python
# Before:
model_inputs = _move_batch_to_device(model_inputs, _resolve_execution_device(self, model_inputs))

# After:
device = torch.device("cuda", torch.cuda.current_device()) if torch.cuda.is_available() else torch.device("cpu")
model_inputs = _move_batch_to_device(model_inputs, device)
```

The same one-line fix applies inside `_prepare_multimodal_vllm_prompt()` at line 635.

## Workaround

None available without code changes. The image enhancer modes ("I", "TI") with Qwen3.5 produce
incorrect output under all current configurations.

Use Florence2 (enhancer_enabled = 1 or 2) for image-based prompt enhancement — it does not
use the vllm captioning path and works correctly.
