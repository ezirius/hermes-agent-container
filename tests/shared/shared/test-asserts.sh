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

# This checks that a file does not contain text we should never have written.
assert_file_not_contains() {
  local needle="$1"
  local file_path="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file_path"; then
    fail "$message: unexpected [$needle] in $file_path"
  fi
}

# This checks that two file snippets both exist and appear in the expected order.
assert_file_contains_in_order() {
  local first_text="$1"
  local second_text="$2"
  local file_path="$3"
  local message="${4:-expected file snippets to appear in order}"
  local file_text=""
  local after_first_text=""

  file_text="$(<"$file_path")"
  if [[ "$file_text" != *"$first_text"* ]]; then
    fail "$message: missing [$first_text] in $file_path"
  fi

  if [[ "$file_text" != *"$second_text"* ]]; then
    fail "$message: missing [$second_text] in $file_path"
  fi

  after_first_text="${file_text#*"$first_text"}"
  if [[ "$after_first_text" != *"$second_text"* ]]; then
    fail "$message: [$first_text] must appear before [$second_text] in $file_path"
  fi
}
