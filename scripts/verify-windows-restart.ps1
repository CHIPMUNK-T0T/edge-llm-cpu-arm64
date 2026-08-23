[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Prepare', 'Verify')]
    [string]$Mode,
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$Kubeconfig = '/etc/rancher/k3s/k3s.yaml',
    [string]$Namespace = 'edge-llm',
    [int]$GatewayLocalPort = 18085,
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$stateDirectory = Join-Path $repoRoot '.internal'
$stateFile = Join-Path $stateDirectory 'windows-restart-baseline.json'
$gatewaySelector = 'app.kubernetes.io/instance=inference-gateway,app.kubernetes.io/name=inference-gateway'
$inferenceSelector = 'app.kubernetes.io/instance=north-mini-code,app.kubernetes.io/name=north-mini-code'
$portForwardProcess = $null

function Invoke-Kubectl {
    param([string[]]$KubectlArguments)

    $output = & wsl.exe -d $Distribution -- kubectl --kubeconfig $Kubeconfig @KubectlArguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl failed: $($KubectlArguments -join ' ')"
    }
    return $output
}

function Get-WorkloadState {
    param([string]$Selector)

    $json = (Invoke-Kubectl -KubectlArguments @(
        '-n', $Namespace, 'get', 'pods', '-l', $Selector, '-o', 'json'
    )) | Out-String
    $items = @((ConvertFrom-Json $json).items)
    if ($items.Count -ne 1) {
        return [pscustomobject]@{ Ready = $false; RestartCount = -1; Pod = '' }
    }

    $pod = $items[0]
    $ready = @($pod.status.conditions | Where-Object {
        $_.type -eq 'Ready' -and $_.status -eq 'True'
    }).Count -eq 1
    $restartCount = ($pod.status.containerStatuses | Measure-Object -Property restartCount -Sum).Sum
    return [pscustomobject]@{
        Ready        = $ready
        RestartCount = [int]$restartCount
        Pod          = $pod.metadata.name
    }
}

function Start-GatewayPortForward {
    if (Get-NetTCPConnection -LocalPort $GatewayLocalPort -State Listen -ErrorAction SilentlyContinue) {
        throw "localhost port $GatewayLocalPort is already in use"
    }
    $arguments = @(
        '-d', $Distribution, '--', 'kubectl', '--kubeconfig', $Kubeconfig,
        '-n', $Namespace, 'port-forward', 'service/inference-gateway',
        "${GatewayLocalPort}:8080", '--address', '127.0.0.1'
    )
    return Start-Process -FilePath wsl.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
}

function Wait-GatewayHealth {
    param([int]$DeadlineSeconds)

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($DeadlineSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing `
                -Uri "http://127.0.0.1:${GatewayLocalPort}/health" -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }
    throw 'timed out waiting for Gateway health'
}

function Stop-GatewayPortForward {
    if ($null -ne $script:portForwardProcess -and -not $script:portForwardProcess.HasExited) {
        Stop-Process -Id $script:portForwardProcess.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $script:portForwardProcess.Id -ErrorAction SilentlyContinue
    }
    $script:portForwardProcess = $null
}

try {
    if ($Mode -eq 'Prepare') {
        $gateway = Get-WorkloadState -Selector $gatewaySelector
        $inference = Get-WorkloadState -Selector $inferenceSelector
        if (-not $gateway.Ready -or -not $inference.Ready) {
            throw 'serving workloads are not Ready before the Windows restart test'
        }

        $portForwardProcess = Start-GatewayPortForward
        Wait-GatewayHealth -DeadlineSeconds 30
        Stop-GatewayPortForward

        New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
        $os = Get-CimInstance Win32_OperatingSystem
        [pscustomobject]@{
            CapturedAt               = [DateTimeOffset]::Now.ToString('o')
            WindowsBootTime          = ([DateTimeOffset]$os.LastBootUpTime).ToString('o')
            GatewayRestartCount      = $gateway.RestartCount
            InferenceRestartCount    = $inference.RestartCount
        } | ConvertTo-Json | Set-Content -Encoding utf8 $stateFile

        Write-Output 'Baseline recorded. Restart Windows, then run:'
        Write-Output '  pwsh -File scripts/verify-windows-restart.ps1 -Mode Verify'
        return
    }

    if (-not (Test-Path -LiteralPath $stateFile)) {
        throw 'restart baseline is missing; run with -Mode Prepare before rebooting'
    }
    $baseline = Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
    $os = Get-CimInstance Win32_OperatingSystem
    $currentBootTime = [DateTimeOffset]$os.LastBootUpTime
    if ($currentBootTime -le [DateTimeOffset]$baseline.WindowsBootTime) {
        throw 'Windows boot time did not change; the requested reboot is not proven'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $apiReadyMs = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $null = Invoke-Kubectl -KubectlArguments @('get', '--raw=/readyz')
            $apiReadyMs = $stopwatch.ElapsedMilliseconds
            break
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }
    if ($null -eq $apiReadyMs) {
        throw 'timed out waiting for the K3s API after Windows restart'
    }

    $workloadsReadyMs = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $gateway = Get-WorkloadState -Selector $gatewaySelector
            $inference = Get-WorkloadState -Selector $inferenceSelector
            if ($gateway.Ready -and $inference.Ready -and
                $gateway.RestartCount -gt [int]$baseline.GatewayRestartCount -and
                $inference.RestartCount -gt [int]$baseline.InferenceRestartCount) {
                $workloadsReadyMs = $stopwatch.ElapsedMilliseconds
                break
            }
        }
        catch {
            # WSL and K3s can become available at different times after login.
        }
        Start-Sleep -Seconds 2
    }
    if ($null -eq $workloadsReadyMs) {
        throw 'timed out waiting for serving workloads after Windows restart'
    }

    $portForwardProcess = Start-GatewayPortForward
    Wait-GatewayHealth -DeadlineSeconds 120
    $healthReadyMs = $stopwatch.ElapsedMilliseconds
    $bootToObservationMs = [int64]([DateTimeOffset]::Now - $currentBootTime).TotalMilliseconds

    [pscustomobject]@{
        Case                         = 'windows-restart'
        WindowsBootTime              = $currentBootTime.ToString('o')
        VerificationStartToK3sApiMs  = $apiReadyMs
        VerificationStartToPodsMs    = $workloadsReadyMs
        VerificationStartToHealthMs  = $healthReadyMs
        BootToHealthObservationMs    = $bootToObservationMs
        GatewayRestartBefore         = [int]$baseline.GatewayRestartCount
        GatewayRestartAfter          = $gateway.RestartCount
        InferenceRestartBefore       = [int]$baseline.InferenceRestartCount
        InferenceRestartAfter        = $inference.RestartCount
    } | Format-List

    Remove-Item -LiteralPath $stateFile -Force
}
finally {
    Stop-GatewayPortForward
}
