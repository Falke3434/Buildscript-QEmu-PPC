#!/bin/bash
set -e

# -------------------------------
# 1) Abhängigkeiten installieren
# -------------------------------
install_dependencies() {
    echo "🔧 Prüfe, ob Git installiert ist..."
    if ! command -v git >/dev/null 2>&1; then
        echo "🔧 Git wird installiert..."
        sudo apt update
        sudo apt install -y git
    else
        echo "✅ Git ist bereits installiert"
    fi

    echo "🔧 Installation der restlichen Systempakete..."

    # Quellen für build-dep aktivieren, falls vorhanden
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources~
        sudo sed -Ei 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
    fi

    sudo apt update

    if sudo apt build-dep -y qemu; then
        echo "✅ Build-Abhängigkeiten installiert"
    else
        echo "⚠️ Build-Abhängigkeiten manuell installieren"
        sudo apt install -y \
            build-essential ninja-build python3 meson \
            libglib2.0-dev libpixman-1-dev \
            libsdl2-dev libslirp-dev libxkbcommon-dev \
            libpulse-dev libpipewire-0.3-dev libjack-dev libasound2-dev \
            pkg-config
    fi
}

# -------------------------------
# 2) QEMU Repository vorbereiten / aktualisieren
# -------------------------------
prepare_qemu_repo() {
    if [ -d "qemu" ]; then
        cd qemu
        if [ -d ".git" ]; then
            echo "🔄 Existierendes Repo → git pull"
            git reset --hard
            git pull
        else
            echo "⚠️ Kein Git-Repo → lösche und klone neu"
            cd ..
            rm -rf qemu
            git clone https://gitlab.com/qemu-project/qemu.git
            cd qemu
        fi
    else
        echo "⬇️ Klone QEMU-Repository..."
        git clone https://gitlab.com/qemu-project/qemu.git
        cd qemu
    fi
}

# -------------------------------
# 3) QEMU konfigurieren
# -------------------------------
configure_qemu() {
    echo "🧹 Alten Build-Ordner löschen..."
    cd qemu
    sudo rm -rf build 2>/dev/null || true
    sudo chown -R $USER:$USER .

    echo "🔧 QEMU für PowerPC konfigurieren..."

    echo ""
    echo "💡 Hinweis zu Configure-Optionen:"
    echo "--target-list=ppc-softmmu   → Baut nur den PPC-Emulator"
    echo "--enable-sdl                → SDL-GUI"
    echo "--enable-gtk                → GTK-GUI (benutzerfreundlicher, manchmal stabiler als SDL)"
    echo "--enable-opengl             → 3D-Beschleunigung über OpenGL (für moderne GUIs)"
    echo "--enable-lto                → Link-Time-Optimierung, kleinere & schnellere Binaries"
    echo "--enable-slirp              → User-Mode Networking, praktisch ohne root"
    echo "--enable-libusb             → USB-Passthrough"
    echo "--enable-virtfs             → Virtuelle Ordnerfreigabe (host<->guest)"
    echo "--enable-vnc                → Fernzugriff über VNC"
    echo "--enable-tools              → qemu-img etc. mitbauen"
    echo "--enable-kvm                → Hardwarebeschleunigung für x86 (für PPC keine Wirkung)"
    echo "--disable-werror            → Build bricht nicht bei Warnungen ab"
    echo "Optional:"
    echo "--enable-spice              → SPICE-Protokoll für Remote-Desktop"
    echo "--enable-debug-info/--enable-debug-tcg → Kernel/Amiga debuggen"
    echo "--audio-drv-list=alsa,pa,sdl → Soundprobleme vermeiden"
    echo "--disable-docs              → Spart Build-Zeit, wenn die Doku nicht benötigt wird"
    echo ""

    ./configure \
        --target-list=ppc-softmmu \
        --enable-sdl \
        --enable-gtk \
        --enable-lto \
        --enable-slirp \
        --enable-libusb
}

# -------------------------------
# 4) QEMU kompilieren
# -------------------------------
compile_qemu() {
    echo "🧱 Kompiliere QEMU..."
    cd qemu
    make -j"$(nproc)"
    echo "✅ Kompilierung abgeschlossen!"
}

# -------------------------------
# 5) QEMU installieren
# -------------------------------
install_qemu() {
    echo "❓ Möchtest du QEMU systemweit installieren? (Ja/Nein)"
    read -r INSTALL
    if [[ "$INSTALL" =~ ^[JjYy]$ ]]; then
        cd qemu
        sudo make install

        # Symlink anlegen
        if [ ! -f /usr/bin/qemu ]; then
            echo "🔗 Erstelle Symlink /usr/bin/qemu → /usr/bin/qemu-system-ppc"
            sudo ln -sf /usr/bin/qemu-system-ppc /usr/bin/qemu
        fi

        echo "✅ QEMU installiert! Starte mit: qemu"
    else
        echo "🚫 Installation übersprungen. Nutze QEMU direkt aus ./qemu/build/qemu-system-ppc"
    fi
}

# -------------------------------
# 7) QEMU testen
# -------------------------------
test_qemu() {
    echo "🧪 Teste QEMU PPC-Build..."

    # Systemweite Installation
    if command -v qemu >/dev/null 2>&1; then
        echo "ℹ️ QEMU systemweit (via qemu) gefunden:"
        qemu --version
    elif command -v qemu-system-ppc >/dev/null 2>&1; then
        echo "ℹ️ QEMU systemweit (via qemu-system-ppc) gefunden:"
        qemu-system-ppc --version
    # Lokaler Build
    elif [ -x "qemu/build/qemu-system-ppc" ]; then
        echo "ℹ️ QEMU lokal im Build-Verzeichnis:"
        qemu/build/qemu-system-ppc --version
    else
        echo "❌ QEMU nicht gefunden. Stelle sicher, dass es kompiliert oder installiert wurde."
    fi
}

# -------------------------------
# Hauptmenü / Schrittsteuerung
# -------------------------------
echo "Wähle die Aktion:"
echo "1) Abhängigkeiten installieren"
echo "2) QEMU Repository vorbereiten / aktualisieren"
echo "3) QEMU konfigurieren"
echo "4) QEMU kompilieren"
echo "5) QEMU installieren"
echo "6) QEMU testen (lokal oder systemweit)"

read -r CHOICE

case "$CHOICE" in
    1) install_dependencies ;;
    2) prepare_qemu_repo ;;
    3) configure_qemu ;;
    4) compile_qemu ;;
    5) install_qemu ;;
    6) test_qemu ;;
    *) echo "❌ Ungültige Auswahl" ;;
esac
