#!/bin/bash
# One-shot setup for the Direct Mapped Cache Controller project on a Mac.
#
# Usage (from the project folder):
#     bash setup_mac.sh
#
# It installs what is missing (safe to run again; installed things are skipped):
#   - Xcode Command Line Tools  (gives you make, git, python3)
#   - Homebrew
#   - Icarus Verilog            (iverilog + vvp, the simulator)
# Then it runs a quick check simulation to prove everything works.

set -u

say()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")" || fail "cannot enter project folder"

[ "$(uname -s)" = "Darwin" ] || fail "this script is for macOS only"

# ---- 1. Xcode Command Line Tools (make, git, python3) ----
say "Checking Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Not installed. A popup will appear: click 'Install' and wait for it to finish."
  xcode-select --install 2>/dev/null
  echo "Waiting for the installation to finish..."
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
fi
echo "OK"

# ---- 2. Homebrew ----
say "Checking Homebrew"
# Make brew visible in this script on Apple Silicon and Intel Macs.
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && eval "$("$b" shellenv)" && break
done
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing (it will ask for your Mac password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || fail "Homebrew installation failed"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
  command -v brew >/dev/null 2>&1 || fail "brew still not found after install"
fi
echo "OK: $(brew --version | head -1)"

# ---- 3. Icarus Verilog ----
say "Checking Icarus Verilog"
if ! command -v iverilog >/dev/null 2>&1 || ! command -v vvp >/dev/null 2>&1; then
  brew install icarus-verilog || fail "could not install icarus-verilog"
fi
echo "OK: $(iverilog -V 2>&1 | head -1)"

# ---- 4. Make sure the other tools exist ----
say "Checking make and python3"
command -v make    >/dev/null 2>&1 || fail "make not found (Command Line Tools incomplete)"
command -v python3 >/dev/null 2>&1 || brew install python || fail "could not install python3"
echo "OK: $(python3 --version)"

# ---- 5. Quick proof that it works (writes only to build/, not results/) ----
say "Running a quick check simulation"
mkdir -p build
iverilog -g2001 -Wall -s cache_tb -o build/setup_check.vvp \
    testbench/cache_tb.v rtl/main_memory.v rtl/cache_memory.v rtl/cache_controller.v rtl/cache_top.v \
    || fail "compile failed"
vvp build/setup_check.vvp +novcd > build/setup_check.log 2>&1
if grep -q "RESULT: ALL TESTS PASSED" build/setup_check.log; then
  grep -E "SUMMARY|RESULT" build/setup_check.log
  say "SETUP COMPLETE. Everything works."
  echo "Now run the demo with:   make phase1"
else
  tail -20 build/setup_check.log
  fail "simulation did not pass; see build/setup_check.log"
fi
