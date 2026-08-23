[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$Kubeconfig = '/etc/rancher/k3s/k3s.yaml',
    [string]$Namespace = 'edge-llm',
    [int]$GatewayLocalPort = 18084,
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
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

    $json = (Invoke-Kubectl -KubectlArguments @('-n', $Namespace, 'get', 'pods', '-l', $Selector, '-o', 'json')) | Out-String
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

try {
    $gatewayBefore = Get-WorkloadState -Selector $gatewaySelector
    $inferenceBefore = Get-WorkloadState -Selector $inferenceSelector
    if (-not $gatewayBefore.Ready -or -not $inferenceBefore.Ready) {
        throw 'serving workloads are not Ready before the WSL restart test'
    }

    $portForwardProcess = Start-GatewayPortForward
    Wait-GatewayHealth -DeadlineSeconds 30
    Stop-Process -Id $portForwardProcess.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $portForwardProcess.Id -ErrorAction SilentlyContinue
    $portForwardProcess = $null

    $startedAt = [DateTimeOffset]::Now
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & wsl.exe --terminate $Distribution
    if ($LASTEXITCODE -ne 0) {
        throw "failed to terminate WSL distribution: $Distribution"
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $apiRecoveryMs = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $null = Invoke-Kubectl -KubectlArguments @('get', '--raw=/readyz')
            $apiRecoveryMs = $stopwatch.ElapsedMilliseconds
            break
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }
    if ($null -eq $apiRecoveryMs) {
        throw 'timed out waiting for the K3s API after WSL restart'
    }

    $workloadRecoveryMs = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $gatewayAfter = Get-WorkloadState -Selector $gatewaySelector
            $inferenceAfter = Get-WorkloadState -Selector $inferenceSelector
            $gatewayRestarted = $gatewayAfter.RestartCount -gt $gatewayBefore.RestartCount
            $inferenceRestarted = $inferenceAfter.RestartCount -gt $inferenceBefore.RestartCount
            if ($gatewayAfter.Ready -and $inferenceAfter.Ready -and
                $gatewayRestarted -and $inferenceRestarted) {
                $workloadRecoveryMs = $stopwatch.ElapsedMilliseconds
                break
            }
        }
        catch {
            # K3s and the kubelet can become available at different times.
        }
        Start-Sleep -Seconds 2
    }
    if ($null -eq $workloadRecoveryMs) {
        throw 'timed out waiting for the serving workloads after WSL restart'
    }

    $portForwardProcess = Start-GatewayPortForward
    Wait-GatewayHealth -DeadlineSeconds 120
    $healthRecoveryMs = $stopwatch.ElapsedMilliseconds

    [pscustomobject]@{
        Case                  = 'wsl-distribution-restart'
        StartedAt             = $startedAt.ToString('o')
        Distribution          = $Distribution
        K3sApiRecoveryMs      = $apiRecoveryMs
        WorkloadRecoveryMs    = $workloadRecoveryMs
        GatewayHealthMs       = $healthRecoveryMs
        GatewayPod            = $gatewayAfter.Pod
        GatewayRestartBefore  = $gatewayBefore.RestartCount
        GatewayRestartAfter   = $gatewayAfter.RestartCount
        InferencePod          = $inferenceAfter.Pod
        InferenceRestartBefore = $inferenceBefore.RestartCount
        InferenceRestartAfter = $inferenceAfter.RestartCount
    } | Format-List
}
finally {
    if ($null -ne $portForwardProcess -and -not $portForwardProcess.HasExited) {
        Stop-Process -Id $portForwardProcess.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $portForwardProcess.Id -ErrorAction SilentlyContinue
    }
}
