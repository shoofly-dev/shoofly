#!/usr/bin/env bash
# Shoofly Basic — canonical URL is https://shoofly.dev/install.sh
# This file redirects for backwards compatibility.
exec bash <(curl -fsSL https://shoofly.dev/install.sh) "$@"
