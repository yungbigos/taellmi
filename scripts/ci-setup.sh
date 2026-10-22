#!/usr/bin/env bash
# Prepares a fresh GitHub macOS runner like a developer's Mac, before scripts/check.sh or the release build.
# Used by .github/workflows/check.yml and release.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(uname -m)" == "arm64" ]] || { echo "✘ needs an Apple silicon runner"; exit 1; }
sudo xcode-select -s /Applications/Xcode_26.6.app
xcodebuild -version
# MLX compiles Metal shaders; since Xcode 26 the Metal toolchain is a separate download.
xcodebuild -showComponent MetalToolchain | grep -q "Status: installed" || xcodebuild -downloadComponent MetalToolchain
brew install xcodegen
# The word classifier tags German with Apple's NaturalLanguage, whose German data a fresh runner lacks.
swift scripts/ci-language-assets.swift
