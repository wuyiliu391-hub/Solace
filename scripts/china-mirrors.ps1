$ErrorActionPreference = 'Stop'

# Flutter/Pub 镜像由 Flutter 工具通过环境变量读取。
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

# 当前用户后续新终端也使用国内镜像。
[Environment]::SetEnvironmentVariable('PUB_HOSTED_URL', $env:PUB_HOSTED_URL, 'User')
[Environment]::SetEnvironmentVariable('FLUTTER_STORAGE_BASE_URL', $env:FLUTTER_STORAGE_BASE_URL, 'User')

Write-Host "PUB_HOSTED_URL=$env:PUB_HOSTED_URL"
Write-Host "FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL"
Write-Host 'Gradle: Aliyun/Tencent mirrors configured in android/settings.gradle and android/build.gradle'
Write-Host 'npm: npmmirror configured in .npmrc'
