This is the complete `gpt-5.5` entry from OpenAI Codex `rust-v0.153.4`:
https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/models-manager/models.json

The upstream Apache-2.0 license is retained in `LICENSE`. Three fields differ:
`apply_patch_tool_type=null`, `shell_type="disabled"`,
and `supports_search_tool=false`; `experimental_supported_tools` remains empty.
All reasoning, context, instruction and service-tier metadata is preserved.
The provider verifies a pinned SHA256 before use. The hosted CLI version remains
pinned independently by the VPS manifest/executor configuration.
The offline acceptance targets CLI 0.153.4. Local development still permits an
empty expected-version setting; that is not verification of other CLI versions.

An explicit catalog selects Codex's static model manager, so remote catalog
refresh cannot restore the removed capabilities. CLI flags additionally disable
web search, planning and user-input tools. This is not a general-purpose model
catalog or a runtime-selectable profile.

The resulting model request contains the three Coach MCP data tools and three
built-in MCP resource helpers. The sole configured Coach server does not support
resource methods, and the existing event validator rejects non-allowlisted
tool calls. Those helpers have no additional data authority; attempting them
can still fail a turn. Do not claim that only three tools are visible.

Upgrade this file only with exact-version source review, an offline wire capture,
the provider/MCP adversarial tests and a new content hash. Live provider acceptance
is separate; this file never authorizes authentication or activation.
