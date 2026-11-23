# Task 2 (fan-out pattern): two independent changes

1. **Stock:** `Stock.remove(sku, qty)` must raise `InsufficientStock` (a new
   exception class defined in `inventory/stock.py`) when `qty` exceeds the
   current level, leaving the level unchanged.
2. **Pricing:** add `bulk_price(unit_price, qty)` to `inventory/pricing.py`:
   10% off the line total when `qty >= 10`, otherwise no discount.

The two changes touch different files and can be built in parallel.
