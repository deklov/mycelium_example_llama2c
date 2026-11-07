#!/usr/bin/env bash
# Score for the llama2.c example: speedup of CPU inference over the baseline,
# with output that must match the baseline exactly. Higher is better.
#
#   score.sh <dir>     <dir> is a clean export of the candidate llama2.c
#
# 1. Builds the candidate with `make run` (agents may change the Makefile and
#    run.c; the binary must be ./run).
# 2. Draws N_PROMPTS random story prompts (fresh every evaluation, so outputs
#    cannot be hard-coded).
# 3. Generates reference outputs with the pristine baseline (task/baseline/run.c,
#    built with -O3) and times it.
# 4. Runs the candidate on the same prompts PASSES times. Every output must
#    match the reference byte for byte (greedy decoding, temperature 0), or the
#    candidate fails.
# 5. Prints baseline_time / median(candidate_time).
#
# Model weights and tokenizer always come from task/ and the cache, never from
# the candidate. Environment:
#   MYCELIUM_BENCH_CPUS   optional CPU list for taskset, e.g. 0,2,4,6
#   MYCELIUM_CACHE_DIR    where stories15M.bin is cached (default ~/.cache/mycelium)
#   OMP threads are fixed at BENCH_THREADS.
set -euo pipefail

src="$(cd "$1" && pwd)"
task="${MYCELIUM_TASK_DIR:-$(cd "$(dirname "$0")" && pwd)}"
N_PROMPTS=4
STEPS=256
PASSES=3
BENCH_THREADS=4
MODEL_URL="https://huggingface.co/karpathy/tinyllamas/resolve/main/stories15M.bin"
MODEL_SHA256="cd590644d963867a2b6e5a1107f51fad663c41d79c149fbecbbb1f95fa81f49a"

log() { echo "[score] $*" >&2; }

# ---- model (cached, checksummed)
cache="${MYCELIUM_CACHE_DIR:-$HOME/.cache/mycelium}"
model="$cache/stories15M.bin"
mkdir -p "$cache"
if [ ! -f "$model" ]; then
  log "downloading stories15M.bin"
  curl -sSfL -o "$model.part" "$MODEL_URL" && mv "$model.part" "$model"
fi
sum="$(sha256sum "$model" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$model" | cut -d' ' -f1)"
[ "$sum" = "$MODEL_SHA256" ] || { log "model checksum mismatch"; exit 2; }
tokenizer="$task/baseline/tokenizer.bin"

pin=()
if [ -n "${MYCELIUM_BENCH_CPUS:-}" ]; then pin=(taskset -c "$MYCELIUM_BENCH_CPUS"); fi

clock() { if [ -n "${EPOCHREALTIME:-}" ]; then echo "${EPOCHREALTIME/,/.}"; else date +%s.%N; fi; }

# ---- baseline binary (cached by source hash)
base_hash="$(cat "$task/baseline/run.c" | sha256sum | cut -c1-16)"
ref_bin="$cache/run_baseline_$base_hash"
if [ ! -x "$ref_bin" ]; then
  log "building the baseline"
  gcc -O3 -o "$ref_bin.tmp" "$task/baseline/run.c" -lm && mv "$ref_bin.tmp" "$ref_bin"
fi

# ---- candidate build
log "building the candidate: make run"
( cd "$src" && rm -f run && make run >&2 ) || { log "build failed"; exit 1; }
[ -x "$src/run" ] || { log "make run did not produce ./run"; exit 1; }

# ---- random prompts
RANDOM=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
openers=("Once upon a time," "One day," "Yesterday," "Long ago," "Every morning," "On a sunny day," "In a small town," "Last summer,")
names=(Lily Tom Sam Mia Ben Anna Max Sue Tim Lucy Jack Zoe)
actions=("found a" "wanted to see the" "was scared of the" "made a" "lost her" "played with the" "saw a big" "shared the")
things=(ball cat tree boat cake dog kite flower box bird car star)
prompts=()
for _ in $(seq 1 "$N_PROMPTS"); do
  prompts+=("${openers[RANDOM % ${#openers[@]}]} ${names[RANDOM % ${#names[@]}]} ${actions[RANDOM % ${#actions[@]}]} ${things[RANDOM % ${#things[@]}]}")
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ---- reference outputs and baseline time
t0="$(clock)"
for i in "${!prompts[@]}"; do
  "${pin[@]}" "$ref_bin" "$model" -z "$tokenizer" -t 0 -n "$STEPS" -i "${prompts[$i]}" > "$work/ref_$i" 2>/dev/null
done
t1="$(clock)"
base_time="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.6f", b - a }')"
log "baseline: ${base_time}s for $N_PROMPTS prompts"

# ---- candidate passes
times=()
for pass in $(seq 1 "$PASSES"); do
  t0="$(clock)"
  for i in "${!prompts[@]}"; do
    OMP_NUM_THREADS=$BENCH_THREADS "${pin[@]}" "$src/run" "$model" -z "$tokenizer" -t 0 -n "$STEPS" -i "${prompts[$i]}" \
      > "$work/out_$i" 2>/dev/null || { log "candidate crashed on prompt: ${prompts[$i]}"; exit 1; }
  done
  t1="$(clock)"
  for i in "${!prompts[@]}"; do
    if ! cmp -s "$work/ref_$i" "$work/out_$i"; then
      log "output differs from the baseline for prompt: ${prompts[$i]}"
      diff <(tr ' ' '\n' < "$work/ref_$i") <(tr ' ' '\n' < "$work/out_$i") | head -n 10 >&2 || true
      exit 1
    fi
  done
  times+=("$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.6f", b - a }')")
  log "candidate pass $pass: ${times[$((pass - 1))]}s"
done

median="$(printf '%s\n' "${times[@]}" | sort -g | awk '{ a[NR] = $1 } END { print (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2 }')"
awk -v b="$base_time" -v c="$median" 'BEGIN { printf "%.4f\n", b / c }'
