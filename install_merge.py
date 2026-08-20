#!/usr/bin/env python3
"""Fallback de install.sh quando 'jq' não está disponível — mesma lógica de
mesclagem (hooks/lib.sh de cada ferramenta já cai pra fallback sem jq
também, mas na LEITURA de um comando; aqui é ESCRITA/mesclagem de config,
que precisa de um parser JSON de verdade — não dá pra fazer com
grep/sed sem risco real de corromper o arquivo).

Uso: install_merge.py TARGET_FILE SOURCE_FILE SOURCE_SHAPE TARGET_SHAPE OUTPUT_FILE
  SHAPE em {flat, nested} — nested = eventos dentro de "hooks".

Dedup + ordenação IDÊNTICA ao "unique" do jq (chave = JSON canônico do
item), pra dar o mesmo resultado nas duas engines.
"""
import json
import sys


def dedup_sorted(items):
    by_key = {}
    for item in items:
        by_key[json.dumps(item, sort_keys=True)] = item
    return [by_key[k] for k in sorted(by_key.keys())]


def merge_events(target_events, source_events):
    for event, entries in source_events.items():
        combined = target_events.get(event, []) + entries
        target_events[event] = dedup_sorted(combined)
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
