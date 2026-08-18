#!/usr/bin/env python3
"""
Analisador de PR - Analisa a complexidade do PR e sugere uma abordagem de revisão.

Uso:
    python analisador-pr.py [--diff-file ARQUIVO] [--stats]

    Ou direcione o diff via pipe:
    git diff main...HEAD | python analisador-pr.py
"""

import os
import sys
import re
import argparse
from collections import defaultdict
from dataclasses import dataclass
from typing import List, Dict, Optional

RISK_NO_TESTS = "NO_TEST_CHANGES"


@dataclass
class FileStats:
    """Estatísticas de um único arquivo."""
    filename: str
    additions: int = 0
    deletions: int = 0
    is_test: bool = False
    is_config: bool = False
    language: str = "unknown"


@dataclass
class PRAnalysis:
    """Resultado completo da análise do PR."""
    total_files: int
    total_additions: int
    total_deletions: int
    files: List[FileStats]
    complexity_score: float
    size_category: str
    estimated_review_time: int
    risk_factors: List[str]
    suggestions: List[str]


def detect_language(filename: str) -> str:
    """Detecta a linguagem de programação a partir do nome do arquivo."""
    _, ext = os.path.splitext(filename)
    extensions = {
        '.py': 'Python',
        '.js': 'JavaScript',
        '.ts': 'TypeScript',
        '.go': 'Go',
        '.java': 'Java',
        '.cs': 'C#',
        '.sql': 'SQL',
        '.md': 'Markdown',
        '.json': 'JSON',
        '.yaml': 'YAML',
        '.yml': 'YAML',
        '.toml': 'TOML',
        '.css': 'CSS',
        '.scss': 'SCSS',
        '.less': 'Less',
        '.html': 'HTML',
    }
    return extensions.get(ext.lower(), 'unknown')


def is_test_file(filename: str) -> bool:
    """Verifica se o arquivo é um arquivo de teste."""
    test_patterns = [
        r'test_.*\.py$',
        r'.*_test\.py$',
        r'.*\.test\.(js|ts)$',
        r'.*\.spec\.(js|ts)$',
        r'tests?/',
        r'__tests__/',
    ]
    return any(re.search(p, filename) for p in test_patterns)


def is_config_file(filename: str) -> bool:
    """Verifica se o arquivo é um arquivo de configuração."""
    config_patterns = [
        r'\.env',
        r'config\.',
        r'\.json$',
        r'\.yaml$',
        r'\.yml$',
        r'\.toml$',
        r'package\.json$',
        r'tsconfig\.json$',
    ]
    return any(re.search(p, filename) for p in config_patterns)


def parse_diff(diff_content: str) -> List[FileStats]:
    """Faz o parsing da saída do git diff e extrai as estatísticas dos arquivos."""
    files = []
    current_file = None

    for line in diff_content.split('\n'):
        # Cabeçalho de um novo arquivo
        if line.startswith('diff --git'):
            if current_file:
                files.append(current_file)
            # "diff --git a/<path> b/<path>" — captura o lado b/ usando uma
            # referência retroativa (backreference) para que um "b/" literal
            # dentro de caminhos como lib/, web/ ou db/ não seja confundido
            # com o prefixo. Renomeações têm caminhos diferentes, então
            # usamos o lado b/ após o espaço separador como fallback.
            match = re.match(r'diff --git a/(.+?) b/\1', line)
            if not match:
                match = re.search(r' b/(.+)$', line)
            if match:
                filename = match.group(1)
                current_file = FileStats(
                    filename=filename,
                    language=detect_language(filename),
                    is_test=is_test_file(filename),
                    is_config=is_config_file(filename),
                )
            else:
                current_file = None
        elif current_file:
            if line.startswith('+') and not line.startswith('+++'):
                current_file.additions += 1
            elif line.startswith('-') and not line.startswith('---'):
                current_file.deletions += 1

    if current_file:
        files.append(current_file)

    return files


def calculate_complexity(files: List[FileStats]) -> float:
    """Calcula a pontuação de complexidade (escala de 0 a 1)."""
    if not files:
        return 0.0

    total_changes = sum(f.additions + f.deletions for f in files)

    # Complexidade base a partir do tamanho
    size_factor = min(total_changes / 1000, 1.0)

    # Fator referente à quantidade de arquivos
    file_factor = min(len(files) / 20, 1.0)

    # Fator referente à proporção de código que não é teste
    test_lines = sum(f.additions + f.deletions for f in files if f.is_test)
    non_test_ratio = 1 - (test_lines / max(total_changes, 1))

    # Fator referente à diversidade de linguagens
    languages = set(f.language for f in files if f.language != 'unknown')
    lang_factor = min(len(languages) / 5, 1.0)

    complexity = (
        size_factor * 0.4 +
        file_factor * 0.2 +
        non_test_ratio * 0.2 +
        lang_factor * 0.2
    )

    return round(complexity, 2)


def categorize_size(total_changes: int) -> str:
    """Categoriza o tamanho do PR."""
    if total_changes < 50:
        return "XS (Extra Pequeno)"
    elif total_changes < 200:
        return "S (Pequeno)"
    elif total_changes < 400:
        return "M (Médio)"
    elif total_changes < 800:
        return "L (Grande)"
    else:
        return "XL (Extra Grande) - Considere dividir"


def estimate_review_time(files: List[FileStats], complexity: float) -> int:
    """Estima o tempo de revisão em minutos."""
    total_changes = sum(f.additions + f.deletions for f in files)

    # Tempo base: ~1 minuto a cada 20 linhas
    base_time = total_changes / 20

    # Ajusta de acordo com a complexidade
    adjusted_time = base_time * (1 + complexity)

    # Mínimo de 5 minutos, máximo de 120 minutos
    return max(5, min(120, int(adjusted_time)))


def identify_risk_factors(files: List[FileStats]) -> List[str]:
    """Identifica possíveis fatores de risco no PR."""
    risks = []

    total_changes = sum(f.additions + f.deletions for f in files)
    test_changes = sum(f.additions + f.deletions for f in files if f.is_test)

    if total_changes > 400:
        risks.append("PR grande (>400 linhas) - mais difícil de revisar com profundidade")

    if test_changes == 0 and total_changes > 50:
        risks.append(f"{RISK_NO_TESTS}: Nenhuma alteração de teste - verifique a cobertura de testes")

    if total_changes > 100 and test_changes / max(total_changes, 1) < 0.2:
        risks.append("Baixa proporção de testes (<20%) - considere adicionar mais testes")

    # Arquivos sensíveis à segurança
    security_patterns = ['.env', 'auth', 'security', 'password', 'token', 'secret']
    for f in files:
        if any(p in f.filename.lower() for p in security_patterns):
            risks.append(f"Arquivo sensível à segurança: {f.filename}")
            break

    # Mudanças de banco de dados
    for f in files:
        if 'migration' in f.filename.lower() or f.language == 'SQL':
            risks.append("Mudanças de banco de dados detectadas - revise com cuidado")
            break

    # Mudanças de configuração
    config_files = [f for f in files if f.is_config]
    if config_files:
        risks.append(f"Mudanças de configuração em {len(config_files)} arquivo(s)")

    return risks


def generate_suggestions(files: List[FileStats], complexity: float, risks: List[str]) -> List[str]:
    """Gera sugestões de revisão."""
    suggestions = []

    total_changes = sum(f.additions + f.deletions for f in files)

    if total_changes > 800:
        suggestions.append("Considere dividir este PR em mudanças menores e mais focadas")

    if complexity > 0.7:
        suggestions.append("Alta complexidade - reserve tempo extra para a revisão")
        suggestions.append("Considere fazer pair review para as seções críticas")

    if any(RISK_NO_TESTS in r for r in risks):
        suggestions.append("Solicite a adição de testes antes de aprovar")

    # Sugestões específicas por linguagem
    languages = set(f.language for f in files)
    if 'TypeScript' in languages:
        suggestions.append("Verifique o uso correto de tipos (evite 'any')")
    if 'SQL' in languages:
        suggestions.append("Revise quanto a injeção de SQL e performance das consultas")

    if not suggestions:
        suggestions.append("O processo padrão de revisão deve ser suficiente")

    return suggestions


def analyze_pr(diff_content: str) -> PRAnalysis:
    """Executa a análise completa do PR."""
    files = parse_diff(diff_content)

    total_additions = sum(f.additions for f in files)
    total_deletions = sum(f.deletions for f in files)
    total_changes = total_additions + total_deletions

    complexity = calculate_complexity(files)
    risks = identify_risk_factors(files)
    suggestions = generate_suggestions(files, complexity, risks)

    return PRAnalysis(
        total_files=len(files),
        total_additions=total_additions,
        total_deletions=total_deletions,
        files=files,
        complexity_score=complexity,
        size_category=categorize_size(total_changes),
        estimated_review_time=estimate_review_time(files, complexity),
        risk_factors=risks,
        suggestions=suggestions,
    )


def print_analysis(analysis: PRAnalysis, show_files: bool = False):
    """Imprime os resultados da análise."""
    print("\n" + "=" * 60)
    print("RELATÓRIO DE ANÁLISE DO PR")
    print("=" * 60)

    print(f"\nRESUMO")
    print(f"   Arquivos alterados: {analysis.total_files}")
    print(f"   Adições: +{analysis.total_additions}")
    print(f"   Remoções: -{analysis.total_deletions}")
    print(f"   Total de mudanças: {analysis.total_additions + analysis.total_deletions}")

    print(f"\nTAMANHO: {analysis.size_category}")
    print(f"   Pontuação de complexidade: {analysis.complexity_score}/1.0")
    print(f"   Tempo estimado de revisão: ~{analysis.estimated_review_time} minutos")

    if analysis.risk_factors:
        print(f"\nFATORES DE RISCO:")
        for risk in analysis.risk_factors:
            print(f"   • {risk}")

    print(f"\nSUGESTÕES:")
    for suggestion in analysis.suggestions:
        print(f"   • {suggestion}")

    if show_files:
        print(f"\nARQUIVOS:")
        # Agrupa por linguagem
        by_lang: Dict[str, List[FileStats]] = defaultdict(list)
        for f in analysis.files:
            by_lang[f.language].append(f)

        for lang, lang_files in sorted(by_lang.items()):
            print(f"\n   [{lang}]")
            for f in lang_files:
                tag = "[teste] " if f.is_test else "[config] " if f.is_config else ""
                print(f"   {tag}{f.filename} (+{f.additions}/-{f.deletions})")

    print("\n" + "=" * 60)


def main():
    parser = argparse.ArgumentParser(description='Analisa a complexidade do PR')
    parser.add_argument('--diff-file', '-f', help='Caminho para o arquivo de diff')
    parser.add_argument('--stats', '-s', action='store_true', help='Mostra detalhes dos arquivos')
    args = parser.parse_args()

    # Lê o diff a partir de um arquivo ou da stdin
    try:
        if args.diff_file:
            with open(args.diff_file, 'r', encoding='utf-8', errors='replace') as f:
                diff_content = f.read()
        elif not sys.stdin.isatty():
            diff_content = sys.stdin.buffer.read().decode('utf-8', errors='replace')
        else:
            print("Uso: git diff main...HEAD | python analisador-pr.py")
            print("     python analisador-pr.py -f diff.txt")
            sys.exit(1)
    except OSError as e:
        print(f"Erro ao ler a entrada do diff: {e}", file=sys.stderr)
        sys.exit(1)

    if not diff_content.strip():
        print("Nenhum conteúdo de diff fornecido")
        sys.exit(1)

    analysis = analyze_pr(diff_content)
    print_analysis(analysis, show_files=args.stats)


if __name__ == '__main__':
    main()
