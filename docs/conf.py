# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

"""Sphinx configuration - CMake domain docs extracted from the module sources."""

project = "find_ocx"
author = "The OCX Authors"
copyright = "2026, The OCX Authors"

extensions = ["sphinxcontrib.moderncmakedomain"]
primary_domain = "cmake"

master_doc = "index"
html_title = "find_ocx"
exclude_patterns = ["_build", ".venv"]
