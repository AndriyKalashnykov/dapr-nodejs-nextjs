#!/usr/bin/env bash
# Pick a free TCP port from the kernel's ephemeral range.
#
# Usage: scripts/pick-port.sh
# Prints a single free port number to stdout.
#
# Binds port 0 (OS-assigned), reads back the assigned port, releases it.
# Note: there is an unavoidable TOCTOU race between `close()` and the
# caller's subsequent `bind()`. Use this in CI where collision is rare,
# not in tight test loops.

set -euo pipefail

if command -v python3 >/dev/null 2>&1; then
  python3 -c "import socket; s=socket.socket(); s.bind(('', 0)); print(s.getsockname()[1]); s.close()"
elif command -v python >/dev/null 2>&1; then
  python -c "import socket; s=socket.socket(); s.bind(('', 0)); print(s.getsockname()[1]); s.close()"
elif command -v node >/dev/null 2>&1; then
  node -e "const s=require('net').createServer();s.listen(0,()=>{console.log(s.address().port);s.close();});"
else
  echo "pick-port.sh: needs python3 or node" >&2
  exit 1
fi
