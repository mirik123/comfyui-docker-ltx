FROM nvidia/cuda:12.8.0-base-ubuntu24.04

ARG PYTHON_VERSION="3.12"

# Optional. Safer default is false because SageAttention wheels can be Torch/CUDA/Python-specific.
# Build with:
#   --build-arg INSTALL_SAGE_ATTENTION=true
# Optional wheel override:
#   --build-arg SAGEATTENTION_WHEEL_URL="https://..."
ARG INSTALL_SAGE_ATTENTION="false"
ARG SAGEATTENTION_WHEEL_URL=""

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:/root/.local/bin:/root/.cargo/bin:${PATH}" \
    WORKSPACE_DIR=/workspace \
    COMFY_DIR=/workspace/ComfyUI \
    IMAGE_COMFY_DIR=/opt/ComfyUI \
    HF_HOME=/workspace/cache/huggingface \
    HUGGINGFACE_HUB_CACHE=/workspace/cache/huggingface/hub \
    PIP_CACHE_DIR=/workspace/cache/pip \
    UV_CACHE_DIR=/workspace/cache/uv \
    TORCH_HOME=/workspace/cache/torch \
    TRITON_CACHE_DIR=/workspace/cache/triton \
    TORCH_EXTENSIONS_DIR=/workspace/cache/torch_extensions \
    TORCHINDUCTOR_CACHE_DIR=/workspace/cache/torchinductor

# Minimal runtime for ComfyUI + LTX-2.3 + LTX IC-LoRA control workflows.
# Removed: Wan, Qwen, generic backend, log viewer, Jupyter, ComfyUI Manager, model downloader app.
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    git \
    build-essential \
    ninja-build \
    libgl1 \
    libglib2.0-0 \
    ffmpeg \
    aria2 \
    rsync \
    curl \
    wget \
    ca-certificates \
    jq \
    nano \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update --yes \
    && apt-get install --yes --no-install-recommends \
    python3-pip \
    "python${PYTHON_VERSION}" \
    "python${PYTHON_VERSION}-venv" \
    "python${PYTHON_VERSION}-dev" \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && "python${PYTHON_VERSION}" -m venv /opt/venv \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# CUDA PyTorch + base packages are baked into the image, not installed at Pod start.
RUN uv pip install --python /opt/venv/bin/python --no-cache \
    torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    && uv pip install --python /opt/venv/bin/python --no-cache \
    pip \
    "numpy<2" \
    safetensors \
    huggingface_hub \
    transformers \
    accelerate \
    sentencepiece \
    protobuf \
    imageio \
    imageio-ffmpeg \
    opencv-python-headless \
    einops \
    av \
    triton \
    && if [ "$INSTALL_SAGE_ATTENTION" = "true" ]; then \
         if [ -n "$SAGEATTENTION_WHEEL_URL" ]; then \
           uv pip install --python /opt/venv/bin/python --no-cache "$SAGEATTENTION_WHEEL_URL"; \
         else \
           uv pip install --python /opt/venv/bin/python --no-cache sageattention; \
         fi; \
       fi \
    && uv cache clean

# Bake ComfyUI and LTX-relevant custom nodes into the image.
#
# Why keep ComfyUI-LTXVideo?
# - ComfyUI has native/basic LTX support, but Lightricks' node pack includes the
#   official advanced LTX-2.3 workflows, IC-LoRA, multimodal guider, low VRAM loaders,
#   conditioning save/load, etc.
#
# Why keep comfyui_controlnet_aux?
# - LTX-2.3 control is usually IC-LoRA Union Control / motion control, not old SD ControlNet.
# - The workflow still needs preprocessors for depth / canny / pose if you want to create control maps inside ComfyUI.
RUN set -eux; \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI; \
    cd /opt/ComfyUI; \
    uv pip install --python /opt/venv/bin/python --no-cache -r requirements.txt; \
    mkdir -p custom_nodes; \
    cd custom_nodes; \
    git clone --depth=1 https://github.com/Lightricks/ComfyUI-LTXVideo.git; \
    git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git; \
    git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git; \
    find /opt/ComfyUI/custom_nodes -name requirements.txt -print0 \
      | xargs -0 -r -I{} uv pip install --python /opt/venv/bin/python --no-cache -r "{}"; \
    mkdir -p /opt/ComfyUI/models/{checkpoints,vae,diffusion_models,unet,text_encoders,clip,clip_vision,loras,controlnet,upscale_models,latent_upscale_models,embeddings}; \
    mkdir -p /opt/ComfyUI/input /opt/ComfyUI/output /opt/ComfyUI/user; \
    uv cache clean

WORKDIR /notebooks
COPY model_config_ltx23_iclora.json /notebooks/models_config.json
COPY start.sh /notebooks/start.sh
RUN chmod +x /notebooks/start.sh && mkdir -p /workspace /notebooks


EXPOSE 8188
CMD ["/notebooks/start.sh"]
