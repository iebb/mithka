#!/usr/bin/env python3
"""Record an already-successful Play upload without broad workflow permissions."""

import os

from weekly_store_release import Error, record_play_marker

if __name__ == "__main__":
    try:
        if os.environ.get("GITHUB_REPOSITORY") != "iebb/mithka":
            raise Error("only the canonical repository can record publication")
        record_play_marker(
            os.environ["SOURCE_SHA"],
            os.environ["VERSION_CODE"],
            os.environ["GITHUB_RUN_ID"],
        )
    except (Error, KeyError, ValueError) as error:
        print(str(error) if isinstance(error, Error) else type(error).__name__)
        raise SystemExit(1)
