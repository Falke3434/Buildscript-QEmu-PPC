function Show-Menu {
    Write-Host ""
    Write-Host "========== QEMU Build Setup =========="
    Write-Host "1. MSYS2 installieren"
    Write-Host "2. QEMU herunterladen oder aktualisieren"
    Write-Host "3. QEMU kompilieren und installieren"
    Write-Host "4. MSYS2 deinstallieren"
    Write-Host "5. Beenden"
    Write-Host "======================================"
}

function Get-LatestMsys2InstallerUrl {
    $baseUrl = "https://repo.msys2.org/distrib/x86_64/"
    Write-Host "Hole aktuelle MSYS2 Installer-Liste..."
    $html = Invoke-WebRequest $baseUrl
    $links = $html.Links | Where-Object { $_.href -match "^msys2-x86_64-.*\.exe$" }
    if ($links.Count -eq 0) {
        throw "Keine MSYS2 Installer-Links gefunden!"
    }
    $latest = $links | Sort-Object href -Descending | Select-Object -First 1
    return $baseUrl + $latest.href
}

function Run-Msys2Command {
    param([string]$command)
    & $msys2_env MSYSTEM=MINGW64 $msys2_bash --login -i -c $command
}

# Konstanten definieren
$msys2_root = "C:\msys64"
$msys2_env = "$msys2_root\usr\bin\env.exe"
$msys2_bash = "$msys2_root\usr\bin\bash.exe"
$windows_username = $env:USERNAME
$home_dir = "C:/msys64/home/$windows_username"
$qemu_dir = "$home_dir/qemu"
$qemu_build_dir = "$qemu_dir/build"
$qemu_install_dir = "C:\qemu"
$msys2_installer_path = "$env:TEMP\msys2-installer.exe"
$mingw64_bin = "$msys2_root\mingw64\bin"

# Start-Menü
do {
    Show-Menu
    $choice = Read-Host "Wähle eine Option (1-5)"

    switch ($choice) {
        '1' {
            if (-not (Test-Path $msys2_env)) {
                Write-Host "MSYS2 nicht gefunden. Starte Installation..."
                $url = Get-LatestMsys2InstallerUrl
                Write-Host "Lade herunter: $url"
                Invoke-WebRequest -Uri $url -OutFile $msys2_installer_path
                #Start-Process -FilePath $msys2_installer_path -ArgumentList "/S" -Wait
                Start-Process -FilePath $msys2_installer_path -ArgumentList "install --root C:\msys64 --confirm-command" -Wait
                Start-Sleep -Seconds 10
                Write-Host "MSYS2 wurde installiert."
            } else {
                Write-Host "MSYS2 ist bereits installiert."
            }
        }

        '2' {
            if (-not (Test-Path $msys2_env)) {
                Write-Warning "Bitte zuerst MSYS2 installieren!"
                break
            }
            Write-Host "Aktualisiere Paketdatenbank..."
            Run-Msys2Command "pacman -Syu --noconfirm"

            Write-Host "Installiere benötigte Pakete..."
            Run-Msys2Command "pacman -S --needed --noconfirm base-devel git mingw-w64-x86_64-toolchain mingw-w64-x86_64-SDL2 mingw-w64-x86_64-SDL_image mingw-w64-x86_64-glib2 mingw-w64-x86_64-pixman mingw-w64-x86_64-libslirp mingw-w64-x86_64-curl mingw-w64-x86_64-python-pip mingw-w64-x86_64-python-sphinx mingw-w64-x86_64-python-sphinx_rtd_theme mingw-w64-x86_64-ninja mingw-w64-x86_64-gtk3"

            if (-not (Test-Path $qemu_dir)) {
                Write-Host "Klone QEMU Repository..."
                Run-Msys2Command "cd $home_dir && git clone --depth 1 https://gitlab.com/qemu-project/qemu.git"
            } else {
                Write-Host "Aktualisiere QEMU Repository..."
                Run-Msys2Command "cd $qemu_dir && git pull"
            }
        }

		'3' {
			if (-not (Test-Path $msys2_env)) {
				Write-Warning "Bitte zuerst MSYS2 installieren!"
				break
			}
			Run-Msys2Command "mkdir -p $qemu_build_dir"
			Run-Msys2Command "cd $qemu_build_dir && ../configure --target-list=ppc-softmmu --enable-sdl --enable-gtk --enable-slirp"

			$cpuCount = [Environment]::ProcessorCount
			Write-Host "Kompiliere mit $cpuCount Threads..."
			Run-Msys2Command "cd $qemu_build_dir && make -j$cpuCount"
			Run-Msys2Command "cd $qemu_build_dir && make install"

			if (-not (Test-Path $qemu_install_dir)) {
				New-Item -Path $qemu_install_dir -ItemType Directory -Force | Out-Null
			}

			Write-Host "Analysiere benötigte DLLs mit ldd..."

			$qemu_binary = Join-Path $qemu_install_dir "qemu-system-ppc.exe"

			# ldd aufrufen und Zeilen filtern, die auf mingw64/bin verweisen
			$ldd_output = Run-Msys2Command "ldd '$qemu_binary' | grep '/mingw64/bin/'"

			# DLL-Namen extrahieren
			$dlls = ($ldd_output -split "`n") | ForEach-Object {
				if ($_ -match '/mingw64/bin/(.*\.dll)') { $matches[1] }
			} | Sort-Object -Unique

			Write-Host "Gefundene DLLs:"
			$dlls | ForEach-Object { Write-Host " - $_" }

			# DLLs kopieren
			foreach ($dll in $dlls) {
				$src = Join-Path $mingw64_bin $dll
				$dst = Join-Path $qemu_install_dir $dll
				if (Test-Path $src) {
					Copy-Item -Path $src -Destination $dst -Force
					Write-Host "Kopiere $dll"
				} else {
					Write-Warning "Fehlende DLL: $dll"
				}
			}

			Write-Host "QEMU wurde nach $qemu_install_dir installiert."
		}

		'4' {
			if (Test-Path "$msys2_root\uninstall.exe") {
				Write-Host "Deinstalliere MSYS2 von $msys2_root..."
				Start-Process -FilePath "$msys2_root\uninstall.exe" -ArgumentList "purge --confirm-command" -Wait
				Write-Host "MSYS2 wurde deinstalliert."
			} else {
				Write-Warning "MSYS2-Deinstallationsprogramm nicht gefunden unter: $msys2_root\uninstall.exe"
			}
		}

        '5' {
            Write-Host "Beende das Skript."
            exit
        }
        default {
            Write-Warning "Ungültige Eingabe. Bitte 1-4 wählen."
        }
    }

} while ($true)
