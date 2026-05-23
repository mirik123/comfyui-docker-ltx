# RunPod ComfyUI LTX-2.3 Template with Optional SageAttention

## What `--extra-model-paths-config` does

The template writes:

```text
/workspace/extra_model_paths.yaml
```

Then starts ComfyUI with:

```bash
python main.py --extra-model-paths-config /workspace/extra_model_paths.yaml
```

This tells ComfyUI to search `/workspace/models/...` in addition to its normal `ComfyUI/models/...` folders.

It does not download or validate models. It only maps model categories to persistent folders.

Example:

```yaml
runpod_network_volume:
  base_path: /workspace/models
  checkpoints: checkpoints
  loras: loras
  vae: vae
```

This means:

```text
checkpoints -> /workspace/models/checkpoints
loras       -> /workspace/models/loras
vae         -> /workspace/models/vae
```

## Why SageAttention is optional

SageAttention can speed up attention-heavy video workflows, but it is sensitive to:

- Python version
- PyTorch version
- CUDA version
- GPU architecture
- wheel availability

Build with SageAttention:

```bash
docker build \
  --build-arg INSTALL_SAGE_ATTENTION=true \
  -t your-image:ltx23 .
```

Build with a specific wheel:

```bash
docker build \
  --build-arg INSTALL_SAGE_ATTENTION=true \
  --build-arg SAGEATTENTION_WHEEL_URL="https://..." \
  -t your-image:ltx23 .
```

Run with SageAttention enabled:

```bash
USE_SAGE_ATTENTION=true
```

The start script only passes `--use-sage-attention` if `import sageattention` works.
