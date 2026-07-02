# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

"""Sphinx configuration - CMake domain docs extracted from the module sources."""

project = "find_ocx"
author = "The OCX Authors"
copyright = "2026, The OCX Authors"

extensions = ["sphinxcontrib.moderncmakedomain"]
primary_domain = "cmake"
highlight_language = "cmake"
# Pygments' cmake lexer can't tokenize bracket arguments ([[...]]); the
# fallback rendering is fine and the code itself is CI-tested.
suppress_warnings = ["misc.highlighting_failure"]

master_doc = "index"
html_title = "find_ocx"
exclude_patterns = ["_build", ".venv"]

html_theme = "furo"
html_theme_options = {
    "source_repository": "https://github.com/ocx-sh/find_ocx",
    "source_branch": "main",
    "source_directory": "docs/",
}
