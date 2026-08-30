from value_investing.hashing import canonical_json, sha256_hex


def test_canonical_hash_ignores_dictionary_insertion_order():
    left = {"b": 2, "a": [3, 1]}
    right = {"a": [3, 1], "b": 2}
    assert canonical_json(left) == canonical_json(right)
    assert sha256_hex(left) == sha256_hex(right)
