#!/bin/bash
# Runs the retrieval evaluation against the labeled corpus.
#
# Compiles the app's real Ranker, LexicalIndex, and Vector sources — not a copy —
# so the numbers describe what actually ships.
set -euo pipefail
cd "$(dirname "$0")"
SRC=../Recall
BIN=$(mktemp -d)/evaluate

xcrun swiftc -O -swift-version 6 -target arm64-apple-macos26.0 \
  "$SRC/Models/Mood.swift" \
  "$SRC/Retrieval/Vector.swift" \
  "$SRC/Retrieval/LexicalIndex.swift" \
  "$SRC/Retrieval/Ranker.swift" \
  main.swift -o "$BIN"

"$BIN" .
