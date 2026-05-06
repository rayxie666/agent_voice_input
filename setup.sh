#!/usr/bin/env bash
# Set up whisper.cpp (vendored, built with Metal) and download ggml-medium model.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$ROOT/vendor"
WHISPER="$VENDOR/whisper.cpp"
MODELS="$ROOT/Models"
WHISPER_TAG="${WHISPER_TAG:-v1.7.4}"
MODEL_NAME="${MODEL_NAME:-ggml-medium.bin}"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}"

mkdir -p "$VENDOR" "$MODELS"

if [ ! -d "$WHISPER/.git" ]; then
    echo "==> Cloning whisper.cpp ($WHISPER_TAG)"
    git clone --depth 1 --branch "$WHISPER_TAG" \
        https://github.com/ggerganov/whisper.cpp.git "$WHISPER"
else
    echo "==> whisper.cpp already cloned at $WHISPER"
fi

echo "==> Building whisper.cpp with Metal (Apple Silicon)"
cmake -S "$WHISPER" -B "$WHISPER/build" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_BLAS=ON \
    -DGGML_ACCELERATE=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
cmake --build "$WHISPER/build" -j --config Release

echo "==> Copying headers into Sources/CWhisper/include (so SPM can find them)"
cp "$WHISPER"/include/*.h           "$ROOT/Sources/CWhisper/include/"
cp "$WHISPER"/ggml/include/*.h      "$ROOT/Sources/CWhisper/include/"

if [ ! -f "$MODELS/$MODEL_NAME" ]; then
    echo "==> Downloading $MODEL_NAME (~1.5GB)"
    curl -L --fail --progress-bar -o "$MODELS/$MODEL_NAME" "$MODEL_URL"
else
    echo "==> Model already present: $MODELS/$MODEL_NAME"
fi

# Symlink into Application Support so the launched .app finds the model
# without depending on whatever cwd it was started from.
APP_SUPPORT="$HOME/Library/Application Support/VoiceInput/Models"
mkdir -p "$APP_SUPPORT"
if [ ! -e "$APP_SUPPORT/$MODEL_NAME" ]; then
    ln -s "$MODELS/$MODEL_NAME" "$APP_SUPPORT/$MODEL_NAME"
    echo "==> Linked model into $APP_SUPPORT"
fi

echo
echo "Setup complete."
echo "Next: make build  (or open Package.swift in Xcode)"
