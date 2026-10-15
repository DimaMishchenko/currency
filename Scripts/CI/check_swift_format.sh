#!/usr/bin/env bash
set -euo pipefail

git ls-files -z -- \
  ':(glob)Apps/**/*.swift' ':(glob)AppExtensions/**/*.swift' \
  ':(glob)Domain/**/*.swift' ':(glob)Features/**/*.swift' ':(glob)Foundation/**/*.swift' \
  | xargs -0 swift format lint --strict
