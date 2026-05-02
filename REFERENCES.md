# Reference projects

Peer projects studied during the 2026-05-02 audit cycle. All are MIT/Apache/BSD licensed with ≥50 GitHub stars at time of writing.

---

## 1. `mataanin/multi-llm` — parallel dispatch, no gate

**Pattern adopted:** thread-pool dispatch with per-CLI timeout isolation.  
Each CLI runs in its own thread; a timeout on one does not block siblings. `triple-review` mirrors this via `ThreadPoolExecutor` + `subprocess.run(..., timeout=...)`.

---

## 2. `Maleick/peer-review` — partial multi-model consensus

**Pattern adopted:** returning a *cluster* object (not a flat list) so callers can inspect per-model votes.  
`triple-review`'s `ConsensusFinding` carries the full `findings` list and the `clis` list, letting the caller (or the gate) inspect individual model opinions rather than just an aggregate.

---

## 3. `religa/multi_mcp` — MCP-native multi-model dispatch

**Pattern noted:** vendor-neutral adapter interface — each "reviewer" exposes the same `review(path, prompt) → list[Finding]` contract, making it easy to swap models.  
`triple-review` implements this via the `runner: Callable` field on `ReviewConfig`: pass a Python callable for in-process SDK calls, or omit it to use the default shell-out runner. This keeps the orchestrator vendor-neutral.

---

## 4. GH Marketplace `LLM Code Reviewer` — GitHub Action integration

**Pattern adopted:** using a composite Action (not a Docker Action) so the step reuses the already-checked-out repo and avoids a container pull.  
`triple-review`'s `action/action.yml` uses `runs: using: composite` for the same reason: faster CI start, no image maintenance.

---

## 5. `anthropics/anthropic-sdk-python` — robust subprocess/SDK boundary

**Pattern adopted:** fail-safe JSON extraction — try `json.loads` first; if that fails, scan for `[...]` in the output and retry.  
This tolerates models that wrap their JSON output in markdown fences or add a preamble sentence. Implemented in `core._parse_findings`.
