# Bundled dependencies

These source snapshots make release archives and CI independent of sibling checkouts.

| Package | Upstream | Commit |
| --- | --- | --- |
| z-parser | https://github.com/carlos-sweb/z-parser | `35cb8ad5dd6f208b7a0bb9abb8ec7b17d39742aa` |
| z-lexer | https://github.com/carlos-sweb/z-lexer | `08e123597183b4934d7c1c6ec595f1ffd2ceb43f` |

The z-lexer manifest uses z-regex v0.9.1 from its upstream release archive,
with a verified Zig package hash. z-parser resolves the same bundled z-lexer.
Upstream source, tests, and README files are retained unchanged.
