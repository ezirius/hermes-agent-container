#!/usr/bin/env bash

set -euo pipefail

# These are tiny test helpers that make shell test failures easy to read.

# This stops the test right away with one clear failure message.
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# This checks that two values are exactly the same.
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-expected values to match}"

  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected [$expected], got [$actual]"
  fi
}

# This checks that one piece of text appears inside another one.
assert_contains() {
  local needle="$1"
  local haystack="$2"
  local message="${3:-expected substring not found}"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message: missing [$needle]"
  fi
}

# This checks that a file contains the text the test expects to see.
assert_file_contains() {
  local needle="$1"
  local file_path="$2"
  local message="${3:-expected file substring not found}"

  if ! grep -Fq -- "$needle" "$file_path"; then
    fail "$message: missing [$needle] in $file_path"
  fi
}
