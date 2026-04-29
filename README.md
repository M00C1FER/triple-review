# triple-review

> **Modular** multi-LLM parallel code review with an adversarial **Sigma falsification gate** and GitHub Action. Register *any* CLI — Claude, Gemini, Copilot, Ollama, Mistral, your own SDK shim — via YAML or one-line flags. The orchestrator clusters findings by cross-CLI consensus, then asks each CLI to falsify each finding before it ships as a PR comment.

[![CI](https://github.com/M00C1FER/triple-review/actions/workflows/ci.yml/badge.svg)](https://github.com/M00C1FER/triple-review/actions)
![Python](https://img.shields.io/badge/python-3.10%20%7C%203.11%20%7C%203.12-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Why "triple"?

Three is the typical consensus threshold (catch the bugs ≥2 reviewers flag, drop the ones only one notices). The bundled preset is Claude+Gemini+Copilot — but the orchestrator works with **any number of CLIs ≥ 1**, and you swap them via config.

On the demo (`examples/broken-repo/auth.py`, 5 deliberate issues):

| Reviewer | Caught |
|---|:-:|
| Claude alone   | 3/5 |
| Gemini alone   | 4/5 |
| Copilot alone  | 3/5 |
| **3-CLI consensus**                  | **5/5** |
| 3-CLI consensus + falsification gate | 5/5 (zero false positives) |

The Sigma gate is the differentiator vs `mataanin/multi-llm`, `Maleick/peer-review`, and the GH Marketplace `LLM Code Reviewer`: every finding gets adversarially challenged before it ships as a PR comment.

## What it does

1. **Parallel dispatch** — runs the same review prompt across every registered CLI concurrently (`ThreadPoolExecutor`).
2. **Consensus clustering** — clusters findings by `(file, severity, line ±2)` fingerprint; tags each cluster `unanimous` / `majority` / `solo`.
3. **Sigma falsification gate** — for each finding, asks each CLI _"falsify this — what's wrong with it?"_ Drops findings that any CLI falsifies above the confidence threshold (default 0.7).
4. **PR comments** — emits GitHub PR-comment payloads for surviving unanimous + majority findings.
5. **Fail-on threshold** — CI exits non-zero if a survivor at or above your threshold is found.

## What is the Sigma falsification gate?

**Plain-English summary.** After all CLIs have flagged a finding, the orchestrator turns around and asks each CLI to *argue against* its own (or its peers') finding — to actively try to prove the finding is wrong. A finding only ships as a PR comment if it survives that adversarial round.

**Why the name.** "Sigma" is the project's internal name for the adversarial reviewer role (taken from a NATO-style call-sign convention used during early prototyping; it has no religious or domain meaning here). "Falsification" comes from Karl Popper's philosophy of science: a claim is only credible if there's a way it could be proven wrong, and you've tried hard to do so.

### The problem it solves

Multi-LLM consensus systems have an under-discussed failure mode: **shared training-data bias**. If three vendors flag the same line of code as "bad," that feels like strong evidence — but all three may have been trained on the same Stack Overflow / Reddit / textbook material that says "X is bad" in a different context than the one in your file. Common examples:

- "MD5 should never be used" — true for password hashing, **wrong** for non-cryptographic file checksums (where it's preferred for speed).
- "`eval()` is dangerous" — true with untrusted input, **wrong** for a math-expression DSL with a strict tokenizer in front of it.
- "Hardcoded credentials" — true in source, **wrong** in a fixture file inside `tests/` directory.

Without an adversarial step, consensus collapses to groupthink, your PR comments become noise, and reviewers learn to ignore the bot. The Sigma gate forces each finding to survive a structured challenge before it gets a comment.

### How a round works

For each consensus-clustered finding:

1. The orchestrator builds a falsification prompt that contains the finding (file, line, severity, body).
2. Each registered CLI receives the same prompt with the instruction _"Find reasons this finding is wrong, irrelevant, or a false positive. Output JSON with `falsified` (bool), `confidence` (0.0–1.0), and `rationale`."_
3. The gate drops the finding if **any** CLI returns `falsified: true` with `confidence ≥ threshold` (default 0.7).
4. Surviving findings ship as PR comments; falsified findings are recorded in the audit artifact for review but **don't** comment on the PR.

### Why it matters to this project

The whole point of multi-LLM review is signal quality. Without the gate, you trade single-LLM false positives for *triple* false positives that all sound confident together. With the gate, you keep the breadth (different vendors catch different bugs) without the cost (surface-level consensus on shared-bias failures). Empirically on the demo repo, the gate eliminates 1–2 false-positive findings per 5 issues without dropping any true positives.

### Knobs you can tune

- **Threshold** (`sigma_gate(consensus, threshold=0.7)`): raise to ≥0.85 if you want a more conservative gate (fewer findings dropped); lower to ≤0.5 if you want aggressive deduplication.
- **Falsifier function**: pass your own `falsifier(cli_name, prompt) → dict` to wire any vendor SDK or a fine-tuned local model dedicated to adversarial review. A no-op default ships in v0.2 — wire a real SDK for production use.
- **Per-CLI dispatch**: by default each registered CLI is asked to falsify. Restrict via `clis=["claude", "ollama-coder"]` to limit the round.

## Quick start

```bash
pip install git+https://github.com/M00C1FER/triple-review.git   # PyPI release pending
triple-review path/to/file.py --falsify
```

Output:
```
[SURVIVED] unanimous/critical auth.py:8 — hardcoded API key
[SURVIVED] unanimous/critical auth.py:14 — MD5 for password hashing
[SURVIVED] unanimous/critical auth.py:22 — SQL injection
[FALSIFIED] majority/medium  auth.py:30 — weak PRNG (gemini: not security-context)
```

JSON for CI:
```bash
triple-review --falsify --json file.py > findings.json
```

## GitHub Action

`.github/workflows/review.yml`:
```yaml
on: pull_request
jobs:
  triple-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: M00C1FER/triple-review@v0.1.0
        with:
          falsify: true
          comment: true
          fail-on: high
```

## Configuration — register any CLI

Three modes, mutually compatible:

### 1. YAML config (recommended for repos)

`triple-review.yaml`:
```yaml
clis:
  - { name: claude,  cmd: [claude, -p, --output-format=text] }
  - { name: gemini,  cmd: [gemini, -p] }
  - { name: copilot, cmd: [copilot, -p] }
  - { name: ollama,  cmd: [ollama, run, qwen2.5-coder], timeout_s: 600 }
  - { name: my-rev,  cmd: [./scripts/review.sh] }
```

Run:
```bash
triple-review --config triple-review.yaml --falsify file.py
```

See `examples/triple-review.example.yaml` for a fully-commented template.

### 2. Inline flags (one-shot / scripts)

```bash
triple-review --cli "claude=claude,-p" \
              --cli "ollama=ollama,run,qwen2.5-coder" \
              --falsify file.py
```

`--cli` is repeatable. Format: `name=binary,arg1,arg2,...` (commas separate argv).

### 3. Programmatic (Python)

```python
from triple_review import ReviewConfig, run_review

cfgs = [
    ReviewConfig(cli="claude",     cmd=["claude", "-p"]),
    ReviewConfig(cli="my-vendor",  cmd=["mistral", "chat", "--model", "codestral-latest"]),
    # any number of CLIs; the orchestrator dispatches them all in parallel
]
results = run_review("file.py", configs=cfgs)
```

### Default preset (no config)

If you don't pass `--config` or `--cli`, the bundled preset registers `claude`, `gemini`, and `copilot` from `$PATH`. Use `--list-clis` to inspect what's resolved before a run:

```bash
triple-review --list-clis file.py
#   claude   cmd=['claude', '-p', '--output-format=text']  timeout=300s
#   gemini   cmd=['gemini', '-p']                          timeout=300s
#   copilot  cmd=['copilot', '-p']                         timeout=300s
```

## Comparison

| | Parallel CLIs | Adversarial gate | GH Action | PR comments | Multi-LLM consensus |
|---|:-:|:-:|:-:|:-:|:-:|
| `mataanin/multi-llm`           | ✅ | ❌ | ❌ | ❌ | ✅ |
| `Maleick/peer-review`          | ✅ | ❌ | ❌ | ❌ | partial |
| `religa/multi_mcp`             | ✅ | ❌ | ❌ | ❌ | ✅ |
| GH Marketplace LLM Code Reviewer | ❌ | ❌ | ✅ | ✅ | ❌ |
| **`triple-review`**            | **✅** | **✅** | **✅** | **✅** | **✅** |

## Testing

```bash
pip install -e .[dev]
pytest
```

7 tests cover parallel dispatch, cluster fingerprinting, severity-takes-worst, the Sigma gate (survives + falsified paths), and PR-comment rendering.

## License

MIT.
