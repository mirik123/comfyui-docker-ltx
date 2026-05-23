# RunPod ComfyUI LTX-2.3 Template

Docker-ready RunPod template for ComfyUI + LTX-2.3 + IC-LoRA control workflows.

## Build

```bash
docker build -t your-dockerhub-user/runpod-comfyui-ltx:latest .
docker push your-dockerhub-user/runpod-comfyui-ltx:latest
```

Build with SageAttention:

```bash
docker build --build-arg INSTALL_SAGE_ATTENTION=true -t your-dockerhub-user/runpod-comfyui-ltx:sage .
```

## RunPod port

Expose HTTP port `8188`.

## Manual model download

Model download is intentionally manual, not automatic at Pod startup:

```bash
MODELS_CONFIG_URL=/workspace/models_config.json python /notebooks/download_models.py
```

Force re-download:

```bash
FORCE_MODEL_DOWNLOAD=true MODELS_CONFIG_URL=/workspace/models_config.json python /notebooks/download_models.py
```

Dry run:

```bash
DRY_RUN=true MODELS_CONFIG_URL=/workspace/models_config.json python /notebooks/download_models.py
```

Use a Hugging Face token if needed:

```bash
HF_TOKEN=hf_xxx MODELS_CONFIG_URL=/workspace/models_config.json python /notebooks/download_models.py
```

The downloader writes into `/workspace/models/<category>`, matching `/workspace/extra_model_paths.yaml`.

## Runtime storage

```text
/opt/ComfyUI        image-baked clean copy
/workspace/ComfyUI persistent editable copy
/workspace/models  persistent models
/workspace/input   input assets
/workspace/output  generations
/workspace/cache   HF/torch/triton caches
```

On first Pod start, `start.sh` copies `/opt/ComfyUI` to `/workspace/ComfyUI`.
