#!/bin/sh
# Downloads the prebuilt llama.cpp xcframework (LFM3 support landed in b11935+).
set -eu
TAG="${LLAMA_TAG:-b11946}"
cd "$(dirname "$0")/.."
rm -rf Vendor && mkdir -p Vendor && cd Vendor
curl -fL -o llama.zip "https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"
unzip -q llama.zip && rm llama.zip
echo "llama.xcframework (${TAG}) ready in Vendor/build-apple"
