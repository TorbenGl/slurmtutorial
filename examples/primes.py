#!/usr/bin/env python3
"""Count prime numbers up to N with a simple Sieve of Eratosthenes.

Used as "step A" in the job-dependency demo: it writes its result to a file that
"step B" reads back.

Usage:
    python primes.py [N] [output_file]
"""
import sys


def count_primes(n: int) -> int:
    if n < 2:
        return 0
    sieve = bytearray([1]) * (n + 1)
    sieve[0] = sieve[1] = 0
    for i in range(2, int(n**0.5) + 1):
        if sieve[i]:
            sieve[i * i :: i] = bytearray(len(sieve[i * i :: i]))
    return sum(sieve)


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
    out = sys.argv[2] if len(sys.argv) > 2 else "primes_result.txt"
    total = count_primes(n)
    with open(out, "w") as f:
        f.write(str(total))
    print(f"There are {total:,} primes <= {n:,} (written to {out})")
