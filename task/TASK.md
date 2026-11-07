# Task: make llama2.c inference faster on CPU

## Goal

Make `run.c` generate text as fast as possible on CPU, **without changing its
output**. The model is `stories15M` (Llama 2 architecture: 6 layers, dim 288,
6 heads, vocab 32000, seq_len 256, float32 weights).

The score (`task/score.sh`) is the **speedup over the baseline**:
`baseline_time / candidate_time`, where both generate 256 tokens greedily
(temperature 0) for the same 4 random story prompts. Higher is better; the
baseline scores about 1.0. The prompts are new on every evaluation, and every
output must match the baseline **byte for byte**, or the candidate fails.

## How the candidate is built and run

- Built with `make run` in the candidate's directory. The binary must be `./run`.
- Run as `OMP_NUM_THREADS=4 ./run <model> -z <tokenizer> -t 0 -n 256 -i "<prompt>"`,
  on a fixed set of 4 CPU cores. Only stdout is compared; stderr is ignored.
- The model and tokenizer come from outside the repo; the binary reads them
  through the normal command-line arguments.

## What may be changed

- `run.c` and the `Makefile`: compiler flags (`-O3`, `-Ofast`, `-march=native`,
  `-fopenmp`, ...), OpenMP parallelism, SIMD (intrinsics or vectorisable loops),
  loop tiling and blocking, memory layout, fusing kernels, avoiding redundant
  work, faster softmax/exp, better use of the KV cache, and so on.
- You may add new source files if `make run` builds them into `./run`.

## What must not be changed

- **The output.** Greedy decoding must produce exactly the same text as the
  baseline. Optimisations that change floating-point results enough to flip a
  token (aggressive approximations, lower precision weights) will fail the
  check. Small reorderings usually do not flip tokens, but test.
- The command-line interface (`-t`, `-n`, `-i`, `-z`, and the positional model path).
- No caching of results across runs, no precomputed outputs, no reading of
  files other than the model and tokenizer, and no work outside the process.
  Each run must actually compute the forward pass for every token.
- `tokenizer.bin` and `tokenizer.model` (protected).
- More than 4 threads will not help: the benchmark is pinned to 4 cores.

## Hints

- The baseline `Makefile` target `run` uses `-O3` with no `-march`, so it gets
  no AVX/FMA and no OpenMP. The `runomp` target shows a faster set of flags.
- Almost all time is in `matmul` (the QKV, output, FFN and classifier
  projections). The final classifier (32000 x 288) is the largest single matmul.
- The model is small (about 60 MB): it is partly cache-resident, so memory
  layout and blocking matter.
- OpenMP has overhead for tiny loops; parallelising the attention heads or only
  the large matmuls may beat parallelising everything.
- Measure: `scripts/evaluate.sh` prints a per-pass log to `.work/eval/*.log`.

## Known dead ends

(None yet: add them via the notes board.)

## Constraints

- C only (C99/C11 with GCC extensions and intrinsics is fine), GCC as the compiler.
- Keep it portable to x86-64 with AVX2; the benchmark machine has AVX2 and FMA.
