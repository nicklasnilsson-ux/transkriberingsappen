"""Konverterar KlangAI:s Pianissimo (svensk Parakeet TDT v3) till CoreML-paket.

Körs av .github/workflows/pianissimo-model.yml på en Linux-runner, med Fluid
Inference:s exportverktyg för Parakeet TDT v3 (mobius). Pianissimo har samma
arkitektur och ordlista som NVIDIA:s Parakeet TDT v3, så komponenterna får exakt
samma in- och utdata som FluidAudio förväntar sig:

    python convert.py --mobius <mobius>/models/stt/parakeet-tdt-v3-0.6b/coreml --out out

Resultat: out/pianissimo-sv/ med Preprocessor, Encoder, Decoder och JointDecisionv3
som .mlpackage samt parakeet_vocab.json. Paketen kompileras och kvantiseras sedan
på en Mac (se workflowet).
"""

import argparse
import json
import os
import runpy
import shutil
import sys
from pathlib import Path

MODEL_ID = "KlangAI/pianissimo-sv"

# mobius-namn → namn som FluidAudio läser (AsrModelVersion.v3).
COMPONENTS = {
    "parakeet_preprocessor.mlpackage": "Preprocessor.mlpackage",
    "parakeet_encoder.mlpackage": "Encoder.mlpackage",
    "parakeet_decoder.mlpackage": "Decoder.mlpackage",
    "parakeet_joint_decision_single_step.mlpackage": "JointDecisionv3.mlpackage",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mobius", required=True, type=Path, help="mobius/models/stt/parakeet-tdt-v3-0.6b/coreml")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    mobius = args.mobius.resolve()
    work = (args.out / "work").resolve()
    final = (args.out / "pianissimo-sv").resolve()
    final.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(mobius))

    import nemo.collections.asr as nemo_asr

    # Pianissimo använder lokal uppmärksamhet (256 bildrutor åt varje håll) för långa
    # inspelningar. FluidAudio kör 15-sekundersfönster (188 bildrutor), där lokal och
    # full uppmärksamhet ger samma resultat. Full uppmärksamhet ger samma graf som v3.
    loaded = {}
    original = nemo_asr.models.EncDecRNNTBPEModel.from_pretrained

    def from_pretrained(*a, **k):
        model = original(*a, **k)
        print("Uppmärksamhet före:", model.cfg.encoder.get("self_attention_model"), model.cfg.encoder.get("att_context_size"))
        model.change_attention_model(self_attention_model="rel_pos", att_context_size=[-1, -1])
        loaded["model"] = model
        return model

    nemo_asr.models.EncDecRNNTBPEModel.from_pretrained = staticmethod(from_pretrained)

    module = runpy.run_path(str(mobius / "convert-parakeet.py"), run_name="mobius_convert")
    module["convert"](
        nemo_path=None,
        model_id=MODEL_ID,
        output_dir=work,
        preprocessor_cu="CPU_ONLY",
        mel_encoder_cu="CPU_ONLY",
        compute_precision="FLOAT16",
    )

    for source, target in COMPONENTS.items():
        shutil.copytree(work / source, final / target, dirs_exist_ok=True)

    # Ordlistan i samma format som FluidInference/parakeet-tdt-0.6b-v3-coreml: {"id": "token"}.
    model = loaded["model"]
    preprocessor = model.cfg.preprocessor
    print("Förbehandling:", {k: preprocessor.get(k) for k in ["sample_rate", "features", "n_fft", "window_size", "window_stride", "normalize"]})
    if int(preprocessor.get("features")) != 128:
        raise SystemExit("Pianissimo ska ha 128 mel-band som Parakeet v3")
    vocab_size = int(model.tokenizer.vocab_size)
    tokens = model.tokenizer.ids_to_tokens(list(range(vocab_size)))
    with open(final / "parakeet_vocab.json", "w") as f:
        json.dump({str(i): token for i, token in enumerate(tokens)}, f, ensure_ascii=False)
    print(f"Ordlista: {vocab_size} token")

    with open(final / "conversion.json", "w") as f:
        json.dump({
            "source": MODEL_ID,
            "license": "CC BY 4.0 (KlangAI)",
            "exporter": "FluidInference/mobius parakeet-tdt-v3-0.6b/coreml",
            "attention": "rel_pos (full) i 15 s fönster",
            "vocab_size": vocab_size,
        }, f, indent=2)

    shutil.rmtree(work, ignore_errors=True)
    print("Klar:", final, os.listdir(final))


if __name__ == "__main__":
    main()
