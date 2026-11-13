"""Referens: Klangs egen laddare (pianissimo_mlx.py) med parakeet-mlx, som på modellkortet.
Kör: python reference.py <hf-repo> <ljud.wav>"""
import sys
import time
import wave

import numpy as np
from huggingface_hub import snapshot_download

repo, audio_path = sys.argv[1], sys.argv[2]
path = snapshot_download(repo)
sys.path.append(path)
import pianissimo_mlx  # noqa: E402

with wave.open(audio_path) as w:
    assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
    audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768

start = time.time()
model = pianissimo_mlx.load(path)
loaded = time.time()
result = pianissimo_mlx.transcribe(model, audio)
print(f"MODELL: {repo} (Klangs laddare)")
print(f"LADDNING: {loaded - start:.1f} s, TRANSKRIBERING: {time.time() - loaded:.2f} s")
print(f"TEXT: {result.text}")
