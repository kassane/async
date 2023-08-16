#!/bin/bash

# Array of git URLs
GIT_URLS=(
    "git+https://github.com/boostorg/circular_buffer"
    "git+https://github.com/boostorg/leaf"
    "git+https://github.com/boostorg/url"
    "git+https://github.com/boostorg/function"
    "git+https://github.com/boostorg/signals2"
    "git+https://github.com/boostorg/variant"
    "git+https://github.com/boostorg/integer"
    "git+https://github.com/boostorg/unordered"
    "git+https://github.com/boostorg/parameter"
    "git+https://github.com/boostorg/callable_traits"
    "git+https://github.com/boostorg/type_index"
    "git+https://github.com/boostorg/lockfree"
    "git+https://github.com/kassane/beast"
    "git+https://github.com/kassane/context"
)

# Loop through each URL
for GIT_URL in "${GIT_URLS[@]}"
do
  # Extract the package name from the URL
  PKG_NAME=$(basename "$GIT_URL")

  # Use zig fetch with the package name and URL
  zig fetch --save="$PKG_NAME" "$GIT_URL"
done
