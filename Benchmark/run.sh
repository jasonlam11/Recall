#!/bin/bash
# Latency benchmarks against the on-device model.
#
# Cold-start is measured in fresh processes, since the model stays warm for the
# life of a process — measuring it twice in one run would only ever show "warm".
set -euo pipefail
cd "$(dirname "$0")"
BIN=$(mktemp -d)/benchmark
xcrun swiftc -O -swift-version 6 -target arm64-apple-macos26.4 \
  ../Recall/Models/Mood.swift ../Recall/Models/EntryInsight.swift \
  main.swift -o "$BIN"

echo "== token budget =="
"$BIN" tokens
echo
echo "== cold start: does prewarm() help? =="
printf "         first-snapshot  total\n"
for i in 1 2 3; do "$BIN" cold; done
for i in 1 2 3; do "$BIN" warm; done
echo
echo "== steady state =="
"$BIN" enrich
"$BIN" embed
