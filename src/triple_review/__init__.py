"""triple-review: parallel multi-CLI code review with adversarial Sigma falsification gate."""
from .core import Finding, ReviewResult, run_review
from .consensus import build_consensus, ConsensusFinding
from .falsify import sigma_gate

__version__ = "0.1.0"
__all__ = [
    "Finding", "ReviewResult", "run_review",
    "ConsensusFinding", "build_consensus",
    "sigma_gate",
]
