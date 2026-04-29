"""triple-review: parallel multi-CLI code review with adversarial Sigma falsification gate."""
from .core import Finding, ReviewConfig, ReviewResult, run_review
from .consensus import ConsensusFinding, build_consensus
from .falsify import sigma_gate
from .config import load_config_yaml, parse_inline_cli

__version__ = "0.2.0"
__all__ = [
    "Finding", "ReviewConfig", "ReviewResult", "run_review",
    "ConsensusFinding", "build_consensus",
    "sigma_gate",
    "load_config_yaml", "parse_inline_cli",
]
