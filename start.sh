#!/usr/bin/env bash
set -euo pipefail

export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
export IMAGE_COMFY_DIR="${IMAGE_COMFY_DIR:-/opt/ComfyUI}"
export LOG_DIR="${LOG_DIR:-$WORKSPACE_DIR/logs}"
export COMFY_LOG_PATH="${COMFY_LOG_PATH:-$LOG_DIR/comfyui.log}"

export UPDATE_ON_START="${UPDATE_ON_START:-false}"
export INSTALL_MISSING_DEPS_ON_START="${INSTALL_MISSING_DEPS_ON_START:-false}"
export RESET_COMFY_FROM_IMAGE="${RESET_COMFY_FROM_IMAGE:-false}"
export USE_SAGE_ATTENTION="${USE_SAGE_ATTENTION:-false}"

export TORCH_FORCE_WEIGHTS_ONLY_LOAD="${TORCH_FORCE_WEIGHTS_ONLY_LOAD:-1}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-max_split_size_mb:512}"

export HF_HOME="${HF_HOME:-$WORKSPACE_DIR/cache/huggingface}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HF_HOME/hub}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$WORKSPACE_DIR/cache/pip}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$WORKSPACE_DIR/cache/uv}"
export TORCH_HOME="${TORCH_HOME:-$WORKSPACE_DIR/cache/torch}"
export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-$WORKSPACE_DIR/cache/triton}"
export TORCH_EXTENSIONS_DIR="${TORCH_EXTENSIONS_DIR:-$WORKSPACE_DIR/cache/torch_extensions}"
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-$WORKSPACE_DIR/cache/torchinductor}"

MODEL_DIRS=(checkpoints checkpoints/LTX-Video vae diffusion_models unet text_encoders clip clip_vision loras controlnet upscale_models latent_upscale_models embeddings)

log() { echo "[$(date --iso-8601=seconds)] $*" | tee -a "$COMFY_LOG_PATH"; }

mkdir -p "$WORKSPACE_DIR" "$LOG_DIR" "$WORKSPACE_DIR/cache" "$WORKSPACE_DIR/models" "$WORKSPACE_DIR/input" "$WORKSPACE_DIR/output" "$WORKSPACE_DIR/workflows"
touch "$COMFY_LOG_PATH"

for d in "${MODEL_DIRS[@]}"; do mkdir -p "$WORKSPACE_DIR/models/$d"; done
mkdir -p "$HF_HOME" "$HUGGINGFACE_HUB_CACHE" "$PIP_CACHE_DIR" "$UV_CACHE_DIR" "$TORCH_HOME" "$TRITON_CACHE_DIR" "$TORCH_EXTENSIONS_DIR" "$TORCHINDUCTOR_CACHE_DIR"

if [ ! -e /runpod-volume ]; then ln -s "$WORKSPACE_DIR" /runpod-volume 2>/dev/null || true; fi
if [ ! -f "$WORKSPACE_DIR/models_config.json" ] && [ -f /notebooks/models_config.json ]; then cp /notebooks/models_config.json "$WORKSPACE_DIR/models_config.json"; fi

if [ "$RESET_COMFY_FROM_IMAGE" = "true" ]; then
  log "RESET_COMFY_FROM_IMAGE=true: replacing $COMFY_DIR with image copy"
  rm -rf "$COMFY_DIR"
fi

if [ ! -f "$COMFY_DIR/main.py" ]; then
  log "Seeding ComfyUI from $IMAGE_COMFY_DIR to persistent Network Volume: $COMFY_DIR"
  mkdir -p "$COMFY_DIR"
  rsync -a "$IMAGE_COMFY_DIR/" "$COMFY_DIR/"
else
  log "Using persistent ComfyUI at $COMFY_DIR"
fi

mkdir -p "$COMFY_DIR/input" "$COMFY_DIR/output" "$COMFY_DIR/user" "$COMFY_DIR/models"
if [ ! -L "$COMFY_DIR/input" ]; then rm -rf "$COMFY_DIR/input"; ln -s "$WORKSPACE_DIR/input" "$COMFY_DIR/input"; fi
if [ ! -L "$COMFY_DIR/output" ]; then rm -rf "$COMFY_DIR/output"; ln -s "$WORKSPACE_DIR/output" "$COMFY_DIR/output"; fi

EXTRA_MODEL_PATHS="$WORKSPACE_DIR/extra_model_paths.yaml"
cat > "$EXTRA_MODEL_PATHS" <<YAML
runpod_network_volume:
  base_path: $WORKSPACE_DIR/models
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  unet: unet
  vae: vae
  text_encoders: text_encoders
  clip: clip
  clip_vision: clip_vision
  loras: loras
  controlnet: controlnet
  upscale_models: upscale_models
  latent_upscale_models: latent_upscale_models
  embeddings: embeddings
YAML

cd "$COMFY_DIR"

if [ "$UPDATE_ON_START" = "true" ]; then
  log "UPDATE_ON_START=true: updating ComfyUI and LTX/control nodes"
  git pull --ff-only || true
  for node in ComfyUI-LTXVideo ComfyUI-VideoHelperSuite comfyui_controlnet_aux; do
    if [ -d "custom_nodes/$node/.git" ]; then git -C "custom_nodes/$node" pull --ff-only || true; fi
  done
fi

if [ "$INSTALL_MISSING_DEPS_ON_START" = "true" ]; then
  log "INSTALL_MISSING_DEPS_ON_START=true: installing runtime requirements"
  uv pip install -r requirements.txt 2>&1 | tee -a "$COMFY_LOG_PATH"
  for node in ComfyUI-LTXVideo ComfyUI-VideoHelperSuite comfyui_controlnet_aux; do
    if [ -f "custom_nodes/$node/requirements.txt" ]; then uv pip install -r "custom_nodes/$node/requirements.txt" 2>&1 | tee -a "$COMFY_LOG_PATH"; fi
  done
fi

log "Manual model download command:"
log "  MODELS_CONFIG_URL=$WORKSPACE_DIR/models_config.json python /notebooks/download_models.py"

if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi | tee -a "$COMFY_LOG_PATH" || true; else log "WARNING: nvidia-smi not available"; fi

python - <<'PY' || true
try:
    import torch
    torch.cuda.empty_cache()
    print(f"CUDA available: {torch.cuda.is_available()}")
except Exception as exc:
    print(f"CUDA check skipped: {exc}")
PY

COMFY_ARGS=(--listen 0.0.0.0 --port 8188 --extra-model-paths-config "$EXTRA_MODEL_PATHS")

if [ "$USE_SAGE_ATTENTION" = "true" ]; then
  if python -c "import sageattention" >/dev/null 2>&1; then
    log "SageAttention module found. Enabling --use-sage-attention."
    COMFY_ARGS+=(--use-sage-attention)
  else
    log "USE_SAGE_ATTENTION=true but sageattention is not installed/importable. Starting without it."
  fi
fi

log "Starting ComfyUI on port 8188"
python main.py "${COMFY_ARGS[@]}" 2>&1 | tee -a "$COMFY_LOG_PATH"
