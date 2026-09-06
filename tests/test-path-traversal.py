#!/usr/bin/env python3
"""
AWS WAF Security Lab - Projeto 02 (Path Traversal)
Teste controlado de deteccao de Path Traversal / LFI pelo AWS WAF.

O script executa DUAS requisicoes contra cada endpoint:
  1. Requisicao normal          -> deve chegar ao Nginx (ex.: 200)
  2. Requisicao Path Traversal   -> SEM WAF: chega ao servidor | COM WAF: 403 (BLOCKED)

REGRAS DE USO:
  - Execute SOMENTE contra a sua propria infraestrutura de laboratorio.
  - Sem threads, sem flood, sem DDoS. Sao apenas 4 requisicoes no total.
  - O parametro ?file=../../etc/passwd e enviado apenas como texto; a aplicacao
    NAO le nenhum arquivo do sistema.

Uso:
  python test-path-traversal.py --sem-waf https://alb-sem-waf.dominio.com \
                                --com-waf https://alb-com-waf.dominio.com
"""

import argparse
import sys
import urllib.error
import urllib.parse
import urllib.request

# Padrao de Path Traversal usado somente contra os endpoints do laboratorio.
TRAVERSAL_PAYLOAD = "../../etc/passwd"
TIMEOUT = 15


def _build_url(base, value):
    base = base.rstrip("/")
    query = urllib.parse.urlencode({"file": value})
    return "{}/?{}".format(base, query)


def _do_request(url):
    """Executa uma unica requisicao GET e retorna o status HTTP (int) ou None."""
    req = urllib.request.Request(url, method="GET", headers={"User-Agent": "waf-lab-02-pt/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.getcode()
    except urllib.error.HTTPError as e:
        # 403 do WAF cai aqui - e um resultado esperado no endpoint COM WAF.
        # 404 tambem cai aqui e significa que a requisicao chegou ao Nginx.
        return e.code
    except Exception as e:
        print("  ! Erro ao acessar {}: {}".format(url, e))
        return None


def _fmt_normal(label, status):
    dots = "." * max(3, 28 - len(label))
    if status is None:
        return "  {}{}ERRO".format(label, dots)
    return "  {}{}{}".format(label, dots, status)


def _fmt_traversal(label, status):
    dots = "." * max(3, 28 - len(label))
    if status is None:
        return "  {}{}ERRO".format(label, dots)
    if status == 403:
        return "  {}{}403 BLOCKED".format(label, dots)
    # Qualquer outro codigo (200, 404, etc.) significa que chegou ao servidor.
    return "  {}{}chegou ao servidor ({})".format(label, dots, status)


def run_block(title, base_url):
    print(title)
    normal = _do_request(_build_url(base_url, "relatorio.txt"))
    traversal = _do_request(_build_url(base_url, TRAVERSAL_PAYLOAD))
    print(_fmt_normal("Normal", normal))
    print(_fmt_traversal("Path Traversal", traversal))
    print("")


def main():
    parser = argparse.ArgumentParser(description="Teste controlado de Path Traversal com AWS WAF (Lab 02).")
    parser.add_argument("--sem-waf", dest="sem_waf", required=True, help="URL do endpoint SEM WAF")
    parser.add_argument("--com-waf", dest="com_waf", required=True, help="URL do endpoint COM WAF")
    args = parser.parse_args()

    print("=" * 43)
    print("AWS WAF LAB 02 - PATH TRAVERSAL")
    print("=" * 43)
    print("")

    run_block("SEM WAF", args.sem_waf)
    run_block("COM WAF", args.com_waf)

    print("=" * 43)
    return 0


if __name__ == "__main__":
    sys.exit(main())
