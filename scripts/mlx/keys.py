"""Skriver ut nycklarna i Klangs MLX-vikter för första lagret och allt utanför kodarens lager,
så att de kan jämföras med vad mlx-audio-swift väntar sig. Kör: python keys.py <hf-repo>"""
import sys

import mlx.core as mx
from huggingface_hub import snapshot_download

path = snapshot_download(sys.argv[1], allow_patterns=["*.safetensors", "config.json"])
import glob, json  # noqa: E401,E402

for file in glob.glob(f"{path}/*.safetensors"):
    weights = mx.load(file)
    for key in sorted(weights):
        if ".layers." in key and ".layers.0." not in key:
            continue
        print(key, weights[key].dtype, tuple(weights[key].shape))
config = json.load(open(f"{path}/config.json"))
print("CONFIG-NYCKLAR:", sorted(config))
for k in ("encoder", "quantization", "model_type", "target"):
    if k in config:
        print(k, json.dumps(config[k])[:600])
