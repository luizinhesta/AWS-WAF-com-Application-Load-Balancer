# Implantação — Passo a Passo pelo Console AWS

Guia completo de implantação do laboratório **exclusivamente pelo Console AWS**, em português.

> Este guia usa **variáveis** (no formato `<VARIAVEL>`) no lugar de nomes reais de recursos, domínios e regiões, para que você não exponha informações do seu ambiente. Antes de começar, preencha a tabela de variáveis abaixo com os seus próprios valores e, ao seguir o passo a passo, substitua cada `<VARIAVEL>` pelo valor correspondente. **Toda a Etapa de WAF e o ACM devem ser criados na MESMA região do ALB** (WAF regional e certificado do ALB acompanham a região dos recursos).

### Variáveis do laboratório

Defina os valores abaixo (os exemplos são apenas sugestões — troque pelos seus):

| Variável | Descrição | Exemplo |
|---|---|---|
| `<DOMINIO>` | Seu domínio com zona hospedada no Route 53 | `exemplo.com` |
| `<REGIAO>` | Região AWS do laboratório | `sa-east-1` ou `us-east-1` |
| `<VPC_CIDR>` | Bloco CIDR da VPC | `10.0.0.0/16` |
| `<VPC>` | Nome da VPC | ex.: `vpc-waf-lab` |
| `<SUBNET_A>` | Subnet pública na AZ 1 | ex.: `subnet-lab-a` |
| `<SUBNET_B>` | Subnet pública na AZ 2 | ex.: `subnet-lab-b` |
| `<SG_ALB>` | Security Group do ALB | ex.: `sg-alb-lab` |
| `<SG_EC2>` | Security Group da EC2 | ex.: `sg-ec2-lab` |
| `<IAM_ROLE_SSM>` | Função IAM para SSM | ex.: `role-ec2-ssm-lab` |
| `<EC2>` | Nome da instância EC2 | ex.: `ec2-waf-lab` |
| `<TG_SEM_WAF>` | Target Group do ALB sem WAF | ex.: `tg-sem-waf-lab` |
| `<TG_COM_WAF>` | Target Group do ALB com WAF | ex.: `tg-com-waf-lab` |
| `<ALB_SEM_WAF>` | Application Load Balancer sem WAF | ex.: `alb-sem-waf-lab` |
| `<ALB_COM_WAF>` | Application Load Balancer com WAF | ex.: `alb-com-waf-lab` |
| `<SUBDOMINIO_SEM_WAF>` | Subdomínio do endpoint sem WAF | ex.: `alb-sem-waf.<DOMINIO>` |
| `<SUBDOMINIO_COM_WAF>` | Subdomínio do endpoint com WAF | ex.: `alb-com-waf.<DOMINIO>` |
| `<WEB_ACL>` | Web ACL regional do WAF | ex.: `waf-lab-path-traversal` |
| `<REGRA_PATH_TRAVERSAL>` | Regra de bloqueio de Path Traversal | ex.: `Block-Path-Traversal-Lab` |
| `<REGRA_CAPTCHA>` | Regra de CAPTCHA por país | ex.: `Captcha-Fora-do-Brasil` |

> **A sequência importa.** Ordem: **VPC → Security Groups → EC2 (IAM/SSM) → Nginx → Target Groups → ACM → ALBs (com Listeners HTTPS) → Route 53 → WAF → Testes → Exclusão**.

---

## Antes de começar

- Conta AWS com permissões para VPC, EC2, ELB, WAF, ACM, Route 53, IAM e Systems Manager.
- Domínio com **zona hospedada no Route 53** (`<DOMINIO>`).
- Escolha a **região** e a mantenha selecionada no canto superior direito durante todo o lab.

> A partir daqui, o passo a passo se refere aos recursos pelas variáveis definidas acima (`<VPC>`, `<SG_ALB>`, `<EC2>`, etc.). Substitua cada uma pelo valor que você escolheu.

---

## Etapa 1 — VPC e rede

> Você pode usar a VPC padrão da conta para simplificar. O passo a passo abaixo cria uma VPC dedicada com o assistente.

1. Abra o serviço **VPC**.
2. Clique em **Criar VPC**.
3. Selecione **VPC e mais** (assistente que cria subnets, IGW e rotas de uma vez).
4. **Marcadores de nome:** `<VPC>`.
5. **Bloco CIDR IPv4:** `<VPC_CIDR>`.
6. **Número de zonas de disponibilidade (AZs):** **2**.
7. **Número de subnets públicas:** **2**. **Subnets privadas:** 0 (para simplificar o lab).
8. **Gateways NAT:** Nenhum. **Endpoints de VPC:** Nenhum.
9. Clique em **Criar VPC**. O assistente cria a VPC, o **Internet Gateway**, as **2 subnets públicas** e a **Route Table** com rota `0.0.0.0/0` para o IGW.

> O ALB exige **pelo menos duas subnets em AZs diferentes** — por isso criamos duas.

---

![Descrição da imagem](<imagens/imagem%20(29).png>)

## Etapa 2 — Security Groups

Crie dois security groups em **VPC > Grupos de segurança > Criar grupo de segurança**, ambos na `<VPC>`.

### 2.1 SG do ALB — `<SG_ALB>`

- **Regras de entrada (inbound):**
  - Tipo **HTTP**, porta **80**, origem **0.0.0.0/0**.
  - Tipo **HTTPS**, porta **443**, origem **0.0.0.0/0**.
- **Regras de saída:** manter padrão (todo o tráfego).

### 2.2 SG da EC2 — `<SG_EC2>`

- **Regras de entrada (inbound):**
  - Tipo **HTTP**, porta **80**, origem: **selecione o grupo de segurança `<SG_ALB>`** (não use 0.0.0.0/0).
- **Regras de saída:** manter padrão (necessário para SSM e updates).

> A porta HTTP da EC2 fica acessível **apenas pelo ALB**. Não abrimos SSH (porta 22) — a administração é via **SSM Session Manager**.

---

![Descrição da imagem](<imagens/imagem%20(30).png>)

## Etapa 3 — Perfil IAM para SSM

Para usar o Session Manager, a EC2 precisa de um perfil de instância com a política do SSM.

1. Abra **IAM > Funções (Roles) > Criar função**.
2. **Entidade confiável:** **Serviço AWS** → **EC2**.
3. Anexe a política gerenciada **AmazonSSMManagedInstanceCore**.
4. **Nome:** `<IAM_ROLE_SSM>`. Clique em **Criar função**.

---

## Etapa 4 — Instância EC2 (Ubuntu)

1. Abra **EC2 > Instâncias > Executar instâncias (Launch instances)**.
2. **Nome:** `<EC2>`.
3. **Imagem (AMI):** **Ubuntu Server** (LTS).
4. **Tipo de instância:** uma pequena (ex.: `t3.micro`).
5. **Par de chaves:** selecione **Continuar sem par de chaves** (vamos usar SSM, não SSH).
   > Ao executar a instância, a AWS pode abrir um aviso dizendo que nenhum par de chaves foi selecionado. Isso é **esperado** neste lab. Escolha **Prosseguir sem par de chaves** e continue — o acesso será feito pelo SSM Session Manager (Etapa 5), sem SSH nem porta 22.
6. **Configurações de rede > Editar:**
   - **VPC:** `<VPC>`.
   - **Sub-rede:** `<SUBNET_A>` (uma das subnets **públicas** criadas na Etapa 1 — o lab não tem subnets privadas).
   - **Atribuir IP público automaticamente:** **Habilitar** (necessário para o SSM alcançar a internet nesta topologia simplificada).
   - **Firewall (grupos de segurança):** selecione **grupo existente** → `<SG_EC2>`.
7. **Detalhes avançados > Perfil do IAM da instância:** selecione `<IAM_ROLE_SSM>`.
8. **Dados do usuário (User data):** deixe **em branco** e use a **Etapa 5 (SSM)** para instalar o Nginx.
   > O script `install-nginx.sh` publica a página completa (HTML + CSS) e ultrapassa o limite de **16 KB** do campo User data. Por isso, nesta versão do lab, a instalação é feita pela Etapa 5 via Systems Manager (sem limite de tamanho). Não marque "dados do usuário já codificados em base64" — o campo espera texto puro.
9. Clique em **Executar instância**. Se aparecer o aviso de par de chaves, selecione **Prosseguir sem par de chaves** e confirme.
   > Antes de executar, confira: **Perfil do IAM** = `<IAM_ROLE_SSM>` (sem ele o SSM não conecta) e **Dados do usuário** em branco.

---

![Descrição da imagem](<imagens/imagem%20(31).png>)

## Etapa 5 — Nginx via Systems Manager

1. Abra **Systems Manager > Session Manager > Iniciar sessão**.
2. Selecione a instância `<EC2>` e clique em **Iniciar sessão**.
3. No terminal da sessão, torne-se root:
   ```bash
   sudo -i
   ```
4. Crie o arquivo do script e cole o conteúdo de `scripts/install-nginx.sh`. Use o `cat` com here-doc para evitar problemas ao colar textos grandes:
   ```bash
   cat > install-nginx.sh <<'EOF'
   # (cole aqui TODO o conteudo de scripts/install-nginx.sh e tecle Enter)
   EOF
   ```
   > Alternativa: `nano install-nginx.sh`, cole o conteúdo, salve com **Ctrl+O**, **Enter**, e saia com **Ctrl+X**.
5. Execute a instalação:
   ```bash
   bash install-nginx.sh
   ```
   O script instala o Nginx, publica `index.html`, `style.css` e o endpoint `/health`, e executa `systemctl enable nginx` e `systemctl restart nginx`.
6. Verifique localmente:
   ```bash
   systemctl status nginx --no-pager
   curl -s http://localhost/health
   ```
   O `curl` deve retornar `{"status": "healthy"}`.

---

## Etapa 6 — Target Groups

Crie **dois** Target Groups (um para cada ALB), ambos registrando a **mesma EC2**.

1. Abra **EC2 > Grupos de destino (Target Groups) > Criar grupo de destino**.
2. **Tipo de destino:** **Instâncias**.
3. **Nome:** `<TG_SEM_WAF>`.
4. **Protocolo/Porta:** **HTTP / 80**.
5. **VPC:** `<VPC>`.
6. **Verificações de integridade (Health checks):**
   - **Caminho:** `/health`.
   - **Códigos de sucesso:** `200`.
7. Avance para a etapa **Registrar destinos**. Nesta topologia (tipo de destino **Instâncias**), o registro é **manual** — a instância **não** é adicionada sozinha:
   - Na lista **Instâncias disponíveis**, marque a `<EC2>`.
   - Confirme a **porta 80** e clique em **Incluir como pendente abaixo**.
   - A instância aparece em **Destinos**. Clique em **Criar grupo de destino**.
8. Repita criando `<TG_COM_WAF>` com as **mesmas configurações**, registrando a **mesma** instância (`<EC2>`, porta 80).

> **Atenção (diferente do ECS):** com **EC2 tipo Instância**, você precisa registrar a instância no Target Group manualmente. Ao contrário do ECS, onde o serviço registra os alvos automaticamente, aqui um Target Group com **0 destinos** faz o ALB responder **503 Service Temporarily Unavailable**. Ambos os Target Groups (`<TG_SEM_WAF>` e `<TG_COM_WAF>`) devem apontar para a **mesma** `<EC2>`.

> **Se um Target Group já foi criado sem destinos:** abra **EC2 > Target Groups >** selecione o grupo **> aba Destinos (Targets) > Registrar destinos**, marque a `<EC2>` (porta 80), clique em **Incluir como pendente abaixo** e depois **Registrar destinos pendentes**. Aguarde ~1 min até o status ficar **Integro (healthy)**.

---

![Descrição da imagem](<imagens/imagem%20(32).png>)

## Etapa 7 — Certificado ACM (mesma região do ALB)

> Diferente do Lab 01 (CloudFront/us-east-1), aqui o ALB é **regional**: o certificado deve estar na **mesma região do ALB**.

1. Confirme a **região** do laboratório no seletor de região.
2. Abra **AWS Certificate Manager (ACM) > Solicitar > Solicitar um certificado público**.
3. Domínios:
   - `<SUBDOMINIO_SEM_WAF>`
   - Adicione `<SUBDOMINIO_COM_WAF>` (ou use um curinga `*.<DOMINIO>`).
4. **Método de validação:** **Validação por DNS**.
5. Clique em **Solicitar**, abra o certificado e clique em **Criar registros no Route 53**.
6. Aguarde o status **Emitido**.

---

## Etapa 8 — Application Load Balancers

Crie **dois** ALBs. Os dois usam as **2 subnets públicas** e o SG `<SG_ALB>`.

### 8.1 ALB SEM WAF

1. Abra **EC2 > Load Balancers > Criar load balancer**.
2. Escolha **Application Load Balancer**.
3. **Nome:** `<ALB_SEM_WAF>`.
4. **Esquema:** **Voltado para a Internet (internet-facing)**.
5. **Mapeamento de rede:** VPC `<VPC>`, selecione **as duas subnets** (`<SUBNET_A>` e `<SUBNET_B>`).
6. **Grupos de segurança:** `<SG_ALB>`.
7. **Listeners e roteamento:**
   - **Listener HTTP :80** → ação **Redirecionar para URL** → **HTTPS**, porta **443**, código **301** (deixe "host/caminho/consulta" originais). Este listener **não** pede certificado.
   - Clique em **Adicionar listener** e crie o **Listener HTTPS :443** → ação **Encaminhar aos grupos de destino** → `<TG_SEM_WAF>`.
   - Ainda no listener HTTPS, na seção **Configurações seguras do listener**: em **Origem do certificado** escolha **Do ACM** e, em **Certificado (do ACM)**, selecione o certificado da Etapa 7 (ex.: o curinga `*.<DOMINIO>`). Deixe a **Política de segurança** no padrão recomendado e **mTLS desativado**.
   > O campo do certificado **só aparece no listener HTTPS:443** — o listener HTTP:80 (redirecionamento) não tem esse campo.
8. Clique em **Criar load balancer**.

### 8.2 ALB COM WAF

1. Repita o processo criando `<ALB_COM_WAF>`.
2. Mesmas subnets (`<SUBNET_A>` e `<SUBNET_B>`) e o mesmo SG `<SG_ALB>`.
3. **Listener HTTP :80** → **Redirecionar para URL** → HTTPS:443 (301), igual ao ALB SEM WAF.
4. **Adicionar listener HTTPS :443** → **Encaminhar** para o Target Group `<TG_COM_WAF>`; em **Configurações seguras do listener**, **Origem do certificado = Do ACM** e selecione o **mesmo certificado** da Etapa 7.
5. Clique em **Criar load balancer**.

> A **única** diferença entre os dois ALBs é que o `<ALB_COM_WAF>` terá a Web ACL associada na Etapa 9. O `<ALB_SEM_WAF>` **nunca** recebe WAF.

### 8.3 Confirmar saúde dos alvos

- Vá em **Target Groups** e confirme que a EC2 aparece como **Healthy** nos dois grupos antes de testar. Se estiver **Unhealthy**, veja a solução de problemas no fim deste documento.

---

![Descrição da imagem](<imagens/imagem%20(33).png>)

## Etapa 9 — AWS WAF (Web ACL `<WEB_ACL>` + 2 regras)

> A Web ACL deve ser **regional** e criada na **mesma região do ALB**. Ela será associada **somente ao `<ALB_COM_WAF>`**.
> O Console novo chama a Web ACL de **"pacote de proteção (ACL da Web)"**. O fluxo abaixo segue essa interface atual.

### 9.1 Iniciar a criação

1. Na busca do Console, digite **WAF** e abra **AWS WAF & Shield**.
2. No menu à esquerda, clique em **Web ACLs** (ou **Pacotes de proteção**).
3. No seletor **Escopo da região** (topo), selecione **Regional** e confirme a **região do ALB** (`<REGIAO>`).
   > **Importante:** não use o escopo **CloudFront (global)** — uma Web ACL CloudFront **não** pode ser associada a um ALB.
4. Clique em **Criar pacote de proteção (ACL da Web)**.

![Descrição da imagem](<imagens/imagem%20(8).png>)

![Descrição da imagem](<imagens/imagem%20(34).png>)

### 9.2 Escolher o tipo de pacote

Na tela **"Escolher proteções iniciais"**, três colunas são oferecidas:

1. Escolha a coluna **"Crie seu próprio pacote usando todas as proteções oferecidas pelo AWS WAF"** (a opção **"Você o constrói"**, custo estimado mais baixo).
   > **Não** escolha "Regras recomendadas" nem "Regras essenciais" — elas trazem regras gerenciadas (Anti-DDoS, SQLi, bots, etc.) que **não** fazem parte deste lab e encarecem o WAF. O lab usa **apenas 2 regras próprias**.

### 9.3 Nome e descrição

1. Em **Nome**, digite `<WEB_ACL>`.
2. Em **Descrição** (opcional), digite `Lab 02 - bloqueio de Path Traversal`.
3. **Destino do registro em log (CloudWatch):** **opcional**. Se quiser habilitar, o grupo de logs precisa começar com `aws-waf-logs-`. Pode deixar em branco — os bloqueios aparecem em **Sampled requests** mesmo sem log.

### 9.4 Regra 1 — `<REGRA_PATH_TRAVERSAL>` (Path Traversal)

No painel lateral **"Adicionar regras"**:

1. Selecione **Regra personalizada** e clique em **Seguinte**.
2. Na tela de **tipos de regra**, escolha **Regra personalizada** (a última opção, com o ícone AND/OR) e clique em **Seguinte**.
   > As opções "baseada em IP", "localização geográfica" e "baseada em taxas" **não** servem para esta regra.
3. Preencha:
   - **Ação:** **Block**.
   - **Nome da regra:** `<REGRA_PATH_TRAVERSAL>` (com hífens; confira que terminou em `-Lab`).
   - **Se uma solicitação:** **corresponde à instrução**.
   - **Inspecionar:** **Todos os parâmetros de consulta** (a query string, onde vai o `?file=...`).
   - **Tipo de correspondência:** **Contém string** (Contains string).
   - **String para correspondência:** `../`
   - **Transformação de texto:** clique em **Adicionar transformação de texto** e escolha **Decodificar URL** (URL decode) — captura também `%2e%2e%2f`. Deixe **Pre-parse text transformations** vazio.
4. Clique em **Adicionar regra**.

![Descrição da imagem](<imagens/imagem%20(36).png>)

### 9.5 Regra 2 — `<REGRA_CAPTCHA>` (CAPTCHA fora do Brasil)

> Objetivo: quem acessa **de fora do Brasil** recebe um **CAPTCHA**; quem acessa **do Brasil** passa direto. O CAPTCHA é uma página interativa — por isso o teste desta regra é feito **pelo navegador**.

No painel **"Adicionar regras"** novamente:

1. Selecione **Regra personalizada** e clique em **Seguinte**.
2. Na tela de tipos, escolha **Regra baseada em localização geográfica** (ícone do globo) e clique em **Seguinte**.
3. Preencha:
   - **Ação:** **CAPTCHA** (o padrão vem como **Block** — **troque para CAPTCHA**).
   - **Nome da regra:** `<REGRA_CAPTCHA>` (com hífens; confira que terminou em `-Brasil`).
   - **País:** selecione **Brazil - BR**.
   - **Configuração de regras > Instrução de negação (NOT):** marque **Negar resultados da instrução** — a regra passa a valer quando o país **NÃO** é o Brasil (o campo "Se uma solicitação" mostrará **"não corresponde à instrução (NOT)"**).
   - **Endereço IP de origem:** deixe **Endereço IP de origem** (Source IP address).
   - **Tempo de imunidade** (opcional): deixe o padrão (300 s).
4. Clique em **Adicionar regra**.

> **Atenção aos 2 erros mais comuns:** (a) a **Ação** da regra 2 vem como **Block** por padrão — troque para **CAPTCHA**; (b) confira os **nomes completos** (`<REGRA_PATH_TRAVERSAL>` e `<REGRA_CAPTCHA>`), pois é fácil salvar cortado.

![Descrição da imagem](<imagens/imagem%20(37).png>)

### 9.6 Prioridade e ação padrão

1. Feche o painel de "Adicionar regras" (você já tem as **2 regras** — não crie uma terceira).
2. Na lista de regras, confirme que a `<REGRA_PATH_TRAVERSAL>` está **acima** (prioridade mais alta / avaliada primeiro) que a `<REGRA_CAPTCHA>`. Use **Editar ordem das regras** se precisar.
   - Com essa ordem: fora do Brasil **com** `../` → **403** (Block vence); fora do Brasil **sem** `../` → **CAPTCHA**; do Brasil sem `../` → passa direto.
3. Em **Ação padrão da Web ACL**, deixe **Permitir (Allow)**.
4. Revise e clique em **Criar pacote de proteção (ACL da Web)**.

![Descrição da imagem](<imagens/imagem%20(35).png>)

### 9.7 Confirmar a associação ao ALB (passo crítico)

> ⚠️ **Sem associar a Web ACL ao `<ALB_COM_WAF>`, o WAF não inspeciona nada e o endpoint COM WAF se comporta igual ao SEM WAF.** Se você associou na criação (passo "Selecione recursos para proteger"), apenas confirme; caso contrário, associe agora.

1. Abra **WAF > Web ACLs > `<WEB_ACL>` > aba Recursos AWS associados**.
2. Se o `<ALB_COM_WAF>` **não** estiver na lista: **Adicionar recursos AWS** → tipo **Application Load Balancer** → marque **`<ALB_COM_WAF>`** (somente ele) → **Adicionar**.
3. Confirmação alternativa: em **EC2 > Load Balancers > `<ALB_COM_WAF>` > aba Integrações**, o bloco **AWS Web Application Firewall (WAF)** deve aparecer como **Integrado**, apontando para `<WEB_ACL>`.

> **Sobre o CAPTCHA:** ele foi feito para navegadores (rodam JavaScript). Scripts (curl, `Invoke-WebRequest`, os scripts deste lab) **não resolvem** o desafio — recebem **HTTP 405** com o corpo do CAPTCHA. Valide o CAPTCHA **pelo navegador**.

> **Adicionar/editar regras depois da criação:** **WAF > Web ACLs > `<WEB_ACL>` > aba Regras (Rules) > Adicionar regras > Adicionar minha própria regra e grupos de regras**.

---
## Etapa 10 — Route 53 (registros Alias)

1. Abra **Route 53 > Zonas hospedadas > `<DOMINIO>`**.
2. **Criar registro:**
   - **Nome:** a parte de host de `<SUBDOMINIO_SEM_WAF>` (o rótulo antes de `<DOMINIO>`). **Tipo:** **A**. Ative **Alias**.
   - **Rotear tráfego para:** **Alias para Application/Classic Load Balancer** → região do lab → selecione o `<ALB_SEM_WAF>`.
   - **Criar registros**.
3. Repita para a parte de host de `<SUBDOMINIO_COM_WAF>` apontando para `<ALB_COM_WAF>`.
4. Aguarde a propagação DNS e teste com `nslookup`.

![Descrição da imagem](<imagens/imagem%20(42).png>)

---

## Etapa 11 — Testes (com comprovação de cada ataque)

Faça os testes **na ordem abaixo**. Depois de cada teste há um bloco **"Onde comprovar que aconteceu"** — o lugar exato onde você vê o ataque registrado (bloqueado, permitido ou desafiado).

> **Onde o WAF registra tudo:** o principal painel de evidência é o **Sampled requests (Solicitações de amostra)**:
> **WAF & Shield > Web ACLs > `<WEB_ACL>` > aba Solicitações de amostra (Sampled requests) > Obter amostra**.
> Cada linha mostra a **URI**, a **Ação** (Allow / Block / CAPTCHA), a **Regra correspondente** e o **País**. É ali que você "vê o ataque".
> As **métricas** (gráficos) ficam na aba **Visão geral (Overview)** da mesma Web ACL e em **CloudWatch > Métricas > AWS/WAFV2** (podem levar de 1 a 5 minutos para aparecer).

### Teste 1 — Acesso normal SEM WAF

```
https://<SUBDOMINIO_SEM_WAF>/
```
**Esperado:** o site carrega (HTTP 200).

**Onde comprovar que aconteceu:**
- **access.log (SSM):** em `sudo tail -f /var/log/nginx/access.log`, aparece a linha `GET / HTTP/1.1 200`.
- Não há WAF neste ALB, então **não** há registro em Sampled requests para o `<ALB_SEM_WAF>`.

![Descrição da imagem](<imagens/imagem%20(27).png>)

### Teste 2 — Path Traversal SEM WAF (o ataque passa)

```
https://<SUBDOMINIO_SEM_WAF>/?file=../../etc/passwd
```
**Esperado:** a página responde (200/404) — o ataque **chega ao Nginx** (não há WAF para barrar). Nenhum arquivo é lido.

**Onde comprovar que aconteceu:**
- **access.log (SSM):** aparece a linha `GET /?file=../../etc/passwd ...` — prova de que a requisição chegou ao servidor.
- É o "antes": mostra o ataque passando quando **não** há WAF.

![Descrição da imagem](<imagens/imagem%20(7).png>)

### Teste 3 — Acesso normal COM WAF (do Brasil)

```
https://<SUBDOMINIO_COM_WAF>/
```
**Esperado:** o site carrega (HTTP 200).

**Onde comprovar que aconteceu:**
- **Sampled requests:** a requisição, se aparecer na amostra, tem **Ação: Allow** (passou pela ação padrão da Web ACL, sem casar regra).
- **Visão geral / CloudWatch:** o gráfico **Solicitações permitidas (AllowedRequests)** sobe.

![Descrição da imagem](<imagens/imagem%20(28).png>)
![Descrição da imagem](<imagens/imagem%20(15).png>)


### Teste 4 — Path Traversal COM WAF (o ataque é BLOQUEADO)

```
https://<SUBDOMINIO_COM_WAF>/?file=../../etc/passwd
```
**Esperado:** **HTTP 403** — a regra `<REGRA_PATH_TRAVERSAL>` bloqueia antes de chegar ao Nginx.
> Variação (URL encoding) para testar a transformação URL decode: `?file=%2e%2e%2fetc%2fpasswd`.

**Onde comprovar que aconteceu (este é o principal):**
1. **Sampled requests:** **WAF > Web ACLs > `<WEB_ACL>` > Solicitações de amostra > Obter amostra**. A sua requisição aparece com **Ação: BLOCK** e **Regra correspondente: `<REGRA_PATH_TRAVERSAL>`**. **Essa linha é a prova do bloqueio.**
2. **Visão geral / CloudWatch (AWS/WAFV2):** o gráfico **Solicitações bloqueadas (BlockedRequests)** sobe logo após o teste.
3. **access.log (SSM):** a requisição bloqueada **NÃO** aparece no `/var/log/nginx/access.log` — foi barrada no ALB, antes do Nginx. (Compare com o Teste 2, onde ela apareceu.)

> Dica de evidência: rode o Teste 2 e o Teste 4 em sequência, olhando o `tail -f` do access.log. Ver a linha aparecer (SEM WAF) e **não** aparecer (COM WAF) é a demonstração mais clara do lab.

![Descrição da imagem](<imagens/imagem%20(12).png>)
![Descrição da imagem](<imagens/imagem%20(20).png>)
![Descrição da imagem](<imagens/imagem%20(38).png>)
![Descrição da imagem](<imagens/imagem%20(39).png>)
![Descrição da imagem](<imagens/imagem%20(40).png>)
![Descrição da imagem](<imagens/imagem%20(41).png>)

### Teste 5 — Scripts (faz os testes de uma vez)

Os scripts fazem as 4 requisições (Normal e Path Traversal, nos dois endpoints) e mostram o resultado lado a lado. Eles usam **apenas a biblioteca padrão** — não precisa `pip install`.

**Pré-requisito (Python):** se ainda não tiver o Python 3, instale:
- **Windows:** `winget install Python.Python.3.12` (ou baixe em python.org e marque **Add python.exe to PATH**).
- **macOS:** já costuma vir; se precisar, `brew install python`. **Linux:** `sudo apt install -y python3`.
- Confirme com `python --version` (no macOS/Linux use `python3`). O **PowerShell** já vem no Windows.

**Rode a partir da raiz do projeto**:

```bash
python tests/test-path-traversal.py --sem-waf https://<SUBDOMINIO_SEM_WAF> --com-waf https://<SUBDOMINIO_COM_WAF>
```
```powershell
.\tests\test-path-traversal.ps1 -UrlSemWaf "https://<SUBDOMINIO_SEM_WAF>" -UrlComWaf "https://<SUBDOMINIO_COM_WAF>"
```
> Se o PowerShell bloquear o `.ps1`, libere só a sessão atual: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.
> No macOS/Linux, se `python` não existir, use `python3`.

**Saída esperada:**
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

![Descrição da imagem](<imagens/imagem%20(17).png>)
![Descrição da imagem](<imagens/imagem%20(19).png>)

Se a linha `Path Traversal` do bloco **COM WAF** mostrar **403 BLOCKED**, o WAF está funcionando.

**Onde comprovar que aconteceu:**
- **Sampled requests:** aparecem as requisições ao endpoint COM WAF — a **Normal** com **Allow** e a **Path Traversal** com **BLOCK / `<REGRA_PATH_TRAVERSAL>`**.
- **Visão geral:** **BlockedRequests** e **AllowedRequests** sobem.
> Se você estiver **fora do Brasil**, o COM WAF nos scripts retorna **405** (a regra de CAPTCHA responde o desafio, que o script não resolve). Rode os scripts **do Brasil** para ver o 200/403.

### Teste 6 — CAPTCHA (acesso de fora do Brasil)

O CAPTCHA só aparece **de fora do Brasil** e só é resolvido em **navegador** (scripts recebem HTTP 405). Como você provavelmente está no Brasil, mude o **seu** IP de origem (você não ataca ninguém):

- **VPN (mais simples):** app de VPN conectado a **outro país** (ex.: EUA, Portugal). Gratuitas/freemium: **Proton VPN**, **Windscribe**, **Cloudflare WARP** (confira se muda o país). Confirme em `https://ipinfo.io` que o país **não** é o Brasil.
- **Instância em outra região:** suba uma EC2 fora do Brasil e abra o site por um navegador de dentro dela.

Com o IP fora do Brasil, no **navegador**:

1. Acesse `https://<SUBDOMINIO_COM_WAF>/` → aparece a **página de CAPTCHA**. Resolva → o site carrega.
2. Acesse `https://<SUBDOMINIO_COM_WAF>/?file=../../etc/passwd` → **403** (o Block do path traversal vence o CAPTCHA).
3. Compare: do **Brasil** (VPN desligada), o mesmo `/` carrega **direto**, sem CAPTCHA.

**Onde comprovar que aconteceu:**
1. **Sampled requests:** a requisição de fora do Brasil aparece com **Ação: CAPTCHA** e **Regra: `<REGRA_CAPTCHA>`**, com **País (Country) diferente de BR**.
2. A do passo 2 (com `../`) aparece com **Ação: BLOCK** / **`<REGRA_PATH_TRAVERSAL>`** — provando que o Block tem prioridade sobre o CAPTCHA.
3. A do Brasil **não** aparece com ação CAPTCHA (passou direto) — confirma que o Negate está correto.

<p align="center">
  <img src="imagens/imagem%20(21).png" width="30%" />
  <img src="imagens/imagem%20(22).png" width="30%" />
  <img src="imagens/imagem%20(23).png" width="30%" />
</p>

![Descrição da imagem](<imagens/imagem%20(25).png>)

### Métricas do ALB (opcional)

Em **CloudWatch > Métricas > AWS/ApplicationELB**, filtrando pelos seus ALBs:
- `RequestCount` — total de requisições.
- `HTTPCode_ELB_4XX_Count` — inclui os 403 gerados pelo WAF no `<ALB_COM_WAF>`.
- `HealthyHostCount` (≥ 1) e `UnHealthyHostCount` (0).

---
## Etapa 12 — Exclusão de recursos (faça ao terminar)

> ALB e EC2 **cobram por hora**; a Web ACL do WAF também cobra. Exclua tudo ao concluir. Ordem inversa da criação.

### 12.1 Route 53

- Exclua os registros `<SUBDOMINIO_SEM_WAF>` e `<SUBDOMINIO_COM_WAF>`.

### 12.2 AWS WAF

1. **WAF > Web ACLs > `<WEB_ACL>`**.
2. Em **Recursos AWS associados**, remova a associação com `<ALB_COM_WAF>`.
3. Exclua a Web ACL (isso remove as duas regras: `<REGRA_PATH_TRAVERSAL>` e `<REGRA_CAPTCHA>`).

### 12.3 Application Load Balancers

- **EC2 > Load Balancers**, selecione cada ALB e **Excluir** (`<ALB_SEM_WAF>` e `<ALB_COM_WAF>`).

### 12.4 Target Groups

- **EC2 > Grupos de destino**, exclua `<TG_SEM_WAF>` e `<TG_COM_WAF>`.

### 12.5 EC2

- **EC2 > Instâncias**, selecione `<EC2>` e **Encerrar (Terminate)**.

### 12.6 ACM (opcional)

- Exclua o certificado se não for reutilizar (só é possível quando não estiver associado a nenhum ALB).

### 12.7 VPC e rede (se criou VPC dedicada)

- **VPC > Suas VPCs**, exclua `<VPC>` (o Console remove subnets, route tables e IGW associados). Exclua também os security groups se não forem removidos automaticamente.

### 12.8 IAM (opcional)

- Exclua a função `<IAM_ROLE_SSM>` se não for reutilizar.

### Checklist final

- [ ] Registros Alias removidos do Route 53
- [ ] Web ACL `<WEB_ACL>` desassociada e excluída
- [ ] Dois ALBs excluídos
- [ ] Dois Target Groups excluídos
- [ ] Instância EC2 encerrada
- [ ] Certificado ACM excluído (opcional)
- [ ] VPC/subnets/IGW/SGs excluídos (se criou VPC dedicada)
- [ ] Função IAM removida (opcional)
- [ ] Nenhum recurso do laboratório restante gerando custo

---

## Solução de problemas rápida

| Sintoma | O que verificar |
|---|---|
| **503 Service Temporarily Unavailable** no ALB | O Target Group está com **0 destinos** ou nenhum alvo **Integro**. Registre a `<EC2>` (porta 80) no Target Group (**aba Destinos > Registrar destinos**). Com EC2 tipo Instância o registro é **manual** (diferente do ECS). |
| Alvo **Unhealthy** no Target Group | Nginx ativo? `/health` retorna 200? SG da EC2 permite porta 80 vindo do SG do ALB? Health Check Path = `/health`? |
| 502/504 no ALB | EC2 rodando, Nginx ativo, SG da EC2 liberando o SG do ALB na porta 80. |
| COM WAF **não** bloqueia `../` | Web ACL associada ao `<ALB_COM_WAF>`? (confira em **ALB > Integrações > WAF = Integrado**) Regra com ação **Block**? Inspecionando query string? Transformação **URL decode** aplicada? |
| Web ACL **não aparece** para associar ao ALB | Ela foi criada no escopo **CloudFront (global)**. O ALB só aceita Web ACL **Regional** na mesma região. Recrie a Web ACL escolhendo **Regional** + a região do ALB. |
| Regra de CAPTCHA **bloqueia** em vez de mostrar o desafio | A **Ação** da regra ficou como **Block**. Edite a regra `<REGRA_CAPTCHA>` e troque a ação para **CAPTCHA**. |
| SEM WAF retorna 403 | O ALB SEM WAF não deve ter Web ACL associada. |
| CAPTCHA aparece **mesmo do Brasil** | Regra `<REGRA_CAPTCHA>` provavelmente sem o **Negate statement**. Ative o botão **Negate** e confirme o país **BR**. |
| CAPTCHA **não** aparece de fora do Brasil | Seu IP realmente sai por outro país? (confirme em site de "meu IP"). A ação da regra é **CAPTCHA**? Está testando pelo **navegador** (não por script)? |
| De fora do Brasil recebo **405** em vez da página | ✅ Esperado quando o cliente é um **script** (curl/Invoke-WebRequest): o 405 traz o corpo do CAPTCHA. Use o **navegador** para ver e resolver o desafio. |
| Certificado não aparece no ALB | Precisa estar **Emitido** e na **mesma região** do ALB. |
| Não consigo abrir sessão SSM | Perfil IAM com `AmazonSSMManagedInstanceCore` anexado e a EC2 com saída para a internet (IP público / rota IGW). |
| DNS não resolve | Registros Alias corretos no Route 53; aguarde propagação. |
