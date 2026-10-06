"""Update the pinned Sitegeist bundle's Codex subscription model catalog."""

import json
import pathlib
import sys

# Verified against Codex's model catalog on 2026-10-06. Hidden/internal models
# are excluded. Subscription requests have no per-token API charge here.
models = {
    "gpt-6-astra": "GPT-6 Astra",
    "gpt-6-sol": "GPT-6 Sol",
    "gpt-6-luna": "GPT-6 Luna",
    "gpt-5.6-sol": "GPT-5.6 Sol",
    "gpt-5.6-terra": "GPT-5.6 Terra",
    "gpt-5.6-luna": "GPT-5.6 Luna",
}

for filename in ("sidepanel.js", "debug.js"):
    path = pathlib.Path(sys.argv[1]) / filename
    source = path.read_text()
    indent = "      " if filename == "sidepanel.js" else "  "
    marker = '\n' + indent + '"openai-codex": {\n'
    assert source.count(marker) == 1, f"{filename}: model catalog changed"
    entries = {}
    for model_id, name in models.items():
        entries[model_id] = {
            "id": model_id,
            "name": name,
            "api": "openai-codex-responses",
            "provider": "openai-codex",
            "baseUrl": "https://chatgpt.com/backend-api",
            "reasoning": True,
            "input": ["text", "image"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 272000,
            "maxTokens": 128000,
        }
    source = source.replace(marker, marker + json.dumps(entries)[1:-1] + ",\n", 1)

    # This bundled client offers reasoning through xhigh. Expose that level
    # for the new models and normalize its old "minimal" option to "low".
    for old, new in (
        ('model.id.includes("gpt-5.4")',
         '(model.id.includes("gpt-5.4") || model.id.startsWith("gpt-5.6-") || model.id.startsWith("gpt-6-"))'),
        ('id.startsWith("gpt-5.4")',
         '(id.startsWith("gpt-5.4") || id.startsWith("gpt-5.6-") || id.startsWith("gpt-6-"))'),
    ):
        assert old in source, f"{filename}: reasoning handling changed"
        source = source.replace(old, new)
    path.write_text(source)
