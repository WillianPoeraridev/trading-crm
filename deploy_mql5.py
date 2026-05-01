"""
deploy_mql5.py
Copia os arquivos .mq5 do projeto para as pastas do MT5 e compila automaticamente.

USO:
  python deploy_mql5.py          # copia + compila
  python deploy_mql5.py --copy   # só copia, sem compilar
"""

import os
import sys
import shutil
import subprocess
import time
from pathlib import Path

# ── CONFIGURAÇÃO ──────────────────────────────────────────────────────────────

# Pasta raiz do projeto (ajuste se necessário)
PROJECT_ROOT = Path(r"C:\Users\luizp\Desktop\WillianPoerari\Projetos\trading-crm")

# Terminal MT5
TERMINAL_ROOT = Path(
    r"C:\Users\luizp\AppData\Roaming\MetaQuotes\Terminal"
    r"\930119AA53207C8778B41171FBFFB46F\MQL5"
)

# Executável do MetaEditor (compilador do MT5)
# Ajuste o caminho se o MT5 estiver instalado em local diferente
METAEDITOR = Path(
    r"C:\Program Files\MetaTrader 5\metaeditor64.exe"
)

# Mapeamento: origem → destino
COPY_JOBS = [
    {
        "name": "Services",
        "src": PROJECT_ROOT / "mql5" / "Services",
        "dst": TERMINAL_ROOT / "Services",
    },
    {
        "name": "Experts",
        "src": PROJECT_ROOT / "mql5" / "Experts",
        "dst": TERMINAL_ROOT / "Experts" / "Advisors",
    },
]

# ── HELPERS ───────────────────────────────────────────────────────────────────

GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
RESET  = "\033[0m"
BOLD   = "\033[1m"

def ok(msg):   print(f"{GREEN}  ✓ {msg}{RESET}")
def info(msg): print(f"{YELLOW}  → {msg}{RESET}")
def err(msg):  print(f"{RED}  ✗ {msg}{RESET}")
def title(msg):print(f"\n{BOLD}{msg}{RESET}")


def clear_and_copy(src: Path, dst: Path, name: str):
    """Apaga o conteúdo da pasta destino e copia todos os arquivos da origem."""
    title(f"[{name}]  {src}  →  {dst}")

    # Valida origem
    if not src.exists():
        err(f"Pasta de origem não encontrada: {src}")
        return False

    # Cria destino se não existir
    dst.mkdir(parents=True, exist_ok=True)

    # Apaga conteúdo existente
    deleted = 0
    for item in dst.iterdir():
        if item.is_file():
            item.unlink()
            deleted += 1
        elif item.is_dir():
            shutil.rmtree(item)
            deleted += 1
    if deleted:
        info(f"Removidos {deleted} item(s) de {dst.name}")

    # Copia arquivos
    copied = 0
    for item in src.iterdir():
        target = dst / item.name
        if item.is_file():
            shutil.copy2(item, target)
            ok(f"Copiado: {item.name}")
            copied += 1
        elif item.is_dir():
            shutil.copytree(item, target)
            ok(f"Copiado (pasta): {item.name}")
            copied += 1

    if copied == 0:
        info("Nenhum arquivo encontrado na origem.")
        return False

    print(f"  {BOLD}{copied} arquivo(s) copiado(s).{RESET}")
    return True


def compile_file(mq5_path: Path) -> bool:
    """Compila um arquivo .mq5 usando o MetaEditor em modo silencioso."""
    if not METAEDITOR.exists():
        err(f"MetaEditor não encontrado em: {METAEDITOR}")
        err("Ajuste a variável METAEDITOR no topo do script.")
        return False

    log_path = mq5_path.with_suffix(".log")

    cmd = [
        str(METAEDITOR),
        f"/compile:{mq5_path}",
        f"/log:{log_path}",
    ]

    info(f"Compilando: {mq5_path.name} ...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    # Lê o log gerado pelo MetaEditor
    errors = 0
    warnings = 0
    if log_path.exists():
        log_text = log_path.read_text(encoding="utf-16-le", errors="ignore")
        for line in log_text.splitlines():
            line = line.strip()
            if not line:
                continue
            if " error " in line.lower() or line.endswith("error(s)"):
                err(f"  {line}")
                errors += 1
            elif " warning " in line.lower():
                print(f"{YELLOW}    ⚠ {line}{RESET}")
                warnings += 1
            elif "information:" in line.lower() or "0 error" in line.lower():
                ok(f"  {line}")
        log_path.unlink(missing_ok=True)

    if errors == 0:
        ok(f"Compilação OK — {mq5_path.name}"
           + (f" ({warnings} warning(s))" if warnings else ""))
        return True
    else:
        err(f"Compilação FALHOU — {mq5_path.name} ({errors} erro(s))")
        return False


def find_mq5_files(directory: Path) -> list[Path]:
    """Retorna todos os .mq5 da pasta (não recursivo)."""
    return sorted(directory.glob("*.mq5"))


# ── MAIN ──────────────────────────────────────────────────────────────────────

def main():
    only_copy = "--copy" in sys.argv

    print(f"\n{BOLD}{'='*60}")
    print("  MQL5 Deploy Script")
    print(f"{'='*60}{RESET}")

    # 1. Copiar arquivos
    title("ETAPA 1 — Copiando arquivos")
    success_jobs = []
    for job in COPY_JOBS:
        ok_result = clear_and_copy(job["src"], job["dst"], job["name"])
        if ok_result:
            success_jobs.append(job)

    if not success_jobs:
        err("Nenhum arquivo foi copiado. Verifique os caminhos no script.")
        sys.exit(1)

    if only_copy:
        print(f"\n{GREEN}{BOLD}✓ Cópia concluída (sem compilação).{RESET}\n")
        sys.exit(0)

    # 2. Compilar
    title("ETAPA 2 — Compilando no MetaEditor")

    if not METAEDITOR.exists():
        # Tenta localizar o MetaEditor automaticamente
        candidates = [
            Path(r"C:\Program Files\MetaTrader 5\metaeditor64.exe"),
            Path(r"C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"),
            Path(r"C:\Program Files\MetaTrader 5 (Fusion Markets)\metaeditor64.exe"),
        ]
        found = next((p for p in candidates if p.exists()), None)
        if found:
            info(f"MetaEditor encontrado em: {found}")
            global METAEDITOR
            METAEDITOR = found
        else:
            err("MetaEditor não encontrado. Copiar os caminhos possíveis:")
            for c in candidates:
                print(f"    {c}")
            err("Ajuste a variável METAEDITOR no topo do script e execute novamente.")
            err("Para copiar sem compilar: python deploy_mql5.py --copy")
            sys.exit(1)

    total_ok = 0
    total_fail = 0

    for job in success_jobs:
        files = find_mq5_files(job["dst"])
        if not files:
            info(f"Nenhum .mq5 em {job['dst']}")
            continue
        for f in files:
            time.sleep(0.5)  # pequena pausa entre compilações
            if compile_file(f):
                total_ok += 1
            else:
                total_fail += 1

    # Resumo
    print(f"\n{BOLD}{'='*60}")
    if total_fail == 0:
        print(f"{GREEN}  ✓ Tudo certo! {total_ok} arquivo(s) compilado(s) com sucesso.{RESET}")
    else:
        print(f"{YELLOW}  ⚠ {total_ok} OK, {total_fail} com erro(s).{RESET}")
    print(f"{BOLD}{'='*60}{RESET}\n")

    sys.exit(0 if total_fail == 0 else 1)


if __name__ == "__main__":
    main()
