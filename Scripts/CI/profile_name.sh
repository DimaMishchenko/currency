#!/bin/bash
set -euo pipefail

bundle=${1#com.dimasike.}
date_stamp=$(date -u +%Y%m%d)
suffix=$(openssl rand -hex 4)
printf 'Currency CI %.34s %s %s\n' "$bundle" "$date_stamp" "$suffix"
