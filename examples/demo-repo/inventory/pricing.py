"""Order pricing."""


def subtotal(items):
    """Sum of price * qty for (price, qty) pairs."""
    return sum(price * qty for price, qty in items)


def apply_discount(total, pct):
    """Return total reduced by pct percent."""
    return total * (1 - pct / 100)
