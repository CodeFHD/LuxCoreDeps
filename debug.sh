# SPDX-FileCopyrightText: 2024 Howetuft
#
# SPDX-License-Identifier: Apache-2.0

# Debug linux build locally


# Script to run build locally. You need 'act' to be installed in your
# system

#export CIBW_DEBUG_KEEP_CONTAINER=TRUE
act \
  --action-offline-mode \
  -s GITHUB_TOKEN="$(gh auth token)" \
  --matrix os:ubuntu-latest --matrix python-minor:'8' \
  --artifact-server-path /tmp/artifacts
