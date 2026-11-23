from inventory.pricing import apply_discount, subtotal


def test_subtotal():
    assert subtotal([(2.0, 3), (1.5, 2)]) == 9.0


def test_apply_discount():
    assert apply_discount(200, 10) == 180
