#!/usr/bin/env bash
# Verificación completa del proyecto (ver CLAUDE.md, sección "Verificación").
#
#   tools/verify.sh            → import + lint + arranque + tests + smoke test
#   GODOT=/ruta/a/godot tools/verify.sh
#
# Copia tools/strict_warnings.cfg como override.cfg mientras corre: así TODAS
# las advertencias de GDScript salen como errores (Godot no imprime warnings
# fuera del editor). override.cfg se borra al terminar y está en .gitignore.
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
LOG_DIR="${LOG_DIR:-/tmp/dc_verify}"
mkdir -p "$LOG_DIR"

# Avisos conocidos y benignos (de assets de terceros, no de nuestro código).
IGNORE='OBJ: Ambient light for material'

cp tools/strict_warnings.cfg override.cfg
trap 'rm -f override.cfg' EXIT

failed=0

step() {
	local name="$1"; shift
	local log="$LOG_DIR/$name.log"
	timeout 300 "$GODOT" --headless --path . "$@" > "$log" 2>&1
	local code=$?
	local problems
	problems=$(grep -nE 'SCRIPT ERROR|^ERROR|^WARNING|Parse Error|FAILED|TEST FAIL' "$log" | grep -vE "$IGNORE")
	if [ "$code" -ne 0 ] || [ -n "$problems" ]; then
		echo "✗ $name (código $code) — log: $log"
		[ -n "$problems" ] && echo "$problems" | head -40
		failed=1
	else
		echo "✓ $name"
	fi
}

step import --import
step lint res://tools/lint.tscn
step arranque --quit-after 120
[ -f tests/TestRunner.tscn ] && step tests res://tests/TestRunner.tscn
[ -f tests/SmokeTest.tscn ] && step smoke res://tests/SmokeTest.tscn

if [ "$failed" -ne 0 ]; then
	echo "VERIFICACIÓN FALLIDA"
	exit 1
fi
echo "VERIFICACIÓN OK"
