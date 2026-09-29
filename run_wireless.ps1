param(
    [switch]$ReleaseMode
)

# ==============================================================================
# EmoHeal - 1-Click Wireless Phone Live Monitor & Auto-Reload Runner
# ==============================================================================
$Host.UI.RawUI.WindowTitle = "EmoHeal - Wireless Runner (All Logs + Auto Hot-Reload)"

# 0. Khoi tao he thong ghi nhat ky & Tu dong lam sach log cu (Fresh Session)
$logDir = Join-Path $PSScriptRoot "logs"
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

# Don sach log cu de phien chay moi co log sach cho AI fix bug
$logFilesToReset = @("wireless_runner.log", "backend.log", "flutter_app.log", "phone_client_errors.log", "PENDING_AI_FIX.md")
foreach ($f in $logFilesToReset) {
    $targetFile = Join-Path $logDir $f
    if (Test-Path $targetFile) {
        try {
            Set-Content -Path $targetFile -Value "" -Encoding UTF8 -Force
        } catch {}
    }
}

$logFile = Join-Path $logDir "wireless_runner.log"

function Write-Log {
    param([string]$message, [string]$color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $formatted = "[$timestamp] $message"
    Write-Host $formatted -ForegroundColor $color
    
    try {
        $fs = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$formatted`r`n")
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Close()
    } catch {}
}

function Log-Raw {
    param([string]$rawText)
    try {
        $fs = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$rawText`r`n")
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Close()
    } catch {}
}

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  EMOHEAL 'VÒNG TAY THẤU CẢM' - GIÁM SÁT TOÀN BỘ LOG & TỰ ĐỘNG CẬP NHẬT CODE KHÔNG DÂY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Thiet lap moi truong tren o E:
Write-Log "[BƯỚC 1/3] Kiểm tra & Cấu hình môi trường SDK trên ổ E:..." "Yellow"

$sdkPath        = "E:\AndroidSDK"
$platformToolsE = "E:\platform-tools"
$gradleDir      = "E:\.gradle"
$androidDir     = "E:\.android"
$pubCacheDir    = "E:\.pub-cache"
$tempDir        = "E:\.temp"
$flutterBin     = "E:\flutter\bin"

foreach ($dir in @($gradleDir, $androidDir, $pubCacheDir, $tempDir, $sdkPath, $platformToolsE)) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

$jdk21 = "C:\Program Files\Java\jdk-21"
if (Test-Path $jdk21) {
    $env:JAVA_HOME = $jdk21
    $env:Path = "$jdk21\bin;$env:Path"
}

$env:GRADLE_USER_HOME = $gradleDir
$env:ANDROID_USER_HOME = $androidDir
$env:PUB_CACHE = $pubCacheDir
$env:TEMP = $tempDir
$env:TMP = $tempDir
$env:_JAVA_OPTIONS = "-Djava.io.tmpdir=$tempDir"
$env:ANDROID_HOME = $sdkPath
$env:ANDROID_SDK_ROOT = $sdkPath

$effectiveAdb = if (Test-Path "$platformToolsE\adb.exe") { "$platformToolsE\adb.exe" } elseif (Test-Path "C:\platform-tools\adb.exe") { "C:\platform-tools\adb.exe" } else { "adb" }
$effectiveFlutter = if (Test-Path "$flutterBin\flutter.bat") { "$flutterBin\flutter.bat" } else { "flutter" }

if ($env:Path -notlike "*$platformToolsE*") {
    $env:Path = "$platformToolsE;C:\platform-tools;$sdkPath\platform-tools;$env:Path"
}
if ($env:Path -notlike "*$flutterBin*") {
    $env:Path = "$flutterBin;$env:Path"
}

Write-Log "   * Android SDK   : $sdkPath" "Gray"
Write-Log "   * Gradle Cache  : $gradleDir" "Gray"
Write-Log "   * Bộ đệm Temp   : $tempDir" "Gray"
Write-Log "   * Flutter Bin   : $effectiveFlutter" "Gray"

# Kiem tra va tu dong khoi dong Local Maven Cache Server
$proxyRunning = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect("127.0.0.1", 8899, $null, $null)
    $success = $iar.AsyncWaitHandle.WaitOne(500)
    if ($success) {
        $tcp.EndConnect($iar)
        $proxyRunning = $true
    }
    $tcp.Close()
} catch {}

if (!$proxyRunning) {
    $serverScript = Join-Path $PSScriptRoot "tool\local_maven_server.py"
    if (Test-Path $serverScript) {
        Start-Process -FilePath "python" -ArgumentList "`"$serverScript`"" -WindowStyle Hidden
        Write-Log "   * Maven Cache   : Đã bật máy chủ tăng tốc cục bộ (Port 8899)" "Gray"
    }
} else {
    Write-Log "   * Maven Cache   : Máy chủ tăng tốc cục bộ đang hoạt động (Port 8899)" "Gray"
}

# Kiem tra va tu dong khoi dong Backend FastAPI (Port 8000)
$backendRunning = $false
try {
    $tcp8000 = New-Object System.Net.Sockets.TcpClient
    $iar8000 = $tcp8000.BeginConnect("127.0.0.1", 8000, $null, $null)
    $success8000 = $iar8000.AsyncWaitHandle.WaitOne(500)
    if ($success8000) {
        $tcp8000.EndConnect($iar8000)
        $backendRunning = $true
    }
    $tcp8000.Close()
} catch {}

if (!$backendRunning) {
    $backendDir = Join-Path $PSScriptRoot "backend"
    Start-Process -FilePath "python" -ArgumentList "-m uvicorn main:app --host 0.0.0.0 --port 8000" -WorkingDirectory $backendDir -WindowStyle Hidden
    Write-Log "   * Backend FastAPI: Đã tự động khởi động máy chủ AI Voice & Auth (Port 8000)" "Green"
} else {
    Write-Log "   * Backend FastAPI: Máy chủ AI Voice & Auth đang hoạt động (Port 8000)" "Green"
}

# Cau hinh Android SDK vao Flutter
& $effectiveFlutter config --android-sdk "$sdkPath" 2>&1 | Out-Null

$keepRunningSession = $true

do {
    # 2. Tu dong do tim va ket noi dien thoai khong day
    Write-Host ""
    Write-Log "[BƯỚC 2/3] Quét & Tự động kết nối Wi-Fi ADB với điện thoại..." "Yellow"

    $lastDeviceFile = Join-Path $logDir "last_device.txt"

    # Thu ket noi thiet bi da tung luu truoc do
    if (Test-Path $lastDeviceFile) {
        $savedDevice = (Get-Content $lastDeviceFile -Raw).Trim()
        if (![string]::IsNullOrWhiteSpace($savedDevice)) {
            Write-Log "   -> Đang thử kết nối lại thiết bị cũ: $savedDevice..." "Gray"
            & $effectiveAdb connect $savedDevice 2>&1 | Out-Null
        }
    }

    $currentDevices = & $effectiveAdb devices -l
    Log-Raw "[ADB DEVICES]`r`n$currentDevices"

    $connectedDevice = $null
    $connectedDeviceName = "Android Device"

    foreach ($line in ($currentDevices -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^([^\s]+)\s+device\b') {
            $connectedDevice = $matches[1]
            if ($trimmed -match 'model:([^\s]+)') {
                $connectedDeviceName = $matches[1]
            }
            break
        }
    }

    if ($connectedDevice) {
        Write-Log "   -> [OK] Đã nhận diện điện thoại: $connectedDeviceName ($connectedDevice)" "Green"
        $targetDevice = $connectedDevice
        try { [System.IO.File]::WriteAllText($lastDeviceFile, $targetDevice) } catch {}
    } else {
        Write-Log "   -> [!] Chưa thấy thiết bị kết nối. Hướng dẫn kết nối nhanh:" "Yellow"
        Write-Host "   -------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "    1. Trên điện thoại: Vào Cài đặt -> Tùy chọn nhà phát triển" -ForegroundColor White
        Write-Host "    2. Bật 'Gỡ lỗi không dây' (Wireless Debugging)" -ForegroundColor White
        Write-Host "    3. Xem 'Địa chỉ IP và cổng' (Ví dụ: 192.168.1.5:43009)" -ForegroundColor White
        Write-Host "   -------------------------------------------------------------------------" -ForegroundColor DarkGray
        
        $userInput = Read-Host "   -> Nhập IP:Port (hoặc 'q' để thoát)"
        if ([string]::IsNullOrWhiteSpace($userInput) -or $userInput -eq "q") {
            Write-Log "   -> Dừng tiến trình!" "Yellow"
            break
        }
        
        if ($userInput -notlike "*:*") {
            $userInput = "$userInput`:5555"
        }
        
        Write-Log "   -> Đang kết nối ADB đến $userInput..." "Yellow"
        $connectOut = & $effectiveAdb connect $userInput
        Write-Log "   -> Kết quả: $connectOut" "White"
        Start-Sleep -Seconds 1
        $targetDevice = $userInput
        try { [System.IO.File]::WriteAllText($lastDeviceFile, $targetDevice) } catch {}
    }

    # Thiet lap ADB Reverse Port de chuyen tiep cong 8000 tu dien thoai ve may tinh
    try {
        & $effectiveAdb -s $targetDevice reverse tcp:8000 tcp:8000 2>&1 | Out-Null
        Write-Log "   -> [OK] Đã thông cầu mạng ADB Reverse: Điện thoại -> PC (Port 8000)" "Green"
    } catch {}

    # Thu thap thong tin chi tiet ve dien thoai & Kich hoat che do Giu sang man hinh (Keep Awake)
    try {
        $modelProp = (& $effectiveAdb -s $targetDevice shell getprop ro.product.model 2>$null).Trim()
        $versionProp = (& $effectiveAdb -s $targetDevice shell getprop ro.build.version.release 2>$null).Trim()
        $sdkProp = (& $effectiveAdb -s $targetDevice shell getprop ro.build.version.sdk 2>$null).Trim()
        $abiProp = (& $effectiveAdb -s $targetDevice shell getprop ro.product.cpu.abi 2>$null).Trim()
        if ($modelProp) {
            Write-Log "   -> Thiết bị: $modelProp | Android $versionProp (API $sdkProp) | CPU: $abiProp" "Cyan"
        }

        # Kích hoạt chế độ giữ sáng màn hình khi cắm sạc / gỡ lỗi để chống ColorOS / Android tự ngắt Wi-Fi
        & $effectiveAdb -s $targetDevice shell svc power stayon 'true' 2>&1 | Out-Null
        Write-Log "   -> [OK] Đã kích hoạt chế độ Giữ sáng màn hình (chống ColorOS/Android tự ngắt Wi-Fi ADB)" "Green"


    } catch {}

    # 3. Build va Chay ung dung truc tiep - Hien thi 100% TAT CA CAC LOG & Tu dong Hot Reload
    Write-Host ""
    Write-Log "[BƯỚC 3/3] Khởi động Build & Giám sát TẤT CẢ LOG thời gian thực..." "Yellow"
    Write-Host ""
    if ($ReleaseMode) {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "  🚀 CHẾ ĐỘ RELEASE (HIỆU NĂNG TỐI ĐA):                                          " -ForegroundColor Cyan
        Write-Host "  * Ứng dụng sẽ được biên dịch AOT, chạy siêu mượt (60/120 FPS).               " -ForegroundColor Green
        Write-Host "  * Vô hiệu hóa Hot-Reload để đạt hiệu năng thật trên thiết bị.                " -ForegroundColor Yellow
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "  👉 [LƯU Ý TRÊN ĐIỆN THOẠI]:                                                   " -ForegroundColor Yellow
        Write-Host "  * Màn hình điện thoại sẽ luôn được giữ sáng để duy trì kết nối Wi-Fi ổn định. " -ForegroundColor White
        Write-Host "  * Nếu điện thoại hiện hộp thoại 'Cho phép cài đặt?' -> Bấm [Cho phép/Cài đặt]" -ForegroundColor Green
        Write-Host "================================================================================" -ForegroundColor Cyan
    } else {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "  TÍNH NĂNG TỰ ĐỘNG NẠP CODE (AUTO HOT-RELOAD ENABLED):                        " -ForegroundColor Cyan
        Write-Host "  * Bạn chỉ cần sửa code và bấm Save (Ctrl + S) trong VS Code / IDE.           " -ForegroundColor Green
        Write-Host "  * Hệ thống sẽ tự động phát hiện thay đổi và nạp ngay lên điện thoại (1 giây) " -ForegroundColor Green
        Write-Host "  * Phím tắt thủ công: [r] Reload | [R] Restart | [q] Thoát                    " -ForegroundColor Gray
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "  👉 [LƯU Ý TRÊN ĐIỆN THOẠI]:                                                   " -ForegroundColor Yellow
        Write-Host "  * Màn hình điện thoại sẽ luôn được giữ sáng để duy trì kết nối Wi-Fi ổn định. " -ForegroundColor White
        Write-Host "  * Nếu điện thoại hiện hộp thoại 'Cho phép cài đặt?' -> Bấm [Cho phép/Cài đặt]" -ForegroundColor Green
        Write-Host "================================================================================" -ForegroundColor Cyan
    }
    Write-Host ""

    Log-Raw "`r`n[RUN START] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $targetDevice`r`n"

    $buildStartTime = Get-Date

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $effectiveFlutter
    $baseArgs = "run -d $targetDevice --no-pub --android-skip-build-dependency-validation --dart-define=BACKEND_URL=http://127.0.0.1:8000"
    if ($ReleaseMode) {
        $psi.Arguments = "$baseArgs --release"
    } else {
        $psi.Arguments = $baseArgs
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $false

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $global:lastLogTime = Get-Date
    $global:hasLostConnection = $false

    $proc.Start() | Out-Null

    $watcher = $null
    if (!$ReleaseMode) {
        $watchPath = Join-Path $PSScriptRoot "lib"
        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $watchPath
        $watcher.Filter = "*.dart"
        $watcher.IncludeSubdirectories = $true
        $watcher.EnableRaisingEvents = $true

        $global:lastReloadTime = [DateTime]::MinValue

        $fileChangeAction = {
            param($sender, $e)
            $now = Get-Date
            # Debounce 600ms tranh trigger nhieu lan khi save
            if (($now - $global:lastReloadTime).TotalMilliseconds -gt 600) {
                $global:lastReloadTime = $now
                $changedFile = $e.Name
                Write-Host ""
                Write-Host "[$($now.ToString('HH:mm:ss'))] [⚡ AUTO HOT-RELOAD] Đã phát hiện thay đổi: $changedFile -> Đang cập nhật lên điện thoại..." -ForegroundColor Cyan
                try {
                    $proc.StandardInput.WriteLine("r")
                } catch {}
            }
        }

        $watchEvent1 = Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $fileChangeAction
        $watchEvent2 = Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $fileChangeAction
        $watchEvent3 = Register-ObjectEvent -InputObject $watcher -EventName "Renamed" -Action $fileChangeAction
    }

    # Vong lap chuyen tiep ban phim tu nguoi dung 
    try {
        while (!$proc.HasExited) {
            try {
                if ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    try {
                        $proc.StandardInput.Write($k.KeyChar)
                    } catch {}
                }
            } catch {}
            Start-Sleep -Milliseconds 100
        }
    } finally {
        if ($watcher) {
            $watcher.EnableRaisingEvents = $false
            $watcher.Dispose()
            Unregister-Event -SourceIdentifier $watchEvent1.Name -ErrorAction SilentlyContinue
            Unregister-Event -SourceIdentifier $watchEvent2.Name -ErrorAction SilentlyContinue
            Unregister-Event -SourceIdentifier $watchEvent3.Name -ErrorAction SilentlyContinue
        }
    }

    $proc.WaitForExit()

    $elapsed = (Get-Date) - $buildStartTime
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "  Phiên chạy kết thúc (Thời gian: $($elapsed.Minutes)m $($elapsed.Seconds)s)." -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Log "Phien tam dung luc $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "Green"

    if ($global:hasLostConnection) {
        Write-Host ""
        Write-Host "================================================================================" -ForegroundColor Red
        Write-Host "  ⚠️ ĐÃ MẤT KẾT NỐI WI-FI ADB VỚI ĐIỆN THOẠI (Lost connection to device)" -ForegroundColor Red
        Write-Host "  👉 Nguyên nhân: Màn hình điện thoại vừa tắt/khóa, hoặc Wi-Fi bị gián đoạn." -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Red
        Write-Host "  [Enter / 1] Thử kết nối lại ngay lập tức" -ForegroundColor Green
        Write-Host "  [2]         Nhập IP:Port mới từ điện thoại" -ForegroundColor Cyan
        Write-Host "  [q / 0]     Thoát" -ForegroundColor Gray
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
        $recoveryChoice = Read-Host "  -> Lựa chọn của bạn"
        if ($recoveryChoice -eq "q" -or $recoveryChoice -eq "0") {
            $keepRunningSession = $false
        } elseif ($recoveryChoice -eq "2") {
            if (Test-Path $lastDeviceFile) { Remove-Item $lastDeviceFile -Force }
            $keepRunningSession = $true
        } else {
            $keepRunningSession = $true
        }
    } else {
        $keepRunningSession = $false
    }
} while ($keepRunningSession)
