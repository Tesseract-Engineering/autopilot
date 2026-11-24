"""Stock levels per SKU."""


class Stock:
    def __init__(self):
        self._levels = {}

    def add(self, sku, qty):
        self._levels[sku] = self._levels.get(sku, 0) + qty

    def level(self, sku):
        return self._levels.get(sku, 0)

    def remove(self, sku, qty):
        self._levels[sku] = self.level(sku) - qty
