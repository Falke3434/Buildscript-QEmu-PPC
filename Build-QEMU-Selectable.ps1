# Neustart als Admin, wenn nicht bereits mit Adminrechten gestartet
If (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    
    Write-Host "Starte Skript neu mit Administratorrechten..."
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    Exit
}

function Show-Menu {
    Write-Host ""
    Write-Host "========== QEMU Build Setup =========="
    Write-Host "1. MSYS2 installieren"
    Write-Host "2. QEMU herunterladen oder aktualisieren"
    Write-Host "3. QEMU kompilieren und installieren"
    Write-Host "4. BBoot installieren"
    Write-Host "5. MSYS2 deinstallieren"
    Write-Host "6. Beenden"
    Write-Host "======================================"
	Write-Host "9. Patches anwenden (vor QEmu kompilieren ausfuehren)"
	Write-Host "10. Patches Vorschau"
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

# Start-Menu
do {
    Show-Menu
    $choice = Read-Host "Waehle eine Option (1-6)"

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

				if (Test-Path $msys2_installer_path) {
					Remove-Item $msys2_installer_path -Force
					Write-Host "Temporaere MSYS2-Installationsdatei wurde geloescht."
				}
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

            Write-Host "Installiere benoetigte Pakete..."
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

			Write-Host "Analysiere benoetigte DLLs mit ldd..."

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
			Write-Host "Lade neuestes BBoot-Release von Codeberg…"
			try {
				$bbootApi = "https://codeberg.org/api/v1/repos/qmiga/bboot/releases"
				$releases = Invoke-RestMethod -Uri $bbootApi -UseBasicParsing
				$latest = $releases | Sort-Object published_at -Descending | Select-Object -First 1

				$asset = $latest.assets | Where-Object { $_.name -match "\.zip$|\.tar\.gz$|\.tgz$|\.tar\.xz$" } |
						 Sort-Object name | Select-Object -First 1
				if (-not $asset) {
					throw "Kein unterstuetztes Archiv (.zip/.tar.gz/.tgz/.tar.xz) im neuesten Release gefunden!"
				}

				$fileName = $asset.name
				$dlUrl = $asset.browser_download_url
				$tmpFile = Join-Path $env:TEMP $fileName

				Write-Host "Herunterladen: $fileName"
				Invoke-WebRequest -Uri $dlUrl -OutFile $tmpFile

				Write-Host "Entpacke nach $qemu_install_dir…"
				switch -Wildcard ($fileName) {
					"*.zip" {
						Expand-Archive -Path $tmpFile -DestinationPath $qemu_install_dir -Force
					}
					"*.tar.gz" {
						if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
							throw "tar.exe wurde nicht gefunden!"
						}
						& tar.exe -xf $tmpFile -C $qemu_install_dir
					}
					"*.tgz" {
						if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
							throw "tar.exe wurde nicht gefunden!"
						}
						& tar.exe -xf $tmpFile -C $qemu_install_dir
					}
					"*.tar.xz" {
						if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
							throw "tar.exe wurde nicht gefunden!"
						}
						& tar.exe -xf $tmpFile -C $qemu_install_dir
					}
					default {
						throw "Unbekanntes Archivformat: $fileName"
					}
				}

				# Temporaere Datei loeschen
				if (Test-Path $tmpFile) {
					Remove-Item $tmpFile -Force
					Write-Host "Temporaeres Archiv $fileName wurde geloescht."
				}

				Write-Host "BBoot ($fileName) wurde erfolgreich installiert."
			}
			catch {
				Write-Warning "Fehler beim Installieren von BBoot: $_"
			}
		}

		'5' {
			if (Test-Path "$msys2_root\uninstall.exe") {
				Write-Host "Deinstalliere MSYS2 von $msys2_root..."
				Start-Process -FilePath "$msys2_root\uninstall.exe" -ArgumentList "purge --confirm-command" -Wait
				Write-Host "MSYS2 wurde deinstalliert."
			} else {
				Write-Warning "MSYS2-Deinstallationsprogramm nicht gefunden unter: $msys2_root\uninstall.exe"
			}
		}

        '6' {
            Write-Host "Beende das Skript."
            exit
        }

		'9' {
			Write-Host "==> Pruefe und korrigiere qga/vss-win32/install.cpp ..."

			$installCpp = "$qemu_dir/qga/vss-win32/install.cpp"
			if (Test-Path $installCpp) {
				$lines = Get-Content $installCpp
				$out = @()
				$inBlock = $false

				foreach ($line in $lines) {
					# Starte Block für ConvertStringToBSTR
					if ($line -match "Support function to convert ASCII string into BSTR") {
						$out += "#if !defined(__MINGW64_VERSION_MAJOR) || __MINGW64_VERSION_MAJOR < 14 /* Support function to convert ASCII string into BSTR (used in _bstr_t) */"
						$inBlock = $true
						continue
					}

					# Ende des urspruenglichen Blockes erkennen
					if ($inBlock -and $line -match "^\}") {
						$out += $line
						$out += "#endif /* __MINGW64_VERSION_MAJOR < 14 */"
						$inBlock = $false
						continue
					}

					# Ueberspringe alten Block
					if ($inBlock) { continue }

					# Alle anderen Zeilen übernehmen
					$out += $line
				}

				# zurueckschreiben
				Set-Content -Path $installCpp -Value $out -Encoding UTF8
				Write-Host ">> install.cpp erfolgreich gepatcht (MINGW64-Version-Bedingung)."
			} else {
				Write-Warning "install.cpp nicht gefunden: $installCpp"
			}

			Write-Host "==> Pruefe und korrigiere os-win32.h ..."

			$osWin32File = "$qemu_dir/include/system/os-win32.h"
			if (Test-Path $osWin32File) {
				Write-Host ">> Patch: ftruncate in os-win32.h auskommentieren..."
				$lines = Get-Content $osWin32File
				$out = @()
				$skip = $false
				foreach ($line in $lines) {
					if ($line -match '^\s*#if !defined\(ftruncate\)') {
						$skip = $true
						$out += "/* #if !defined(ftruncate)"
						$out += " * # define ftruncate qemu_ftruncate64"
						$out += " * #endif */"
						continue
					}
					if ($skip) {
						if ($line -match '^\s*#endif') { $skip = $false }
						continue
					}
					$out += $line
				}
				Set-Content -Path $osWin32File -Value $out -Encoding UTF8
				Write-Host ">> ftruncate-Block erfolgreich auskommentiert."
			} else {
				Write-Warning "os-win32.h nicht gefunden: $osWin32File"
			}

			Write-Host "==> Alle Patches abgeschlossen. Jetzt kannst du QEMU mit Punkt 3 kompilieren."
		}

		'10' {
			Write-Host "==> Patch-Vorschau: install.cpp"

			$installCpp = "$qemu_dir/qga/vss-win32/install.cpp"
			if (Test-Path $installCpp) {
				$lines = Get-Content $installCpp
				$inBlock = $false

				foreach ($line in $lines) {
					if ($line -match "Support function to convert ASCII string into BSTR") {
						Write-Host "`n--- ALT-Block beginnt hier ---"
						$inBlock = $true
					}

					if ($inBlock) {
						Write-Host $line
						if ($line -match "^\}") {
							Write-Host "--- ALT-Block endet hier ---"
							Write-Host "----------------------------"
							Write-Host "--- NEU-Block wuerde eingefuegt ---"
							Write-Host "#if !defined(__MINGW64_VERSION_MAJOR) || __MINGW64_VERSION_MAJOR < 14 /* Support function to convert ASCII string into BSTR */"
							Write-Host "namespace _com_util { ... }"
							Write-Host "#endif /* __MINGW64_VERSION_MAJOR < 14 */`n"
							$inBlock = $false
						}
						continue
					}
				}
			} else {
				Write-Warning "install.cpp nicht gefunden: $installCpp"
			}

		Write-Host "==> Patch-Vorschau: os-win32.h"

		$osWin32File = "$qemu_dir/include/system/os-win32.h"
		if (Test-Path $osWin32File) {
			$lines = Get-Content $osWin32File
			$found = $false
			for ($i = 0; $i -lt $lines.Count; $i++) {
				$line = $lines[$i]
				# Suche nach ftruncate, ignoriere bereits auskommentierte Zeilen
				if ($line -match 'ftruncate' -and $line -notmatch '^\s*/\*') {
					$found = $true
					Write-Host "`n--- ALT-Block beginnt hier ---"
					# zeige den Block (3 Zeilen vor #endif)
					for ($j = $i; $j -lt [Math]::Min($i+5,$lines.Count); $j++) {
						Write-Host $lines[$j]
						if ($lines[$j] -match '^\s*#endif') { break }
					}
					Write-Host "--- ALT-Block endet hier ---"
					Write-Host "----------------------------"
					Write-Host "--- NEU-Block wuerde eingefuegt ---"
					Write-Host "/* #if !defined(ftruncate)"
					Write-Host " * # define ftruncate qemu_ftruncate64"
					Write-Host " * #endif */`n"
					break
				}
			}
			if (-not $found) {
				Write-Host ">> ftruncate-Block nicht gefunden oder bereits auskommentiert."
			}
		} else {
			Write-Warning "os-win32.h nicht gefunden: $osWin32File"
		}


			Write-Host "==> Patch-Vorschau abgeschlossen. Keine Dateien wurden veraendert."
		}

        default {
            Write-Warning "Ungueltige Eingabe. Bitte 1-6 waehlen."
        }
    }

} while ($true)
