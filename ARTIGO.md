# Protegendo aplicações na AWS: bloqueando Path Traversal e restringindo acesso por país com AWS WAF + Application Load Balancer

> O laboratório **AWS WAF Security Lab — Projeto 02**, um estudo prático de como o AWS WAF protege aplicações web quando associado a um Application Load Balancer (ALB).

---

![Descrição da imagem](<imagens/imagem%20(1).png>)

## Introdução

Toda aplicação exposta na internet recebe, mais cedo ou mais tarde, requisições maliciosas. Uma das técnicas mais antigas e ainda comuns é o **Path Traversal** (também chamado de *directory traversal* ou, quando leva à leitura de arquivos, **Local File Inclusion / LFI**), em que o atacante usa sequências como `../` para tentar escapar do diretório da aplicação e alcançar arquivos do sistema, como `/etc/passwd`.

A pergunta que este laboratório responde na prática é simples: **qual a diferença real, medível, entre uma aplicação com AWS WAF e uma sem AWS WAF?**

Para responder isso sem achismo, o projeto publica **dois endpoints que apontam para exatamente a mesma aplicação** (um Nginx numa EC2 Ubuntu). A única variável entre eles é a presença de uma **Web ACL do AWS WAF**. Assim dá para comparar lado a lado o comportamento e comprovar cada resultado com evidências concretas (logs, Sampled requests e métricas do CloudWatch).

---

## O problema em uma frase

Sem uma camada de inspeção, uma requisição com `?file=../../etc/passwd` atravessa o balanceador e chega ao servidor de aplicação. Mesmo que a aplicação não seja vulnerável, essa requisição **é processada e registrada** — e em uma aplicação que realmente manipule caminhos de arquivo, isso poderia significar vazamento de dados.

O objetivo do WAF é **barrar esse padrão antes que ele chegue à aplicação**.

---

## Visão geral da solução

O laboratório monta dois caminhos paralelos:

- **`<SUBDOMINIO_SEM_WAF>`** → ALB **sem** Web ACL → EC2/Nginx
- **`<SUBDOMINIO_COM_WAF>`** → ALB **com** Web ACL → EC2/Nginx

Os dois ALBs registram a **mesma instância EC2** nos seus Target Groups. Isso é intencional: isolar o WAF como a única diferença entre os endpoints.

![Descrição da imagem](<imagens/imagem%20(3).png>)


```
                              INTERNET
                                 |
                              Route 53
                 +---------------+---------------+
                 v                               v
     <SUBDOMINIO_SEM_WAF>            <SUBDOMINIO_COM_WAF>
                 |                               |
                 v                               v
            ALB SEM WAF                     ALB COM WAF
                 |                               |
                 |                            AWS WAF
                 |                               |
                 v                               v
           Target Group                    Target Group
                 +---------------+---------------+
                                 v
                              EC2 (Ubuntu + Nginx)
                                 |
                             index.html + /health
```

---

## As duas proteções do WAF

O ALB COM WAF usa uma única Web ACL **regional** (`<WEB_ACL>`) com **duas regras**, cada uma demonstrando um tipo diferente de defesa.

### 1. Bloqueio de Path Traversal — `<REGRA_PATH_TRAVERSAL>`

- **Ação:** `BLOCK` (retorna HTTP 403).
- **O que inspeciona:** todos os parâmetros de consulta (a query string).
- **Como detecta:** correspondência do tipo *contém a string* `../`.
- **Transformação de texto:** **URL decode**, para também capturar a forma codificada `%2e%2e%2f`.

Essa é a defesa por **inspeção de conteúdo**: o WAF olha o que vem na requisição e decide bloquear.

![Descrição da imagem](<imagens/imagem%20(35).png>)

### 2. CAPTCHA por país — `<REGRA_CAPTCHA>`

- **Ação:** `CAPTCHA`.
- **Statement:** correspondência geográfica com **Negate** ativo → a regra vale quando o país de origem **não** é o Brasil.
- **Efeito:** quem acessa do Brasil entra direto; quem acessa de fora recebe um desafio de CAPTCHA e só passa depois de resolvê-lo.

Essa é a defesa por **origem geográfica**, útil para reduzir acesso automatizado e tráfego de fora do público-alvo. Como o CAPTCHA é uma página interativa que exige JavaScript, ela só é resolvida em **navegadores** — scripts recebem HTTP 405.

### Ordem de avaliação importa

A regra de Path Traversal tem **prioridade mais alta** (é avaliada primeiro). O resultado combinado fica:

| Origem | Requisição | Resultado |
|---|---|---|
| Fora do Brasil | com `../` | **403** (Block vence) |
| Fora do Brasil | sem `../` | **CAPTCHA** |
| Do Brasil | sem `../` | passa direto |
| Do Brasil | com `../` | **403** (Block) |

![Descrição da imagem](<imagens/imagem%20(23).png>)
![Descrição da imagem](<imagens/imagem%20(25).png>)

---

## Arquitetura e componentes AWS

| Serviço | Papel no laboratório |
|---|---|
| **Route 53** | DNS dos dois subdomínios (registros Alias para os ALBs) |
| **ACM** | Certificado TLS público, na **mesma região do ALB**, validado por DNS |
| **AWS WAF** | Web ACL regional com as duas regras descritas acima |
| **Application Load Balancer** | Dois ALBs (um sem WAF, um com WAF) |
| **Target Group** | Agrupa a EC2; health check em `/health` esperando HTTP 200 |
| **Amazon EC2 (Ubuntu)** | Instância que roda a aplicação |
| **Nginx** | Serve o site e o endpoint `/health` |
| **Systems Manager** | Administração via Session Manager, sem abrir SSH |
| **CloudWatch** | Métricas do WAF (`Allowed/BlockedRequests`) e do ALB |

![Descrição da imagem](<imagens/imagem%20(2).png>)

### Decisões de projeto que valem destacar

- **Mesma EC2 nos dois caminhos:** garante que o WAF seja a única variável do experimento.
- **Web ACL regional (não CloudFront):** obrigatório para associar a um ALB. Uma Web ACL de escopo CloudFront não pode ser associada a um ALB.
- **EC2 acessível apenas pelo Security Group do ALB:** a aplicação nunca fica exposta diretamente à internet na porta 80.
- **SSM Session Manager no lugar de SSH:** a porta 22 permanece fechada, reduzindo a superfície de ataque.
- **HTTP → redirect 301 → HTTPS:** os listeners do ALB forçam a conexão segura.

---

## Segurança de rede (Security Groups)

O desenho segue o princípio do menor privilégio na camada de rede:

- **SG do ALB:** libera inbound 80 e 443 de `0.0.0.0/0` (é ele que fica público).
- **SG da EC2:** libera inbound 80 **apenas com origem no SG do ALB** — ou seja, só o balanceador conversa com o Nginx.

Isso significa que ninguém alcança o Nginx diretamente pela internet; todo tráfego passa obrigatoriamente pelo ALB (e, no caminho protegido, pelo WAF).

---

## A aplicação é intencionalmente inofensiva

Um ponto importante para deixar claro: **este laboratório não cria nenhuma vulnerabilidade real**.

- Não existe endpoint vulnerável — o parâmetro `?file=...` é simplesmente ignorado pela aplicação.
- Não há leitura de `/etc/passwd` nem de qualquer arquivo do sistema.
- Não há execução remota, shell, DDoS ou stress test.

A sequência `../` é enviada **apenas como parâmetro HTTP** para testar a inspeção do WAF. O objetivo não é explorar nada, e sim **comparar se a requisição chega (ou não) ao servidor**.

O site em si é uma página estática publicada pelo script `install-nginx.sh`, que instala o Nginx, gera o `index.html`, o `style.css` e configura o endpoint `/health` (que responde `{"status": "healthy"}` com HTTP 200 para o health check do Target Group).

---

![Descrição da imagem](<imagens/imagem%20(33).png>)

## Como o resultado é comprovado

O grande diferencial didático do laboratório é que **cada teste tem uma evidência associada**. Não basta ver um 403 na tela — dá para rastrear onde aquilo ficou registrado.

As três fontes de evidência são:

1. **`access.log` do Nginx** (visto via SSM): mostra se a requisição chegou ao servidor.
2. **Sampled requests do WAF**: mostra a URI, a ação (Allow / Block / CAPTCHA), a regra que correspondeu e o país de origem.
3. **Métricas do CloudWatch** (`AWS/WAFV2` e `AWS/ApplicationELB`): `BlockedRequests`, `AllowedRequests`, `RequestCount`, `HTTPCode_ELB_4XX_Count`.

### A demonstração mais clara

Rodar dois testes em sequência olhando o `tail -f` do `access.log`:

- **SEM WAF**, `GET /?file=../../etc/passwd` → a linha **aparece** no log (a requisição chegou).
- **COM WAF**, a mesma requisição → a linha **não aparece** no log (foi barrada no ALB, antes do Nginx) e surge nos Sampled requests com ação **BLOCK**.

Essa ausência no log é a prova visual mais direta de que o WAF fez seu trabalho.

![Descrição da imagem](<imagens/imagem%20(14).png>)

---

## Resultados esperados

| Teste | SEM WAF | COM WAF |
|---|---|---|
| Acesso normal (do Brasil) | Chega ao Nginx (200) | Chega ao Nginx (200) |
| Path Traversal | Chega ao Nginx (200/404) | **403** bloqueado pelo WAF |
| Acesso de fora do Brasil (navegador) | Chega ao Nginx | **CAPTCHA** → só entra após resolver |
| Health Check | Healthy | Healthy |

Os scripts de teste (`test-path-traversal.py` e `test-path-traversal.ps1`) automatizam as quatro requisições principais e mostram o resultado lado a lado. Eles usam apenas a biblioteca padrão, então não exigem instalação de dependências.

---

## Aprendizados

Alguns pontos que este laboratório deixa evidentes:

- **WAF é uma camada, não uma bala de prata.** Ele bloqueia padrões conhecidos antes da aplicação, mas o desenho de rede (Security Groups, EC2 privada ao ALB, SSM no lugar de SSH) continua sendo fundamental.
- **Escopo do WAF importa.** Para ALB, a Web ACL precisa ser **regional** e estar na mesma região do balanceador. Errar isso é uma das causas mais comuns de "o WAF não aparece para associar".
- **A ação da regra define o comportamento.** Uma regra de geo pode `BLOCK` ou `CAPTCHA` — trocar a ação muda completamente a experiência do usuário legítimo.
- **CAPTCHA é para humanos.** Scripts não resolvem o desafio e recebem HTTP 405. Testar essa regra exige um navegador e um IP fora do Brasil (via VPN, por exemplo).
- **Prioridade das regras é uma decisão de segurança.** Colocar o Block do Path Traversal acima do CAPTCHA garante que um ataque seja barrado imediatamente, sem sequer oferecer o desafio.

---

## Custos e uso responsável

O AWS WAF **não tem gratuidade permanente**, e o laboratório usa recursos que cobram por hora enquanto existirem (principalmente os dois ALBs e a EC2). O projeto foi mantido enxuto de propósito — **1 Web ACL + 2 regras próprias**, sem grupos de regras gerenciadas — para reduzir custo e manter o foco didático.

Por isso, a regra de ouro: **exclua todos os recursos ao concluir** (o passo a passo de exclusão está no `IMPLANTACAO.md`).

E, claro, os testes devem ser executados **somente contra a sua própria infraestrutura de laboratório**. Nada de apontar para terceiros ou gerar flood.

---

## Para se aprofundar

- **[README.md](README.md)** — visão geral do projeto.
- **[ARQUITETURA.md](ARQUITETURA.md)** — detalhes da VPC, security groups e o fluxo completo de cada requisição.
- **[IMPLANTACAO.md](IMPLANTACAO.md)** — passo a passo completo pelo Console AWS, incluindo os testes (Etapa 11) e a exclusão dos recursos.

---

*Segundo projeto de uma série de laboratórios educacionais sobre AWS WAF.*
