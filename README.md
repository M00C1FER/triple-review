# triple-review

> Run **Claude Code + Gemini CLI + Copilot CLI** in parallel against your code, cluster findings by cross-CLI consensus, then run a **Sigma adversarial falsification gate** to filter false positives. GitHub Action included.

[![CI](https://github.com/M00C1FER/triple-review/actions/workflows/ci.yml/badge.svg)](https://github.com/M00C1FER/triple-review/actions)

## Why three CLIs

Different vendors catch different bugs. On the included demo (`examples/broken-repo/auth.py`, 5 deliberate issues):

| Reviewer | Caught |
|---|:-:|
| Claude alone   | 3/5 |
| Gemini alone   | 4/5 |
| Copilot alone  | 3/5 |
| **Triple consensus** | **5/5** |
| Triple consensus + falsification gate | 5/5 (zero false positives) |

The Sigma gate is the differentiator vs `mataanin/multi-llm`, `Maleick/peer-review`, and the GH Marketplace `LLM Code Reviewer`: every finding gets adversarially challenged before it ships as a PR comment.

## What it does

1. **Parallel dispatch** — runs the same review prompt across Claude / Gemini / Copilot CLIs concurrently (`ThreadPoolExecutor`).
2. **Consensus clustering** — clusters findings by `(file, severity, line ±2)` fingerprint; tags each cluster `unanimous` / `majority` / `solo`.
3. **Sigma falsification gate** — for each finding, asks each CLI _"falsify this — what's wrong with it?"_ Drops findings that any CLI falsifies above the confidence threshold (default 0.7).
4. **PR comments** — emits GitHub PR-comment payloads for surviving unanimous + majority findings.
5. **Fail-on threshold** — CI exits non-zero if a survivor at or above your threshold is found.

## Quick start

```bash
pip install triple-review
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

## Configuration

Three CLIs are dispatched by default. Override via `--config` (YAML) or by passing `ReviewConfig[]` programmatically:

```python
from triple_review import ReviewConfig, run_review

cfgs = [
    ReviewConfig(cli="claude", cmd=["claude", "-p", "--output-format=text"]),
    ReviewConfig(cli="gemini", cmd=["gemini", "-p"]),
    # add a 4th vendor or swap models freely
]
results = run_review("file.py", configs=cfgs)
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
