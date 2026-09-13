# WAF com Application Load Balancer — Proteção contra Path Traversal / LFI

Laboratório educacional que demonstra, de forma prática e controlada, a diferença entre uma aplicação **SEM AWS WAF** e uma aplicação **COM AWS WAF**, usando **Path Traversal / Local File Inclusion (LFI)** como teste principal.

> Segundo projeto da série de laboratórios sobre AWS WAF.

![Descrição da imagem](<imagens/imagem%20(1).png>)
---

## Objetivo

Publicar **dois endpoints** que apontam para a **mesma aplicação** (Nginx em uma EC2 Ubuntu, atrás de um Application Load Balancer):

- **SEM WAF** — uma requisição com padrão de Path Traversal atravessa o ALB e **chega ao Nginx**.
- **COM WAF** — a mesma requisição é **bloqueada com HTTP 403** antes de chegar à aplicação.

O ALB COM WAF tem **duas proteções**:

1. **Path Traversal** (`<REGRA_PATH_TRAVERSAL>`) — bloqueia o padrão `../` na query string.
2. **CAPTCHA por país** (`<REGRA_CAPTCHA>`) — o site só é acessado **direto a partir do Brasil**; requisições de **fora do Brasil** recebem um **CAPTCHA** e só entram após resolvê-lo (evita acesso automatizado/fora do país). O teste dessa regra é feito **pelo navegador**.

A principal evidência do laboratório é o **`access.log` do Nginx**: SEM WAF a requisição aparece no log; COM WAF ela é bloqueada e **não** aparece no log.

![Descrição da imagem](<imagens/imagem%20(3).png>)

### O que este laboratório NÃO faz

- Não explora arquivos reais nem lê `/etc/passwd` ou qualquer arquivo do sistema.
- Não altera arquivos do sistema.
- Não cria shell, execução remota, DDoS ou stress test.
- Não cria nenhum endpoint vulnerável — o parâmetro `?file=...` é ignorado pela aplicação.
- Não usa Bot Control, Fraud Control, Marketplace Rules ou Managed Rule Groups desnecessários.

---

## O que é Path Traversal (contexto do teste)

**Path Traversal** (directory traversal) é uma técnica que tenta usar sequências como `../` para navegar para diretórios fora do local esperado pela aplicação, buscando alcançar arquivos do sistema.

Neste laboratório a sequência é enviada **apenas como parâmetro HTTP**, para testar a inspeção do WAF:

```
?file=../../etc/passwd
```

O Nginx **não precisa retornar o arquivo**. O objetivo é apenas comparar se a requisição chega ao servidor (SEM WAF) ou é bloqueada antes (COM WAF). Também é possível testar a variação com URL encoding: `%2e%2e%2f`.

---

## Serviços AWS utilizados

| Serviço | Papel no laboratório |
|---|---|
| Amazon Route 53 | DNS dos subdomínios do laboratório |
| AWS Certificate Manager (ACM) | Certificado TLS na região do ALB |
| AWS WAF | 1 Web ACL **regional** (`<WEB_ACL>`) + 2 regras (`<REGRA_PATH_TRAVERSAL>` e `<REGRA_CAPTCHA>`) |
| Application Load Balancer | Dois ALBs (um sem WAF, um com WAF) |
| Target Group | Agrupa a EC2 como destino, com health check em `/health` |
| Amazon EC2 (Ubuntu) | Instância que roda a aplicação |
| Nginx | Servidor web que serve o site e o `/health` |
| AWS Systems Manager | Administração da EC2 via Session Manager (sem SSH aberto) |
| Amazon CloudWatch | Métricas do WAF e do ALB |

---

![Descrição da imagem](<imagens/imagem%20(2).png>)

## Estrutura do projeto

```
projeto/
├── scripts/
│   └── install-nginx.sh (instala o Nginx e publica o site completo: index.html, style.css e o endpoint /health na EC2 Ubuntu)
│
├── tests/
│   ├── test-path-traversal.py   (teste controlado em Python)
│   └── test-path-traversal.ps1  (teste controlado em PowerShell)
│
├── README.md           (este arquivo — explicação do projeto)
├── ARQUITETURA.md      (arquitetura, VPC, security groups e como funciona)
└── IMPLANTACAO.md      (passo a passo completo pelo Console AWS, incluindo testes)
```

> O conteúdo do site (`index.html`, `style.css`) e o endpoint `/health` são **gerados pelo próprio `scripts/install-nginx.sh`** no momento da instalação na EC2 — não há mais uma pasta `web/` no repositório.

---

## Como usar

1. Leia a **arquitetura** em [ARQUITETURA.md](ARQUITETURA.md) para entender o fluxo, a VPC e os security groups.
2. Siga o **passo a passo pelo Console** em [IMPLANTACAO.md](IMPLANTACAO.md) — inclui VPC, EC2/Nginx via SSM, ALB, Target Group, Health Check, ACM, Route 53, WAF, **testes** (Etapa 11) e a exclusão ao final.
3. Na **Etapa 11 (Testes)** do [IMPLANTACAO.md](IMPLANTACAO.md) você valida o WAF pelo navegador e pelos scripts, com **onde comprovar cada ataque** (Sampled requests, CloudWatch e `access.log`).

### Scripts de teste

Python:

```bash
python tests/test-path-traversal.py --sem-waf https://<SUBDOMINIO_SEM_WAF> --com-waf https://<SUBDOMINIO_COM_WAF>
```

PowerShell:

```powershell
.\tests\test-path-traversal.ps1 -UrlSemWaf "https://<SUBDOMINIO_SEM_WAF>" -UrlComWaf "https://<SUBDOMINIO_COM_WAF>"
```

Saída esperada:

```
===========================================
AWS WAF LAB 02 - PATH TRAVERSAL
===========================================

SEM WAF
  Normal...................... 200
  Path Traversal.............. chegou ao servidor (404)

COM WAF
  Normal...................... 200
  Path Traversal.............. 403 BLOCKED

===========================================
```

> No endpoint SEM WAF, o código pode ser 200 ou 404 — o importante é que **chegou ao servidor**. COM WAF deve ser **403**.

---

## Resultado esperado

| Teste | SEM WAF | COM WAF |
|---|---|---|
| Normal (do Brasil) | Chega ao Nginx | Chega ao Nginx |
| Path Traversal | Chega ao Nginx | 403 WAF |
| Acesso ao site de fora do Brasil (navegador) | Chega ao Nginx | CAPTCHA → só entra após resolver |
| Health Check | Healthy | Healthy |

---

## Custos (leia antes de começar)

O **AWS WAF não possui gratuidade permanente**, e além dele este lab usa recursos que **cobram por hora enquanto existirem**, principalmente:

- **Application Load Balancer** (2 ALBs) — custo por hora + LCU.
- **EC2** — custo por hora da instância (use uma instância pequena; pare/termine ao fim).
- **AWS WAF** — Web ACL + regra + requisições.

ACM é gratuito; Route 53 cobra pela zona hospedada; CloudWatch tem uso mínimo. Este lab evita recursos premium (1 Web ACL + 2 regras: path traversal e CAPTCHA por país + poucas requisições). **Exclua tudo ao concluir** — o passo a passo de exclusão está no final de [IMPLANTACAO.md](IMPLANTACAO.md).

---

## Uso responsável

Execute os testes **somente** contra a sua própria infraestrutura de laboratório (`<SUBDOMINIO_SEM_WAF>` e `<SUBDOMINIO_COM_WAF>`). Não execute ataques contra terceiros e não gere flood, stress test ou DDoS.
