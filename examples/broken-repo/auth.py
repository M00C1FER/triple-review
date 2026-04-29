"""Example file for triple-review demos. Contains 5 deliberate issues."""
import hashlib
import os
import sqlite3


# Issue 1: hardcoded secret
API_KEY = "sk-1234567890abcdef"


def hash_password(password: str) -> str:
    # Issue 2: MD5 for password hashing
    return hashlib.md5(password.encode()).hexdigest()


def login(username: str, password: str, conn: sqlite3.Connection) -> bool:
    # Issue 3: SQL injection
    cur = conn.cursor()
    cur.execute(f"SELECT 1 FROM users WHERE name='{username}' AND pw='{hash_password(password)}'")
    return cur.fetchone() is not None


def run_user_cmd(cmd: str) -> str:
    # Issue 4: shell injection
    return os.popen(cmd).read()


def make_session_id() -> str:
    # Issue 5: predictable PRNG for security context
    import random
    return f"{random.randint(0, 2**32):08x}"
