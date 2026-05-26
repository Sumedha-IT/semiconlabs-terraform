# Renders user-data.sh.tftpl via Terraform (no AWS credentials required).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $Root "user-data.sh.tftpl"))) {
  $Root = Split-Path -Parent $PSScriptRoot
}
Set-Location $Root
terraform init -input=false | Out-Null
terraform validate -no-color
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$tfVars = @('-var=suffix=ci', '-var=instance_name=ci')
$rawLen = 'length(local.ci_user_data_rendered)' | terraform console @tfVars 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error $rawLen; exit $LASTEXITCODE }
$b64Out = 'base64gzip(local.ci_user_data_rendered)' | terraform console @tfVars 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error $b64Out; exit $LASTEXITCODE }
$b64 = $b64Out.Trim().Trim('"')
$gzipBytes = [Convert]::FromBase64String($b64).Length
$max = 16384
Write-Host "user-data.sh.tftpl OK (uncompressed $($rawLen.Trim()) bytes, gzip payload $gzipBytes bytes)"
if ($gzipBytes -gt $max) {
  Write-Error "gzip payload $gzipBytes exceeds EC2 limit $max - enable S3 split or shrink user-data.sh.tftpl"
  exit 1
}
exit 0
