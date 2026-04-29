# broken-repo demo

`auth.py` contains 5 deliberate issues (1 hardcoded secret, 1 weak crypto, 1 SQLi, 1 shell injection, 1 weak PRNG).

A single LLM reviewer typically catches 3–4. The `triple-review` consensus picks up all 5; the falsification gate trims false positives like "MD5 is fine if you salt it" arguments.

Run:
```bash
triple-review --falsify auth.py
```

Expected output: `[SURVIVED] unanimous/critical auth.py:8 — hardcoded API key`, etc.
