#!/usr/bin/env bash

case "${1:-}" in
  github.com|www.github.com) exit 0 ;;
  *) exit 1 ;;
esac
