"""Structural train/validation split checks, independent of training runtimes."""

from __future__ import annotations

import math


def split_counts(sample_count: int, val_split: float) -> tuple[int, int]:
    """Return nonempty train/validation counts with the existing BC rounding.

    The minimum of one sample per partition is required to compute both losses;
    it is not a corpus-quality or study-size requirement.
    """
    if type(sample_count) is not int or sample_count < 0:
        raise ValueError("sample_count must be a nonnegative integer")
    try:
        valid = (not isinstance(val_split, bool) and isinstance(val_split, (int, float))
                 and math.isfinite(val_split) and 0 < val_split < 1)
    except OverflowError:
        valid = False
    if not valid:
        raise ValueError("val_split must be a finite number strictly between 0 and 1")

    n_val = max(1, int(sample_count * val_split))
    n_train = sample_count - n_val
    if n_train < 1 or n_val < 1:
        raise ValueError(
            "BC train/validation split requires at least one sample in each partition: "
            f"samples={sample_count}, train={n_train}, validation={n_val}, val_split={val_split}"
        )
    return n_train, n_val
