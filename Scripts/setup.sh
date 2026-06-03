#!/bin/bash
# Script de setup para SyncSalud
# Crea el proyecto Xcode desde project.yml usando XcodeGen

set -e

echo "🔧 Setup de SyncSalud"
echo ""

# 1. Verificar XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Instalando XcodeGen..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "❌ Homebrew no está instalado."
        echo "   Instálalo desde https://brew.sh o instalá XcodeGen manualmente:"
        echo "   https://github.com/yonaskolb/XcodeGen"
        exit 1
    fi
fi

# 2. Generar el proyecto
echo "⚙️  Generando SyncSalud.xcodeproj..."
xcodegen generate

# 3. Abrir Xcode
echo ""
echo "✅ Proyecto generado correctamente"
echo ""
echo "📋 Próximos pasos en Xcode:"
echo "   1. Abrí SyncSalud.xcodeproj"
echo "   2. Para cada target (iOS y macOS):"
echo "      - Seleccioná tu Team en Signing & Capabilities"
echo "      - Verificá que el iCloud Container sea: iCloud.com.yourcompany.syncsalud"
echo "   3. Si tu bundle ID es distinto, editá project.yml y re-ejecutá este script"
echo "   4. Compilá y corré en simulador o dispositivo"
echo ""
echo "🚀 Abriendo Xcode..."
open SyncSalud.xcodeproj
