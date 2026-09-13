# Arquitetura

Este documento descreve a arquitetura do laboratório, a rede (VPC), os security groups e **como tudo funciona**.

---

## Visão geral

O laboratório expõe **dois subdomínios**, cada um com seu **Application Load Balancer**, apontando para a **mesma EC2** (Ubuntu + Nginx) através de Target Groups. A única diferença entre os dois caminhos é que apenas o ALB COM WAF tem uma Web ACL regional associada.

```
                              INTERNET
                                 |
                              Route 53
                                 |
                 +---------------+---------------+
                 |                               |
                 v                               v
       <SUBDOMINIO_SEM_WAF>         <SUBDOMINIO_COM_WAF>
                 |                               |
                 v                               v
            ALB SEM WAF                     ALB COM WAF
                 |                               |
                 |                            AWS WAF
                 |                               |
                 v                               v
           Target Group                    Target Group
                 |                               |
                 +---------------+---------------+
                                 |
                                 v
                              EC2
                                 |
                              Ubuntu
                                 |
                              Nginx
                                 |
                            index.html
```

> Os dois Target Groups registram a **mesma instância EC2**. Assim, a única variável entre os endpoints é a presença do WAF.

---

## Componentes

| Componente | Função |
|---|---|
| **Route 53** | Zona hospedada com 2 registros Alias apontando para os dois ALBs. |
| **ACM** | Certificado TLS público na **mesma região do ALB**, validado por DNS. Habilita HTTPS. |
| **ALB SEM WAF** | Application Load Balancer sem Web ACL. |
| **ALB COM WAF** | Application Load Balancer com a Web ACL `<WEB_ACL>` associada. |
| **AWS WAF** | Web ACL **regional** com 2 regras: `<REGRA_PATH_TRAVERSAL>` (detecta `../` e `%2e%2e%2f`, ação Block) e `<REGRA_CAPTCHA>` (geo match, exige CAPTCHA fora do BR). |
| **Target Group(s)** | Agrupam a EC2 como destino; health check em `/health` esperando HTTP 200. |
| **EC2 (Ubuntu)** | Instância que roda o Nginx e serve o site. |
| **Nginx** | Servidor web; responde `/` (site) e `/health` (JSON). |
| **Systems Manager** | Session Manager para administrar a EC2 sem abrir SSH. |
| **CloudWatch** | Métricas do WAF (`Allowed/BlockedRequests`) e do ALB (`RequestCount`, `HTTPCode_ELB_4XX_Count`, `Healthy/UnHealthyHostCount`). |

---

## Rede (VPC)

Para o laboratório:

- **1 VPC** dedicada (`<VPC_CIDR>`, ex.: `10.0.0.0/16`).
- **1 Internet Gateway** anexado à VPC.
- **Pelo menos 2 subnets públicas** em **AZs diferentes** (requisito do ALB, que precisa de no mínimo duas zonas de disponibilidade).
- **Route Table** com rota padrão (`0.0.0.0/0`) para o Internet Gateway, associada às subnets.
- A **EC2** pode ficar em uma das subnets. Para administração, usa-se o **SSM Session Manager** (não é necessário IP público com SSH aberto).

```
VPC <VPC_CIDR>
├── Internet Gateway
├── Route Table pública (0.0.0.0/0 -> IGW)
├── Subnet pública A (AZ 1)  -> ALBs + EC2
└── Subnet pública B (AZ 2)  -> ALBs (2ª AZ exigida)
```

### Arquitetura recomendada em produção

Para um ambiente real (fora do escopo simplificado deste lab), o recomendado seria:

- ALB em **subnets públicas** (2+ AZs).
- EC2 (ou Auto Scaling Group) em **subnets privadas**, sem IP público.
- **NAT Gateway** para saída de internet das instâncias privadas.
- SSM Session Manager para administração (sem bastion/SSH).
- Vários alvos em múltiplas AZs para alta disponibilidade.

Neste laboratório, simplificamos para reduzir custo e complexidade, mantendo a EC2 acessível apenas via ALB e SSM.

---

## Security Groups

### SG do ALB (`<SG_ALB>`)

| Direção | Porta | Origem | Motivo |
|---|---|---|---|
| Inbound | 80 | 0.0.0.0/0 | HTTP (redirecionado para HTTPS) |
| Inbound | 443 | 0.0.0.0/0 | HTTPS |
| Outbound | tudo | — | padrão |

### SG da EC2 (`<SG_EC2>`)

| Direção | Porta | Origem | Motivo |
|---|---|---|---|
| Inbound | 80 | **SG do ALB** (`<SG_ALB>`) | Só o ALB fala com o Nginx |
| Outbound | tudo | — | Necessário para SSM e updates |

> **Importante:** a porta HTTP da EC2 **não** é liberada diretamente para a Internet — apenas o Security Group do ALB pode alcançá-la. A administração é feita via **SSM Session Manager**, sem abrir a porta 22 (SSH).

---

## Como funciona o fluxo SEM WAF

```
Usuário
  ↓
Route 53   (resolve <SUBDOMINIO_SEM_WAF> para o ALB SEM WAF)
  ↓
ALB SEM WAF   (sem Web ACL)
  ↓
Target Group
  ↓
EC2 / Nginx
```

Como **não há Web ACL**, a requisição com `../` não é inspecionada pelo WAF e **chega ao Nginx**. O resultado pode ser `200`, `404` ou outro código — o que importa é que a requisição **aparece no `access.log`** do Nginx.

---

## Como funciona o fluxo COM WAF

```
Usuário
  ↓
Route 53   (resolve <SUBDOMINIO_COM_WAF> para o ALB COM WAF)
  ↓
AWS WAF   (Web ACL <WEB_ACL>)
  ↓
<REGRA_PATH_TRAVERSAL>  → contém ../ (ou %2e%2e%2f)? → BLOCK (403)
  ↓ (sem path traversal)
<REGRA_CAPTCHA>    → origem fora do BR? → CAPTCHA (405 p/ scripts)
  ↓ (origem no Brasil)
Encaminha ao Target Group → EC2 / Nginx
```

O AWS WAF é avaliado **no ALB, antes de encaminhar ao Target Group**. Se a requisição contém o padrão de Path Traversal, a regra `<REGRA_PATH_TRAVERSAL>` retorna **HTTP 403** e a requisição **não aparece no `access.log`** da EC2 — essa ausência é a principal evidência do laboratório. Se a origem está fora do Brasil (sem path traversal), a regra `<REGRA_CAPTCHA>` exige o desafio e a requisição só chega ao Nginx **depois** de resolvido.

---

## Como funciona a regra de Path Traversal

- **Web ACL:** regional (associada ao ALB, não ao CloudFront).
- **Regra:** `<REGRA_PATH_TRAVERSAL>`.
- **Detecção:** procura o padrão `../` (e a variação com URL encoding `%2e%2e%2f`) na **query string** e, se necessário, no **URI Path**.
- **Como implementar:** Byte Match Statement (contém a string `../`) ou um Regex Pattern Set simples. Aplicar transformação de texto **URL decode** para capturar a forma codificada.
- **Ação:** `BLOCK`.
- **Ação padrão da Web ACL:** `Allow`.

---

## Como funciona a regra de CAPTCHA por país (fora do Brasil)

- **Web ACL:** a mesma `<WEB_ACL>` (regional, associada ao `<ALB_COM_WAF>`).
- **Regra:** `<REGRA_CAPTCHA>`.
- **Statement:** Geographic match com **Negate statement** ativo → corresponde quando o país de origem **não** é o Brasil.
- **Configuração:** país = **Brazil (BR)**; IP usado = **Source IP address**.
- **Ação:** `CAPTCHA` (com tempo de imunidade, ex.: 300s).

O objetivo é **restringir o acesso ao site a partir do Brasil**: quem vem do Brasil entra direto; quem vem de fora recebe um **desafio de CAPTCHA** e só acessa após resolvê-lo. Isso ajuda a evitar acesso automatizado e de origens fora do país.

```
Origem no Brasil        →  regra NÃO corresponde  →  acesso direto ao site
Origem fora do Brasil   →  regra corresponde       →  CAPTCHA → site após resolver
```

> O CAPTCHA é resolvido apenas em **navegadores** (executam JavaScript). Clientes automatizados recebem **HTTP 405** com o corpo do desafio, sem passar.

---

## Ordem de avaliação das regras

Recomenda-se `<REGRA_PATH_TRAVERSAL>` com **prioridade mais alta** (avaliada primeiro): um ataque de path traversal deve ser **bloqueado** imediatamente, sem oferecer CAPTCHA. Efeitos combinados:

- Fora do Brasil **com** `../` → **403** (Block vence).
- Fora do Brasil **sem** `../` → **CAPTCHA**.
- Do Brasil **sem** `../` → passa direto.
- Do Brasil **com** `../` → **403** (Block).

---

## Health Check

- **Endpoint:** `/health`.
- **Resposta:** HTTP `200` com corpo JSON `{"status": "healthy"}`.
- **Target Group:** Health Check Path = `/health`, código de sucesso `200`.
- A instância precisa estar **Healthy** no Target Group antes de iniciar os testes.

---

## Decisões de projeto

- **Mesma EC2** para os dois caminhos: isola o WAF como única variável.
- **Web ACL regional**: exigido para associar a um ALB (diferente do escopo CloudFront do Lab 01).
- **SSM Session Manager** em vez de SSH: reduz superfície de ataque (porta 22 fechada).
- **EC2 acessível só pelo SG do ALB**: a aplicação nunca é exposta diretamente à Internet.
- **2 regras** (`<REGRA_PATH_TRAVERSAL>` + `<REGRA_CAPTCHA>`): uma demonstra bloqueio por inspeção de conteúdo, a outra demonstra CAPTCHA por origem geográfica, mantendo o custo baixo e o foco didático.
- **HTTP → Redirect → HTTPS**: configurado nos listeners do ALB.
