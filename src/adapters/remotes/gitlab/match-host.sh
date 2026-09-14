#!/usr/bin/env bash

case "${1:-}" in
  gitlab.com|www.gitlab.com) exit 0 ;;
  *) exit 1 ;;
esac
