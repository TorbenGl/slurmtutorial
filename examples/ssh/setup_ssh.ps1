<#
Example 2a (Windows) — SSH setup on your laptop with Windows' built-in OpenSSH.
Run in PowerShell from the repo folder:

    powershell -ExecutionPolicy Bypass -File examples\ssh\setup_ssh.ps1 -User <your-uni-username>

Safe to run again — every step is skipped if it is already done:
  1. creates %USERPROFILE%\.ssh\id_ed25519 and loads it into the ssh-agent
  2. installs the public key on sl-li          (asks for your uni password once)
  3. adds a "Host slurm" block to .ssh\config, so `ssh slurm` just works
  4. tests the login and copies the public key to the clipboard for GitHub
#>
param([Parameter(Mandatory = $true)][string]$User)

$HostName = "sl-li.informatik.uni-rostock.de"
$Alias    = "slurm"
$SshDir   = Join-Path $env:USERPROFILE ".ssh"
$Key      = Join-Path $SshDir "id_ed25519"
$Config   = Join-Path $SshDir "config"

New-Item -ItemType Directory -Force -Path $SshDir | Out-Null

Write-Host "== 1/4  SSH key"
if (Test-Path $Key) {
    Write-Host "   exists: $Key"
} else {
    ssh-keygen -t ed25519 -C "$User@uni-rostock" -f $Key
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed" }
}

$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($null -eq $agent) {
    Write-Warning "OpenSSH client missing: Settings > Apps > Optional features > add 'OpenSSH Client'."
} elseif ($agent.Status -ne "Running") {
    Write-Warning ("ssh-agent is not running. Once, in an *Administrator* PowerShell:`n" +
                   "    Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent`n" +
                   "then run this script again.")
} else {
    $fingerprint = (ssh-keygen -lf "$Key.pub").Split(" ")[1]
    if ((ssh-add -l) -match [regex]::Escape($fingerprint)) {
        Write-Host "   already loaded in ssh-agent"
    } else {
        ssh-add $Key
    }
}

Write-Host "== 2/4  Public key on $HostName"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$User@$HostName" true
if ($LASTEXITCODE -eq 0) {
    Write-Host "   already accepted"
} else {
    Write-Host "   (the error above is expected the first time) enter your uni password:"
    # Windows has no ssh-copy-id: append the key by hand (tr strips Windows line endings).
    Get-Content "$Key.pub" | ssh "$User@$HostName" "umask 077; mkdir -p ~/.ssh; tr -d '\r' >> ~/.ssh/authorized_keys"
    if ($LASTEXITCODE -ne 0) { throw "copying the key to $HostName failed" }
}

Write-Host "== 3/4  'Host $Alias' in $Config"
$hasAlias = (Test-Path $Config) -and
            (Select-String -Path $Config -Pattern "^\s*Host\s+(.*\s)?$Alias(\s|$)" -Quiet)
if ($hasAlias) {
    Write-Host "   already there - left unchanged"
} else {
    $block = @"

Host $Alias
    HostName $HostName
    User $User
    IdentityFile ~/.ssh/id_ed25519
    AddKeysToAgent yes
    # Lends your laptop's key to the cluster (e.g. for git clone/push to
    # GitHub there) without copying the private key onto the cluster.
    ForwardAgent yes
    ServerAliveInterval 60
"@
    # .NET writes UTF-8 *without* BOM — OpenSSH can't parse a config with a BOM.
    [System.IO.File]::AppendAllText($Config, ($block -replace "`r`n", "`n") + "`n")
    Write-Host "   added"
}

Write-Host "== 4/4  Test"
ssh $Alias 'echo OK: logged in to $(hostname) as $(whoami)'

Get-Content "$Key.pub" | Set-Clipboard
Write-Host ""
Write-Host "Last step (once): add this PUBLIC key to GitHub (it is already in your clipboard)"
Write-Host "  -> https://github.com/settings/keys -> 'New SSH key'"
Write-Host ""
Get-Content "$Key.pub"
Write-Host ""
Write-Host "Check:  ssh -T git@github.com                  (on the laptop)"
Write-Host "        ssh slurm, then ssh -T git@github.com  (on the cluster, via agent forwarding)"
