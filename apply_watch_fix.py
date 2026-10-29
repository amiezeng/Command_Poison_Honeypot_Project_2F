#!/usr/bin/env python3
# copy watch_session and the leave-reason labels from a fixed lifecycle.sh
# into the copy that is running on the vm.
# usage: python3 apply_watch_fix.py /tmp/lifecycle.mac.sh lifecycle.sh

import re
import sys
from pathlib import Path


def function_span(text, name):
    match = re.search(rf"^{name}\(\) \{{", text, re.M)
    if match is None:
        raise SystemExit(f"missing {name}()")
    start = match.start()
    depth = 0
    for index in range(match.end() - 1, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return start, index + 1
    raise SystemExit(f"no closing brace for {name}")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: apply_watch_fix.py <new lifecycle.sh> <vm lifecycle.sh>")
    src = Path(sys.argv[1]).read_text()
    dest_path = Path(sys.argv[2])
    dest = dest_path.read_text()
    dest_path.with_suffix(".sh.before-limit").write_text(dest)
    start, end = function_span(src, "watch_session")
    old_start, old_end = function_span(dest, "watch_session")
    dest = dest[:old_start] + src[start:end] + dest[old_end:]
    dest = re.sub(r'logout\) why=.*', 'logout) why="attacker left" ;;', dest, count=1)
    dest = re.sub(r'idle\) why=.*', 'idle) why="idle timeout" ;;', dest, count=1)
    dest = re.sub(r'timeout\) why=.*', 'timeout) why="session timeout" ;;', dest, count=1)
    dest_path.write_text(dest)
    print(f"updated {dest_path}")


if __name__ == "__main__":
    main()
