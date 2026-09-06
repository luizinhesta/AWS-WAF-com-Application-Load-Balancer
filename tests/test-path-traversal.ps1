<#
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
      .\test-path-traversal.ps1 -UrlSemWaf "https://alb-sem-waf.dominio.com" -UrlComWaf "https://alb-com-waf.dominio.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$UrlSemWaf,

    [Parameter(Mandatory = $true)]
    [string]$UrlComWaf
)

# Padrao de Path Traversal usado somente contra os endpoints do laboratorio.
$TraversalPayload = "../../etc/passwd"
$TimeoutSec = 15

function Build-Url {
    param([string]$Base, [string]$Value)
    $Base = $Base.TrimEnd("/")
    $encoded = [System.Uri]::EscapeDataString($Value)
    return "$Base/?file=$encoded"
}

function Invoke-TestRequest {
    param([string]$Url)
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        return [int]$resp.StatusCode
    }
    catch {
        # 403 do WAF (esperado COM WAF) e 404 (chegou ao Nginx) caem aqui.
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            return [int]$_.Exception.Response.StatusCode.value__
        }
        Write-Host ("  ! Erro ao acessar {0}: {1}" -f $Url, $_.Exception.Message)
        return $null
    }
}

function Format-Normal {
    param([string]$Label, $Status)
    $dots = "." * ([Math]::Max(3, 28 - $Label.Length))
    if ($null -eq $Status) { return "  {0}{1}ERRO" -f $Label, $dots }
    return "  {0}{1}{2}" -f $Label, $dots, $Status
}

function Format-Traversal {
    param([string]$Label, $Status)
    $dots = "." * ([Math]::Max(3, 28 - $Label.Length))
    if ($null -eq $Status) { return "  {0}{1}ERRO" -f $Label, $dots }
    if ($Status -eq 403)   { return "  {0}{1}403 BLOCKED" -f $Label, $dots }
    return "  {0}{1}chegou ao servidor ({2})" -f $Label, $dots, $Status
}

function Invoke-Block {
    param([string]$Title, [string]$BaseUrl)
    Write-Host $Title
    $normal = Invoke-TestRequest (Build-Url -Base $BaseUrl -Value "relatorio.txt")
    $traversal = Invoke-TestRequest (Build-Url -Base $BaseUrl -Value $TraversalPayload)
    Write-Host (Format-Normal -Label "Normal" -Status $normal)
    Write-Host (Format-Traversal -Label "Path Traversal" -Status $traversal)
    Write-Host ""
}

Write-Host ("=" * 43)
Write-Host "AWS WAF LAB 02 - PATH TRAVERSAL"
Write-Host ("=" * 43)
Write-Host ""

Invoke-Block -Title "SEM WAF" -BaseUrl $UrlSemWaf
Invoke-Block -Title "COM WAF" -BaseUrl $UrlComWaf

Write-Host ("=" * 43)
