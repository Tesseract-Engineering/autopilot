from inventory.stock import Stock


def test_add_and_level():
    s = Stock()
    s.add("apple", 5)
    assert s.level("apple") == 5


def test_remove():
    s = Stock()
    s.add("apple", 5)
    s.remove("apple", 2)
    assert s.level("apple") == 3
