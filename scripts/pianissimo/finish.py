"""Gör Pianissimo-paketen färdiga för appen. Körs på macOS efter convert.py:

    python finish.py --packages in/pianissimo-sv --out out/pianissimo-sv

Kodaren kvantiseras till 8 bitar per kanal (ungefär halva storleken, samma
felfrekvens enligt Fluid Inference:s mätningar på Parakeet), och alla delar
kompileras till .mlmodelc som FluidAudio läser direkt.
"""

import argparse
import json
import shutil
import subprocess
from pathlib import Path

import coremltools as ct
import coremltools.optimize.coreml as cto

COMPONENTS = ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"]


def compile_package(package: Path, out: Path, name: str):
    tmp = out / "compile"
    tmp.mkdir(exist_ok=True)
    subprocess.run(["xcrun", "coremlcompiler", "compile", str(package), str(tmp)], check=True)
    compiled = tmp / f"{package.stem}.mlmodelc"
    target = out / f"{name}.mlmodelc"
    shutil.rmtree(target, ignore_errors=True)
    shutil.move(str(compiled), str(target))
    shutil.rmtree(tmp)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--packages", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    for name in COMPONENTS:
        package = args.packages / f"{name}.mlpackage"
        if not package.is_dir():
            raise SystemExit(f"Saknar {package}")
        if name == "Encoder":
            model = ct.models.MLModel(str(package), skip_model_load=True)
            config = cto.OptimizationConfig(
                global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", granularity="per_channel")
            )
            quantized = cto.linear_quantize_weights(model, config=config)
            package = args.out / "Encoder-int8.mlpackage"
            quantized.save(str(package))
        compile_package(package, args.out, name)
        if package.parent == args.out:
            shutil.rmtree(package)

    for filename in ["parakeet_vocab.json", "conversion.json"]:
        shutil.copy(args.packages / filename, args.out / filename)

    info = json.loads((args.out / "conversion.json").read_text())
    info["encoder_weights"] = "int8 (linear_symmetric, per_channel)"
    (args.out / "conversion.json").write_text(json.dumps(info, indent=2))
    print("Klar:", sorted(p.name for p in args.out.iterdir()))


if __name__ == "__main__":
    main()
