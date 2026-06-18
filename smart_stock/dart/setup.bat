@echo off
chcp 65001 >nul 2>&1
echo ============================================
echo   端云协同智能炒股分析系统 - Flutter 初始化
echo ============================================
echo.

where flutter >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 Flutter SDK，请先安装 Flutter 并添加到 PATH
    echo   下载地址: https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

echo [1/4] 备份现有文件...
if exist "lib\main.dart" (
    copy "lib\main.dart" "lib\main.dart.bak" >nul 2>&1
)
if exist "pubspec.yaml" (
    copy "pubspec.yaml" "pubspec.yaml.bak" >nul 2>&1
)

echo [2/4] 初始化 Flutter 工程...
flutter create .

echo [3/4] 恢复业务代码...
if exist "lib\main.dart.bak" (
    copy /y "lib\main.dart.bak" "lib\main.dart" >nul 2>&1
    del "lib\main.dart.bak" >nul 2>&1
)
if exist "pubspec.yaml.bak" (
    copy /y "pubspec.yaml.bak" "pubspec.yaml" >nul 2>&1
    del "pubspec.yaml.bak" >nul 2>&1
)

echo [4/4] 安装依赖...
flutter pub get

echo.
echo ============================================
echo   初始化完成！
echo   运行方式: flutter run
echo ============================================
pause
