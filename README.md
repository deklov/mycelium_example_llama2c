# Mycelium example: faster llama2.c

A ready-to-run [Mycelium](https://github.com/deklov/mycelium) campaign. Many AI
coding agents work together to make
[karpathy/llama2.c](https://github.com/karpathy/llama2.c) generate text faster
on CPU, coordinating only through Git.

- **Target:** `run.c` from llama2.c (MIT), pinned at `350e04f`.
- **Model:** `stories15M`, a 15M-parameter Llama 2 architecture model trained on
  TinyStories. It is downloaded and checksummed on first use (60 MB).
- **Score:** speedup over the baseline, measured on 4 CPU cores. The baseline
  scores about 1.0. Every evaluation uses fresh random prompts, and the output
  must match the baseline byte for byte. See `task/TASK.md` and `task/score.sh`.

The task files are already written. What's left is the part that depends on
you and your machines: forking llama2.c, measuring the noise on your hardware,
scoring the baseline and marking the run ready.

## Run it

1. Fork this repository and clone your fork (with `--recurse-submodules`).
2. Start Claude Code (or Codex) in the checkout. It resumes onboarding:
   1. It forks llama2.c to hold your experiments.
   2. It points `target/` at your fork.
   3. It measures noise, scores the baseline, and tags the run ready.
3. On each machine, run `scripts/launch.sh`, or for unattended use
   `scripts/launch.sh --headless --max-experiments 20` inside a container or VM.

Requirements: Linux or macOS on x86-64 with AVX2, GCC, make, Git 2.30 or later,
and curl.

Optional environment variables:
- `MYCELIUM_BENCH_CPUS=0,2,4,6` pins the benchmark to 4 cores.
- `MYCELIUM_SCORE_LOCK=/path/to/lockfile` stops two agents on one machine from
  benchmarking at the same time.

Ask any agent "What's the status?", or run `scripts/tree.sh status`.

## How this repo relates to the template

This repo is the [Mycelium template](https://github.com/deklov/mycelium) plus
one commit that adds:
- `target/`;
- `task/TASK.md`, `task/score.sh` and `task/config.yaml`;
- `task/baseline/`: a pristine copy of the baseline `run.c` and tokenizer that
  `score.sh` uses as the reference.

To pull in template updates:

```
git remote add template https://github.com/deklov/mycelium
git pull template main
```

See the template's README for how Mycelium works.

## License

MIT. llama2.c is MIT, Copyright (c) 2023 Andrej Karpathy; its license is
included in `task/baseline/LICENSE`.
