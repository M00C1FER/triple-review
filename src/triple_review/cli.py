"""triple-review CLI: review files locally or in CI.

Modular: register any CLI via --config <yaml> or repeat --cli name=cmd[,arg,...].
The "triple" name reflects the typical 3-CLI consensus pattern (Claude+Gemini+
Copilot is one valid preset) but the orchestrator works with any number of
named CLIs ≥ 1.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import List

from .config import load_config_yaml, parse_inline_cli
from .consensus import build_consensus
from .core import ReviewConfig, default_configs, run_review
from .falsify import render_pr_comments, sigma_gate


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="triple-review",
        description="Multi-CLI parallel code review with adversarial falsification gate",
        epilog="""
CLI registration (mutually compatible — combine as needed):
  --config triple-review.yaml         load CLIs from a YAML config file
  --cli name=cmd[,arg,...]            register a single CLI inline (repeatable)
  (none of the above)                 use the bundled 3-CLI preset
                                      (claude / gemini / copilot)

Examples:
  triple-review file.py
  triple-review --config my-clis.yaml --falsify file.py
  triple-review --cli claude=claude,-p --cli ollama=ollama,run,qwen2.5 file.py
""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("files", nargs="+", help="files to review")
    parser.add_argument("--config", metavar="PATH",
                        help="YAML file registering CLIs (overrides built-in preset)")
    parser.add_argument("--cli", action="append", metavar="NAME=CMD[,ARG,...]",
                        default=[], help="register a CLI inline (repeatable)")
    parser.add_argument("--falsify", action="store_true",
                        help="run Sigma adversarial falsification gate")
    parser.add_argument("--pr-comments", action="store_true",
                        help="emit PR-comment JSON payloads")
    parser.add_argument("--json", action="store_true",
                        help="JSON output instead of human-readable")
    parser.add_argument("--list-clis", action="store_true",
                        help="print resolved CLI registry and exit")
    args = parser.parse_args()

    configs = _resolve_configs(args)
    if args.list_clis:
        for c in configs:
            print(f"  {c.cli:24} cmd={c.cmd}  timeout={c.timeout_s}s")
        return 0

    all_results = []
    for path in args.files:
        all_results.extend(run_review(path, configs=configs))

    consensus = build_consensus(all_results)

    if args.falsify:
        gate = sigma_gate(consensus, clis=[c.cli for c in configs])
        if args.pr_comments:
            print(json.dumps(render_pr_comments(gate), indent=2))
        elif args.json:
            print(json.dumps(gate, indent=2))
        else:
            for entry in gate:
                f = entry["finding"]
                marker = "[SURVIVED]" if entry["survived"] else "[FALSIFIED]"
                print(f"{marker} {f['agreement']}/{f['severity']} {f['file']}:{f['line']} — {f['title']}")
        return 0

    if args.json:
        print(json.dumps([c.to_dict() for c in consensus], indent=2))
    else:
        for c in consensus:
            print(f"[{c.agreement}/{c.severity}] {c.file}:{c.line} — {c.title}")
    return 0


def _resolve_configs(args) -> List[ReviewConfig]:
    """Build the active CLI list from --config + --cli + fallback preset."""
    configs: List[ReviewConfig] = []
    if args.config:
        configs.extend(load_config_yaml(args.config))
    for spec in args.cli:
        configs.append(parse_inline_cli(spec))
    if not configs:
        configs = default_configs()
    return configs


if __name__ == "__main__":
    sys.exit(main())
