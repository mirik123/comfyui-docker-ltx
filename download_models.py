#!/usr/bin/env python3
from __future__ import annotations

import json, os, shutil, subprocess, sys, tempfile, urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse, unquote

WORKSPACE_DIR = Path(os.environ.get("WORKSPACE_DIR", "/workspace"))
DEFAULT_CONFIG = os.environ.get("MODELS_CONFIG_URL") or str(WORKSPACE_DIR / "models_config.json")
MODEL_BASE_DIR = Path(os.environ.get("MODEL_BASE_DIR", str(WORKSPACE_DIR / "models")))
LOG_DIR = WORKSPACE_DIR / "logs"
LOG_PATH = Path(os.environ.get("MODEL_DOWNLOAD_LOG", str(LOG_DIR / "model_download.log")))
FORCE_DOWNLOAD = os.environ.get("FORCE_MODEL_DOWNLOAD", "false").lower() == "true"
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
MAX_CONNECTIONS = os.environ.get("ARIA2_CONNECTIONS", "8")
HF_TOKEN = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")

VALID_TOP_LEVEL_CATEGORIES = {"checkpoints","vae","unet","diffusion_models","text_encoders","loras","controlnet","clip","clip_vision","upscale_models","latent_upscale_models","embeddings","ipadapter","style_models","audio_encoders","detection"}

def log(message: str) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    print(message, flush=True)
    with LOG_PATH.open("a", encoding="utf-8") as f: f.write(message + "\n")

def load_config(src: str) -> dict[str, Any]:
    if src.startswith(("http://", "https://")):
        log(f"Loading model config URL: {src}")
        req = urllib.request.Request(src)
        if HF_TOKEN: req.add_header("Authorization", f"Bearer {HF_TOKEN}")
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    path = Path(src)
    log(f"Loading local model config: {path}")
    if not path.exists(): raise FileNotFoundError(f"Model config not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))

def filename_from_url(url: str) -> str:
    name = unquote(Path(urlparse(url).path).name)
    if not name: raise ValueError(f"Cannot infer filename from URL: {url}")
    return name

def validate_category(category: str) -> None:
    if category.startswith("/") or ".." in Path(category).parts: raise ValueError(f"Unsafe category path: {category}")
    top_level = category.split("/", 1)[0]
    if top_level not in VALID_TOP_LEVEL_CATEGORIES: log(f"WARNING: unknown category '{category}', using it anyway.")

def download_with_aria2(url: str, dest_dir: Path, filename: str) -> None:
    cmd = ["aria2c","--continue=true","--file-allocation=none","--summary-interval=30","--console-log-level=warn","--max-tries=8","--retry-wait=10","--connect-timeout=30","--timeout=600","--max-connection-per-server",MAX_CONNECTIONS,"-x",MAX_CONNECTIONS,"-s",MAX_CONNECTIONS,"-k","1M"]
    if HF_TOKEN: cmd += ["--header", f"Authorization: Bearer {HF_TOKEN}"]
    cmd += [url, "-d", str(dest_dir), "-o", filename]
    subprocess.run(cmd, check=True)

def download_with_urllib(url: str, dest_path: Path) -> None:
    req = urllib.request.Request(url)
    if HF_TOKEN: req.add_header("Authorization", f"Bearer {HF_TOKEN}")
    with urllib.request.urlopen(req, timeout=60) as response:
        with tempfile.NamedTemporaryFile(delete=False, dir=str(dest_path.parent), suffix=".tmp") as tmp:
            shutil.copyfileobj(response, tmp)
            tmp_path = Path(tmp.name)
    tmp_path.replace(dest_path)

def download_file(url: str, category: str) -> bool:
    validate_category(category)
    dest_dir = MODEL_BASE_DIR / category
    dest_dir.mkdir(parents=True, exist_ok=True)
    filename = filename_from_url(url)
    dest_path = dest_dir / filename
    if dest_path.exists() and dest_path.stat().st_size > 0 and not FORCE_DOWNLOAD:
        log(f"SKIP existing: {dest_path}")
        return False
    log(f"DOWNLOAD: {url}\n       -> {dest_path}")
    if DRY_RUN: return False
    if FORCE_DOWNLOAD:
        dest_path.unlink(missing_ok=True)
        dest_path.with_suffix(dest_path.suffix + ".aria2").unlink(missing_ok=True)
    if shutil.which("aria2c"): download_with_aria2(url, dest_dir, filename)
    else: download_with_urllib(url, dest_path)
    if not dest_path.exists() or dest_path.stat().st_size == 0: raise RuntimeError(f"Downloaded file missing/empty: {dest_path}")
    log(f"OK: {dest_path} ({dest_path.stat().st_size / (1024 ** 3):.2f} GiB)")
    return True

def main() -> int:
    MODEL_BASE_DIR.mkdir(parents=True, exist_ok=True)
    try: config = load_config(DEFAULT_CONFIG)
    except Exception as exc:
        log(f"ERROR: failed to load config: {exc}")
        return 2
    total = downloaded = failed = 0
    for category, urls in config.items():
        if not urls: continue
        if not isinstance(urls, list):
            log(f"WARNING: skipping '{category}', value is not a list")
            continue
        for url in urls:
            total += 1
            try:
                if download_file(str(url), str(category)): downloaded += 1
            except Exception as exc:
                failed += 1
                log(f"ERROR downloading {url}: {exc}")
    log(f"DONE: total={total}, downloaded={downloaded}, failed={failed}, base={MODEL_BASE_DIR}")
    return 1 if failed else 0

if __name__ == "__main__": sys.exit(main())
