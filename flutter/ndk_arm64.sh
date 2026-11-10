#!/usr/bin/env bash
# hwcodec's build.rs includes host <stdint.h>. On Ubuntu CI, clang only finds
# bits/libc-header-start.h when gcc-multilib is installed. Official Flutter
# Tag Build already installs it; Hobson build now does the same here so a
# workflow-file edit is not required.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  if ! dpkg-query -W -f='${Status}' gcc-multilib 2>/dev/null | grep -q "install ok installed"; then
    sudo apt-get update
    sudo apt-get install -y gcc-multilib g++-multilib libc6-dev
  fi
fi
cargo ndk --platform 21 --target aarch64-linux-android build --locked --release --features flutter,hwcodec
