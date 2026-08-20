#!/usr/bin/env python3
"""Fallback de install.sh quando 'jq' não está disponível — mesma lógica de
mesclagem (hooks/lib.sh de cada ferramenta já cai pra fallback sem jq
também, mas na LEITURA de um comando; aqui é ESCRITA/mesclagem de config,
que precisa de um parser JSON de verdade — não dá pra fazer com
grep/sed sem risco real de corromper o arquivo).

Uso: install_merge.py TARGET_FILE SOURCE_FILE SOURCE_SHAPE TARGET_SHAPE OUTPUT_FILE
  SHAPE em {flat, nested} — nested = eventos dentro de "hooks".

Preserva a ordem: o que já está no alvo continua onde está e o que é novo
vai pro fim — hook roda na ordem em que aparece no arquivo, então reordenar
muda comportamento. Mesma semântica do lado jq de install.sh.
"""
import json
import sys


def append_new(existing, incoming):
    """Acrescenta só o que ainda não está em `existing`, preservando a ordem.

    A comparação é por igualdade de valor (dois dicts com as mesmas chaves
    são iguais independente da ordem delas), igual ao `==` do jq.
    """
    merged = list(existing)
    for item in incoming:
        if item not in merged:
            merged.append(item)
    return merged


def merge_events(target_events, source_events):
    for event, entries in source_events.items():
        target_events[event] = append_new(target_events.get(event, []), entries)
    return target_events


def main():
    target_file, source_file, source_shape, target_shape, output_file = sys.argv[1:6]

    with open(target_file) as f:
        target = json.load(f)
    with open(source_file) as f:
        source = json.load(f)

    source_events = source["hooks"] if source_shape == "nested" else source

    if target_shape == "nested":
        target["hooks"] = merge_events(target.get("hooks", {}), source_events)
    else:
        merge_events(target, source_events)

    with open(output_file, "w") as f:
        json.dump(target, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
