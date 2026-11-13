"""Lägger Klangs MLX-filer i en egen mapp och byter attention-modellen i config.json till
"rel_pos", som är den mlx-audio-swift kan ladda. Vikterna rörs inte; rel_pos är samma
vikter med uppmärksamhet över hela fönstret i stället för ett lokalt fönster.
Kör: python prepare.py <hf-repo> <utmapp>"""
import json
import shutil
import sys
from pathlib import Path

from huggingface_hub import snapshot_download

repo, out = sys.argv[1], Path(sys.argv[2])
src = Path(snapshot_download(repo))
shutil.copytree(src, out, dirs_exist_ok=True)
config = json.loads((out / "config.json").read_text())
before = config["encoder"].get("self_attention_model")
config["encoder"]["self_attention_model"] = "rel_pos"
(out / "config.json").write_text(json.dumps(config))
print(f"{repo}: self_attention_model {before} -> rel_pos, att_context_size {config['encoder'].get('att_context_size')}")
