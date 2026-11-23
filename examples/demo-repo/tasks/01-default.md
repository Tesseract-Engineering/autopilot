# Task 1 (default pattern): validate discounts

`apply_discount(total, pct)` silently accepts nonsense. Change it so that:
- `pct` outside 0..100 (inclusive) raises `ValueError`.
- `total` below 0 raises `ValueError`.
- The result is rounded to 2 decimal places.

Existing behavior for valid input must not change.
