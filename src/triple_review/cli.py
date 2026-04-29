"""triple-review CLI: review files locally or in CI."""
from __future__ import annotations

import argparse
import json
import sys

from .core import run_review
from .consensus import build_consensus
from .falsify import sigma_gate, render_pr_comments


def main() -> int:
    parser = argparse.ArgumentParser(description="Multi-CLI parallel code review with adversarial falsification gate")
    parser.add_argument("files", nargs="+", help="files to review")
    parser.add_argument("--falsify", action="store_true", help="run Sigma falsification gate")
    parser.add_argument("--pr-comments", action="store_true", help="emit PR-comment JSON payloads")
    parser.add_argument("--json", action="store_true", help="JSON output instead of human")
    args = parser.parse_args()

    all_results = []
    for path in args.files:
        all_results.extend(run_review(path))

    consensus = build_consensus(all_results)

    if args.falsify:
        gate = sigma_gate(consensus)
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


if __name__ == "__main__":
    sys.exit(main())
