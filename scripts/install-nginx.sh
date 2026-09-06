#!/usr/bin/env bash
#
# AWS WAF Security Lab - Projeto 02 (Path Traversal)
# Instala e configura o Nginx em uma instancia Ubuntu Linux.
#
# O que este script faz:
#   1. Instala o Nginx.
#   2. Publica index.html (pagina completa), style.css, favicon.ico e o endpoint /health.
#   3. Habilita e inicia o Nginx.
#
# Uso (na EC2, via SSM Session Manager ou user data):
#   sudo bash install-nginx.sh
#
# Observacao: NAO cria nenhum endpoint vulneravel. O parametro ?file=... usado
# no teste de Path Traversal e ignorado pela aplicacao - existe apenas para
# testar a inspecao do AWS WAF.

set -euo pipefail

WEB_ROOT="/var/www/html"

echo "==> Atualizando pacotes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx

echo "==> Criando ${WEB_ROOT}/index.html ..."
cat > "${WEB_ROOT}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content="AWS WAF Security Lab - Projeto 02: Proteção contra Path Traversal com Application Load Balancer e EC2 Linux" />
    <title>AWS WAF Security Lab - Projeto 02 | Proteção Path Traversal</title>
    <link rel="stylesheet" href="style.css" />
</head>
<body>
    <header class="hero">
        <div class="hero-content">
            <div class="badge">AWS WAF Security Lab</div>
            <h1>Proteção contra Path Traversal / LFI</h1>
            <h2>Application Load Balancer + EC2 Linux</h2>
            <div class="hero-tags">
                <span class="tag">Route 53</span>
                <span class="tag">ACM</span>
                <span class="tag">AWS WAF</span>
                <span class="tag">ALB</span>
                <span class="tag">Target Group</span>
                <span class="tag">EC2</span>
                <span class="tag">Ubuntu</span>
                <span class="tag">Nginx</span>
                <span class="tag">Systems Manager</span>
                <span class="tag">CloudWatch</span>
            </div>
        </div>
    </header>

    <nav class="navbar">
        <a href="#sobre">Sobre</a>
        <a href="#servicos">Serviços</a>
        <a href="#pathtraversal">Path Traversal</a>
        <a href="#arquitetura">Arquitetura</a>
        <a href="#resultado">Resultado</a>
    </nav>

    <main>
        <!-- SOBRE -->
        <section id="sobre" class="section">
            <h2 class="section-title">Sobre o Projeto</h2>
            <div class="card">
                <p>
                    Este laboratório demonstra como o <strong>AWS WAF</strong> pode identificar e
                    bloquear uma tentativa controlada de <strong>Path Traversal / Local File
                    Inclusion (LFI)</strong> antes que a requisição alcance uma instância
                    <strong>EC2 Linux</strong> rodando Nginx.
                </p>
                <p>Existem dois endpoints que apontam para a mesma aplicação:</p>
                <div class="endpoint-grid">
                    <div class="endpoint endpoint-open">
                        <div class="endpoint-icon">&#128275;</div>
                        <h3>SEM WAF</h3>
                        <p>A requisição atravessa o ALB e chega ao Nginx na EC2.</p>
                    </div>
                    <div class="endpoint endpoint-protected">
                        <div class="endpoint-icon">&#128737;</div>
                        <h3>COM WAF</h3>
                        <p>O AWS WAF inspeciona e bloqueia o padrão antes da aplicação.</p>
                    </div>
                </div>
                <p class="note">
                    Ambos os endpoints servem exatamente o <strong>mesmo conteúdo</strong>
                    a partir da EC2. A única diferença é a presença da Web ACL do AWS WAF.
                </p>
            </div>
        </section>

        <!-- SERVICOS / CARDS -->
        <section id="servicos" class="section">
            <h2 class="section-title">Componentes</h2>
            <div class="cards-grid">
                <div class="mini-card"><span class="mini-icon">&#127760;</span><h4>Route 53</h4><p>DNS dos subdomínios do laboratório.</p></div>
                <div class="mini-card"><span class="mini-icon">&#128737;</span><h4>AWS WAF</h4><p>Web ACL regional com regra de Path Traversal.</p></div>
                <div class="mini-card"><span class="mini-icon">&#9878;</span><h4>ALB</h4><p>Application Load Balancer (SEM e COM WAF).</p></div>
                <div class="mini-card"><span class="mini-icon">&#127919;</span><h4>Target Group</h4><p>Agrupa a EC2 como destino do ALB.</p></div>
                <div class="mini-card"><span class="mini-icon">&#10084;</span><h4>Health Check</h4><p>Endpoint /health respondendo 200.</p></div>
                <div class="mini-card"><span class="mini-icon">&#128421;</span><h4>EC2</h4><p>Instância que roda a aplicação.</p></div>
                <div class="mini-card"><span class="mini-icon">&#128039;</span><h4>Linux</h4><p>Ubuntu Server como sistema base.</p></div>
                <div class="mini-card"><span class="mini-icon">&#128640;</span><h4>Nginx</h4><p>Servidor web que serve o site.</p></div>
                <div class="mini-card"><span class="mini-icon">&#128202;</span><h4>CloudWatch</h4><p>Métricas do WAF e do ALB.</p></div>
            </div>
        </section>

        <!-- PATH TRAVERSAL -->
        <section id="pathtraversal" class="section">
            <h2 class="section-title">O que é Path Traversal?</h2>
            <div class="card">
                <p>
                    Ataques de <strong>Path Traversal</strong> (também chamados de
                    <em>directory traversal</em>) tentam usar sequências como <code>../</code>
                    para navegar para diretórios <strong>fora do local esperado</strong> pela
                    aplicação, tentando alcançar arquivos do sistema.
                </p>
                <div class="highlight-box">
                    <p><strong>Neste laboratório:</strong></p>
                    <ul>
                        <li>NÃO existe nenhum endpoint vulnerável.</li>
                        <li>NÃO há leitura real de <code>/etc/passwd</code> ou qualquer arquivo do sistema.</li>
                        <li>A sequência é enviada apenas como <strong>parâmetro HTTP</strong>.</li>
                    </ul>
                </div>
                <p>Exemplo de padrão típico enviado na query string:</p>
                <pre><code>?file=../../etc/passwd</code></pre>
                <p>
                    O Nginx <strong>não precisa retornar o arquivo</strong> — o parâmetro é
                    ignorado pela aplicação. O objetivo é apenas comparar se a requisição
                    <strong>chega ao servidor</strong> (SEM WAF) ou é <strong>bloqueada antes</strong>
                    (COM WAF).
                </p>
            </div>
        </section>

        <!-- ARQUITETURA -->
        <section id="arquitetura" class="section">
            <h2 class="section-title">Arquitetura</h2>
            <div class="arch-grid">
                <div class="card arch-card">
                    <h3>SEM WAF</h3>
                    <div class="flow">
                        <div class="flow-node">Internet</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node">Route 53</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node">ALB</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node">Target Group</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node flow-ec2">EC2 / Nginx</div>
                    </div>
                </div>
                <div class="card arch-card arch-protected">
                    <h3>COM WAF</h3>
                    <div class="flow">
                        <div class="flow-node">Internet</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node">Route 53</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node flow-waf">AWS WAF</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node">ALB</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node">Target Group</div>
                        <div class="flow-arrow">&#8595;</div>
                        <div class="flow-node flow-ec2">EC2 / Nginx</div>
                    </div>
                </div>
            </div>
        </section>

        <!-- RESULTADO -->
        <section id="resultado" class="section">
            <h2 class="section-title">Resultado Esperado</h2>
            <div class="card">
                <table class="result-table">
                    <thead>
                        <tr>
                            <th>Teste</th>
                            <th>SEM WAF</th>
                            <th>COM WAF</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>Normal</td>
                            <td><span class="status status-ok">Chega ao Nginx</span></td>
                            <td><span class="status status-ok">Chega ao Nginx</span></td>
                        </tr>
                        <tr>
                            <td>Path Traversal</td>
                            <td><span class="status status-ok">Chega ao Nginx</span></td>
                            <td><span class="status status-block">403 WAF</span></td>
                        </tr>
                        <tr>
                            <td>Health Check</td>
                            <td><span class="status status-ok">Healthy</span></td>
                            <td><span class="status status-ok">Healthy</span></td>
                        </tr>
                    </tbody>
                </table>
                <p class="note">
                    A principal evidência é o <code>access.log</code> do Nginx: SEM WAF a
                    requisição de Path Traversal aparece no log; COM WAF ela é bloqueada (403)
                    e <strong>não</strong> aparece no log.
                </p>
            </div>
        </section>
    </main>

    <footer class="footer">
        <p>AWS WAF Security Lab &mdash; Projeto 02 &mdash; Proteção contra Path Traversal com ALB + EC2 Linux</p>
        <p class="footer-sub">Laboratório educacional. Lembre-se de excluir os recursos após concluir.</p>
    </footer>
</body>
</html>
HTML

echo "==> Criando ${WEB_ROOT}/style.css ..."
cat > "${WEB_ROOT}/style.css" <<'CSS'
:root {
    --aws-dark: #0f1b2d;
    --aws-navy: #16243b;
    --aws-orange: #ff9900;
    --aws-blue: #2074d5;
    --text: #e6edf3;
    --text-muted: #9fb3c8;
    --card-bg: #1b2a41;
    --border: #2a3d59;
    --green: #1fab5a;
    --red: #e5484d;
    --radius: 12px;
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

html {
    scroll-behavior: smooth;
}

body {
    font-family: "Segoe UI", -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif;
    background: var(--aws-dark);
    color: var(--text);
    line-height: 1.65;
}

/* HERO */
.hero {
    background: radial-gradient(circle at 20% 20%, #1d3350 0%, var(--aws-dark) 60%);
    padding: 80px 24px 64px;
    text-align: center;
    border-bottom: 3px solid var(--aws-orange);
}

.hero-content {
    max-width: 960px;
    margin: 0 auto;
}

.badge {
    display: inline-block;
    background: var(--aws-orange);
    color: #14202e;
    font-weight: 700;
    letter-spacing: 1px;
    text-transform: uppercase;
    font-size: 0.8rem;
    padding: 6px 16px;
    border-radius: 999px;
    margin-bottom: 24px;
}

.hero h1 {
    font-size: 3.2rem;
    font-weight: 800;
    line-height: 1.1;
}

.hero h2 {
    font-size: 1.7rem;
    color: var(--aws-orange);
    margin-top: 8px;
    font-weight: 600;
}

.hero-sub {
    font-size: 1.2rem;
    color: var(--text-muted);
    margin-top: 12px;
}

.hero-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    justify-content: center;
    margin-top: 28px;
}

.tag {
    background: var(--aws-navy);
    border: 1px solid var(--border);
    color: var(--text);
    padding: 6px 14px;
    border-radius: 999px;
    font-size: 0.85rem;
}

/* NAVBAR */
.navbar {
    position: sticky;
    top: 0;
    z-index: 10;
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: center;
    background: rgba(15, 27, 45, 0.95);
    backdrop-filter: blur(8px);
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
}

.navbar a {
    color: var(--text-muted);
    text-decoration: none;
    font-size: 0.95rem;
    padding: 6px 12px;
    border-radius: 8px;
    transition: color 0.2s, background 0.2s;
}

.navbar a:hover {
    color: var(--text);
    background: var(--aws-navy);
}

/* MAIN / SECTIONS */
main {
    max-width: 980px;
    margin: 0 auto;
    padding: 24px 20px 64px;
}

.section {
    margin-top: 56px;
    scroll-margin-top: 80px;
}

.section-title {
    font-size: 1.8rem;
    margin-bottom: 20px;
    position: relative;
    padding-left: 16px;
}

.section-title::before {
    content: "";
    position: absolute;
    left: 0;
    top: 4px;
    bottom: 4px;
    width: 5px;
    background: var(--aws-orange);
    border-radius: 4px;
}

.card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 28px;
}

.card p {
    margin-bottom: 14px;
}

.card p:last-child {
    margin-bottom: 0;
}

.card ul {
    margin: 0 0 14px 20px;
}

.note {
    color: var(--text-muted);
    font-size: 0.92rem;
    border-left: 3px solid var(--aws-blue);
    padding-left: 14px;
    margin-top: 18px;
}

.highlight-box {
    background: rgba(32, 116, 213, 0.12);
    border: 1px solid var(--aws-blue);
    border-radius: var(--radius);
    padding: 18px;
    margin: 18px 0;
}

.highlight-box ul {
    margin: 8px 0 0 20px;
}

pre {
    background: #0b1420;
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px;
    overflow-x: auto;
    margin: 10px 0;
}

code {
    font-family: "Consolas", "Courier New", monospace;
    color: var(--aws-orange);
}

/* ENDPOINTS */
.endpoint-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 18px;
    margin: 20px 0;
}

.endpoint {
    border-radius: var(--radius);
    padding: 22px;
    text-align: center;
    border: 1px solid var(--border);
}

.endpoint-open {
    background: rgba(229, 72, 77, 0.08);
    border-color: var(--red);
}

.endpoint-protected {
    background: rgba(31, 171, 90, 0.08);
    border-color: var(--green);
}

.endpoint-icon {
    font-size: 2.4rem;
    margin-bottom: 8px;
}

.endpoint h3 {
    margin-bottom: 8px;
}

/* CARDS GRID (componentes) */
.cards-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 16px;
}

.mini-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
    text-align: center;
    transition: transform 0.15s, border-color 0.15s;
}

.mini-card:hover {
    transform: translateY(-3px);
    border-color: var(--aws-orange);
}

.mini-icon {
    font-size: 1.9rem;
    display: block;
    margin-bottom: 8px;
}

.mini-card h4 {
    color: var(--aws-orange);
    margin-bottom: 6px;
}

.mini-card p {
    font-size: 0.85rem;
    color: var(--text-muted);
}

/* ARQUITETURA */
.arch-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 18px;
}

.arch-card {
    text-align: center;
}

.arch-card h3 {
    margin-bottom: 18px;
    color: var(--aws-orange);
}

.arch-protected h3 {
    color: var(--green);
}

.flow {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
}

.flow-node {
    background: var(--aws-navy);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 18px;
    width: 100%;
    max-width: 240px;
    font-weight: 600;
}

.flow-waf {
    border-color: var(--aws-orange);
    color: var(--aws-orange);
}

.flow-ec2 {
    border-color: var(--aws-blue);
    color: var(--aws-blue);
}

.flow-arrow {
    color: var(--text-muted);
    font-size: 1.1rem;
}

/* TABELA RESULTADO */
.result-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 10px;
}

.result-table th,
.result-table td {
    padding: 14px 16px;
    text-align: left;
    border-bottom: 1px solid var(--border);
}

.result-table th {
    color: var(--aws-orange);
    text-transform: uppercase;
    font-size: 0.82rem;
    letter-spacing: 0.5px;
}

.status {
    display: inline-block;
    padding: 4px 12px;
    border-radius: 999px;
    font-weight: 700;
    font-size: 0.82rem;
}

.status-ok {
    background: rgba(31, 171, 90, 0.18);
    color: #4ade80;
}

.status-block {
    background: rgba(229, 72, 77, 0.18);
    color: #ff6b6b;
}

/* FOOTER */
.footer {
    text-align: center;
    padding: 32px 20px;
    border-top: 1px solid var(--border);
    color: var(--text-muted);
    font-size: 0.9rem;
}

.footer-sub {
    margin-top: 6px;
    font-size: 0.82rem;
}

/* RESPONSIVE */
@media (max-width: 720px) {
    .hero h1 {
        font-size: 2.3rem;
    }
    .hero h2 {
        font-size: 1.3rem;
    }
    .endpoint-grid,
    .arch-grid {
        grid-template-columns: 1fr;
    }
}
CSS

echo "==> Criando endpoint ${WEB_ROOT}/health ..."
cat > "${WEB_ROOT}/health" <<'JSON'
{
  "status": "healthy"
}
JSON

# Configura o Nginx para servir /health com Content-Type JSON e status 200.
echo "==> Configurando site do Nginx (server block) ..."
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    # Health check do Target Group -> retorna JSON com HTTP 200.
    location = /health {
        default_type application/json;
        try_files /health =200;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX

echo "==> Testando configuracao do Nginx ..."
nginx -t

echo "==> Habilitando e iniciando o Nginx ..."
systemctl enable nginx
systemctl restart nginx

echo "==> Concluido. Nginx ativo servindo /var/www/html."
echo "    - Site:   http://<host>/"
echo "    - Health: http://<host>/health  -> {\"status\": \"healthy\"}"
