$QT_INSTALL_DIR = "C:\Qt"
$QT_ROOT_URL = 'https://download.qt.io/online/qtsdkrepository/windows_x86/desktop'

$TOOL_IDS = @(
    "vcredist"
    "telemetry"
    "qtcreator"
    "qt3dstudio_runtime_240"
    "qt3dstudio_runtime_230"
    "qt3dstudio_runtime_220"
    "qt3dstudio_runtime_210"
    "qt3dstudio_runtime"
    "qt3dstudio_openglruntime_250"
    "qt3dstudio_openglruntime_240"
    "qt3dstudio"
    "openssl_x86"
    "openssl_x64"
    "openssl_src"
    "mingw"
    "maintenance_update_reminder"
    "maintenance"
    "ifw"
    "generic"
    "cmake"
)

$package_updates = @{}
$feeds_cache = @{}

function GetVersionId($version) {
    return $version.replace('.', '')
}

function GetReleaseRootUrl($version) {
    return "$QT_ROOT_URL/qt5_$(GetVersionId $version)"
}

function FetchToolsUpdatePackages($toolsId) {
    FetchUpdatePackages "$QT_ROOT_URL/tools_$toolsId"
}

function FetchReleaseUpdatePackages($version) {
    FetchUpdatePackages "$(GetReleaseRootUrl $version)"
    FetchUpdatePackages "$(GetReleaseRootUrl $version)_src_doc_examples"
}

function SplitString($str) {
    $arr = @()
    if ($str) {
        foreach($item in $str.split(',')) {
            $arr += $item.trim()
        }
    }
    return $arr
}

function FetchUpdatePackages($feedRootUrl) {
    $feedUrl = "$feedRootUrl/Updates.xml"
    if (-not $feeds_cache.ContainsKey($feedUrl)) {
        # load xml
        Write-Host "Fetching $feedUrl..." -NoNewline -ForegroundColor Gray
        $feedXml = [xml](New-Object Net.WebClient).DownloadString($feedUrl)
        $feeds_cache[$feedUrl] = $feedXml

        # index 'PackageUpdate' nodes
        $totalPackages = 0
        foreach($packageNode in $feedXml.Updates.PackageUpdate) {

            $package = @{
                BaseUrl = $feedRootUrl
                Name = $packageNode.Name
                DisplayName = $packageNode.DisplayName
                Version = $packageNode.Version
                Dependencies = SplitString $packageNode.Dependencies
                DownloadableArchives = SplitString $packageNode.DownloadableArchives
                Installed = $false
            }

            $package_updates[$package.Name] = $package
            $totalPackages++
        }
        Write-Host "$totalPackages"
    }
}

function Install-QtComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        $Version,
        [Parameter(Mandatory=$false)]
        $Name,
        [Parameter(Mandatory=$false)]
        $Id,
        [Parameter(Mandatory=$false)]
        $Path,
        [switch]$whatIf,
        [switch]$excludeDocs,
        [switch]$excludeExamples
    )

    if ($Version -and $Name) {
        FetchReleaseUpdatePackages $version
        InstallComponentById "qt.qt5.$(GetVersionId $version).$Name" $Path -whatif:$whatIf -excludeDocs:$excludeDocs -excludeExamples:$excludeExamples
    } elseif ($Id) {
        InstallComponentById $Id $Path -whatif:$whatIf -excludeDocs:$excludeDocs -excludeExamples:$excludeExamples
    } else {
        throw "Either -Version and -Name should be specified or -Id."
    }
}

function InstallComponentById {
    param(
        $componentId,
        $destPath,
        [switch]$whatIf,
        [switch]$excludeDocs,
        [switch]$excludeExamples
    )

    Write-Host "Installing $componentId" -ForegroundColor Cyan

    $comp = $package_updates[$componentId]

    # if ($whatIf -eq $true) {
    #     $comp
    # }

    if (-not $destPath) {
        $destPath = $QT_INSTALL_DIR
    }

    if ($comp.Installed) {
        Write-Host "Already installed" -ForegroundColor Yellow
        return
    }    

    if ($excludeDocs -eq $true -and $componentId.EndsWith('.doc')) {
        Write-Host "Skipped documentation installation" -ForegroundColor Yellow
        return
    }
    if ($excludeExamples -eq $true  -and $componentId.EndsWith('.examples')) {
        Write-Host "Skipped examples installation" -ForegroundColor Yellow
        return
    }

    # download and extract component archives
    foreach($downloadableArchive in $comp.DownloadableArchives) {
        $fileName = "$($comp.Version)$downloadableArchive"
        $downloadUrl = "$($comp.BaseUrl)/$($comp.Name)/$fileName"
        $sha1 = (New-Object Net.WebClient).DownloadString("$downloadUrl.sha1")

        $tempDir = "$env:TEMP\qt5-installer-temp"
        New-Item $tempDir -ItemType Directory -Force | Out-Null

        Write-Host "$($comp.Name)/$fileName - Downloading..." -NoNewline
        $tempFileName = "$tempDir\$fileName"
        (New-Object Net.WebClient).DownloadFile($downloadUrl, $tempFileName)
        $downloadedSha1 = (Get-FileHash -Algorithm SHA1 $tempFileName).Hash.ToLowerInvariant()

        if ($sha1 -ne $downloadedSha1) {
            throw "SHA1 hashes don't match for $downloadUrl ($sha1) and $tempFileName ($downloadedSha1)"
        }

        Write-Host "Extracting..." -NoNewline
        7z x $tempFileName -aoa -o"$destPath" | Out-Null

        Write-Host "OK" -ForegroundColor Green
        $comp.Installed = $true
        Remove-Item $tempFileName
    }

    # recurse dependencies
    foreach($dependencyId in $comp.Dependencies) {
        InstallComponentById $dependencyId $destPath -whatif:$whatIf -excludeDocs:$excludeDocs -excludeExamples:$excludeExamples
    }
}

# fetch tools packages
foreach($tool_id in $TOOL_IDS) {
    FetchToolsUpdatePackages $tool_id
}

# fetch licenses
FetchUpdatePackages "$QT_ROOT_URL/licenses"
