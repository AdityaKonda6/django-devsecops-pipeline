# -----------------------------
# CONFIG
# -----------------------------
$imageName = "helloworld-web:latest"
$templateFile = "trivy-html.tpl"
$reportFile = "trivy-report.html"

# -----------------------------
# STEP 1 — Run Trivy Scan (HTML output)
# -----------------------------
Write-Host "Running Trivy Scan on image: $imageName ..." -ForegroundColor Cyan

docker run --rm `
  -v //var/run/docker.sock:/var/run/docker.sock `
  -v "${PWD}:/report" `
  aquasec/trivy:latest `
  image --exit-code 1 `
  --severity HIGH,CRITICAL `
  --format template `
  --template "@/report/$templateFile" `
  -o "/report/$reportFile" `
  $imageName

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌  HIGH/CRITICAL vulnerabilities found! Aborting compose up." -ForegroundColor Red
    Write-Host "📄  Check the HTML report: $reportFile"
    exit 1
}

Write-Host "✅  Trivy scan passed — no HIGH/CRITICAL vulnerabilities found." -ForegroundColor Green
Write-Host "📄  HTML Report saved at: $reportFile" -ForegroundColor Green

# -----------------------------
# STEP 2 — Run docker-compose 
# -----------------------------
Write-Host "Starting docker-compose up -d ..." -ForegroundColor Cyan
docker-compose up -d

Write-Host "🎉 DONE — Containers are up and running." -ForegroundColor Green
