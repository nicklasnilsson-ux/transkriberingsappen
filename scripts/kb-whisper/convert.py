"""Konverterar en KB-Whisper-modell (KBLab) till WhisperKits CoreML-format.

Körs av .github/workflows/kb-whisper-models.yml på en macOS-runner:

    python convert.py --size small --out out [--int8] [--variant strict]

Resultat: out/kb-whisper-<size>[-strict]/ med AudioEncoder.mlmodelc, TextDecoder.mlmodelc,
MelSpectrogram.mlmodelc, config.json och generation_config.json – samma layout
som https://huggingface.co/argmaxinc/whisperkit-coreml använder.
"""

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

from huggingface_hub import hf_hub_download, snapshot_download

# Behåll .mlpackage efter kompilering så att vi kan kvantisera i efterhand.
import argmaxtools.test_utils as test_utils

_original_save = test_utils._save_coreml_asset


def _save_keep_mlpackage(model, out_dir, fname, do_compile=True, do_remove_mlpackage=True):
    _original_save(model, out_dir, fname, do_compile=do_compile, do_remove_mlpackage=False)


test_utils._save_coreml_asset = _save_keep_mlpackage

from scripts import generate_model  # noqa: E402  (whisperkittools)


def quantize_int8(mlpackage, out_dir, name):
    import coremltools as ct
    import coremltools.optimize.coreml as cto

    model = ct.models.MLModel(mlpackage, skip_model_load=True)
    config = cto.OptimizationConfig(
        global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=2048)
    )
    quantized = cto.linear_quantize_weights(model, config=config)
    tmp = os.path.join(out_dir, f"{name}-int8.mlpackage")
    quantized.save(tmp)
    target = os.path.join(out_dir, f"{name}.mlmodelc")
    shutil.rmtree(target, ignore_errors=True)
    subprocess.run(["xcrun", "coremlcompiler", "compile", tmp, out_dir], check=True)
    shutil.move(os.path.join(out_dir, f"{name}-int8.mlmodelc"), target)
    shutil.rmtree(tmp)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", required=True, choices=["tiny", "base", "small", "medium", "large"])
    parser.add_argument("--out", required=True)
    parser.add_argument("--int8", action="store_true", help="Kvantisera vikterna till 8 bitar")
    parser.add_argument(
        "--variant", default="standard", choices=["standard", "strict"],
        help="KBLab:s stilvariant: standard eller strict (mer ordagrann)",
    )
    args = parser.parse_args()

    repo = f"KBLab/kb-whisper-{args.size}"
    model_name = f"kb-whisper-{args.size}" + ("" if args.variant == "standard" else f"-{args.variant}")
    revision = None if args.variant == "standard" else args.variant
    if revision:
        # whisperkittools tar bara ett modellnamn, inte en revision. Ladda ner varianten till
        # en lokal mapp och ange sökvägen; den laddas då därifrån i stället för från hubben.
        source = os.path.join("hf", "KBLab", model_name)
        snapshot_download(
            repo_id=repo,
            revision=revision,
            local_dir=source,
            allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model"],
            ignore_patterns=["*/*"],
        )
    else:
        source = repo
    work = os.path.abspath(os.path.join(args.out, "work"))
    sys.argv = ["whisperkit-generate-model", "--model-version", source, "--output-dir", work]
    generate_model.cli()

    built = os.path.join(work, source.replace("/", "_"))
    final = os.path.abspath(os.path.join(args.out, model_name))
    os.makedirs(final, exist_ok=True)

    for name in ["AudioEncoder", "TextDecoder", "MelSpectrogram"]:
        compiled = os.path.join(built, f"{name}.mlmodelc")
        if not os.path.isdir(compiled):
            raise SystemExit(f"Saknar {compiled} – konverteringen misslyckades")
        if args.int8 and name != "MelSpectrogram":
            quantize_int8(os.path.join(built, f"{name}.mlpackage"), built, name)
        shutil.copytree(compiled, os.path.join(final, f"{name}.mlmodelc"))

    for filename in ["config.json", "generation_config.json"]:
        with open(hf_hub_download(repo_id=repo, filename=filename, revision=revision)) as f:
            data = json.load(f)
        with open(os.path.join(final, filename), "w") as f:
            json.dump(data, f)

    whisperkittools_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=os.path.dirname(generate_model.__file__)
    ).stdout.strip()
    with open(os.path.join(final, "conversion.json"), "w") as f:
        json.dump({
            "source": repo,
            "revision": revision or "standard",
            "whisperkittools": whisperkittools_commit,
            "weights": "int8 (linear_symmetric)" if args.int8 else "float16",
        }, f, indent=2)

    size_mb = sum(os.path.getsize(p) for p in glob.glob(f"{final}/**/*", recursive=True) if os.path.isfile(p)) / 1e6
    print(f"Klar: {final} ({size_mb:.0f} MB)")


if __name__ == "__main__":
    main()
