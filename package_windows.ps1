param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"

$Script = Join-Path $PSScriptRoot "scripts/package_windows.ps1"
if (Test-Path $Script) {
    & $Script -Configuration $Configuration -Runtime $Runtime
    exit $LASTEXITCODE
}

$Project = Join-Path $PSScriptRoot "windows/Huyi.Windows/Huyi.Windows.csproj"
if (-not (Test-Path $Project)) {
    throw "找不到 windows/Huyi.Windows/Huyi.Windows.csproj。请确认 Huyi.Windows 文件夹和 package_windows.ps1 在同一个虎译项目目录下。"
}

$PublishDir = Join-Path $PSScriptRoot "dist/Huyi-Windows-Portable"
$ZipPath = Join-Path $PSScriptRoot "dist/Huyi-Windows-Portable.zip"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet SDK 未安装。请在 Windows 10/11 x64 机器上安装 .NET 8 SDK 后再运行。"
}

if (Test-Path $PublishDir) {
    Remove-Item $PublishDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PublishDir | Out-Null

dotnet publish $Project `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=false `
    -p:PublishReadyToRun=false `
    -o $PublishDir

$Readme = @"
虎译 Windows Portable

运行方式：
1. 启动 LM Studio，并开启 OpenAI-compatible local server。
2. 默认地址：http://127.0.0.1:1234/v1
3. 双击 Huyi.exe。

默认快捷键：
- F4：截图翻译
- F1：截图
- F5：输入翻译

注意：
- OCR 使用 Windows 内置 OCR。若识别不可用，请在 Windows 设置中安装英文/中文语言和 OCR 能力。
- 设置保存在当前用户 AppData\Roaming\Huyi\settings.json。
- 这是便携目录，不需要安装器。
"@
Set-Content -Path (Join-Path $PublishDir "README.txt") -Value $Readme -Encoding UTF8

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Compress-Archive -Path (Join-Path $PublishDir "*") -DestinationPath $ZipPath

Write-Host "Done."
Write-Host "Portable dir: $PublishDir"
Write-Host "Zip: $ZipPath"
