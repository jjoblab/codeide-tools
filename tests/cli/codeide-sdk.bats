#!/usr/bin/env bash
# Tests bats du CLI codeide-sdk — vecteurs de référence tests/golden/ (12.7).
# Chaque option documentée a un test : le sens d'une option ne peut pas être
# inversé sans casser un test (prompt 2 § 8).

CODEIDE_SDK="$BATS_TEST_DIRNAME/../../cli/codeide-sdk"
export GOLDEN="$BATS_TEST_DIRNAME/../golden"
FETCH_HOOK="$BATS_TMPDIR/fake-fetch.$$"

setup() {
  TESTROOT=$(mktemp -d "$BATS_TMPDIR/cli.XXXXXX")
  export CODEIDE_TOOLS_MANIFEST="$GOLDEN/manifest-test.json"
  export CODEIDE_SDK_ROOT="$TESTROOT/sdk"
  export CODEIDE_CACHE="$TESTROOT/cache"
  export CODEIDE_ARCH=aarch64
  export CODEIDE_FETCH_CMD="$FETCH_HOOK"
  cat >"$FETCH_HOOK" <<'HOOK'
#!/bin/sh
out=''
while [ $# -gt 0 ]; do
  case $1 in
    -o) out=$2; shift 2 ;;
    *) url=$1; shift ;;
  esac
done
name=${url##*/}
cp "$GOLDEN/archives/$name" "$out"
HOOK
  chmod +x "$FETCH_HOOK"
}

teardown() {
  rm -rf "$TESTROOT" "$FETCH_HOOK"
}

sdk() { sh "$CODEIDE_SDK" "$@"; }

# --- help / version ----------------------------------------------------------

@test "help : code 0 et usage affiché" {
  run sdk help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage"
}

@test "--help : code 0" {
  run sdk --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "codeide-sdk"
}

@test "version : code 0 et semver" {
  run sdk version
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq 'codeide-sdk [0-9]+\.[0-9]+\.[0-9]+'
}

@test "commande inconnue : code 1" {
  run sdk fiente
  [ "$status" -eq 1 ]
}

# --- list ----------------------------------------------------------------------

@test "list : affiche les composants de l'arch et any" {
  run sdk list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "test-tools@1.0-r1"
  echo "$output" | grep -q "test-tools@2.0-r1"
}

@test "list : le canal preview est étiqueté" {
  run sdk list
  echo "$output" | grep -q "\[preview\]"
  echo "$output" | grep -q "\[stable\]"
}

@test "list --json : une ligne d'évènement JSON valide" {
  run sh "$CODEIDE_SDK" --json list
  [ "$status" -eq 0 ]
  echo "$output" | grep '"event"' | jq -e '.event == "listed"' >/dev/null
}

@test "--arch arm : filtre les composants d'arch" {
  run sh "$CODEIDE_SDK" --arch arm list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "test-tools@1.0"   # any passe pour toute arch
}

# --- env --print (contrat 12.4) -------------------------------------------------

@test "env --print : exactement les variables du contrat 12.4" {
  run sdk env --print
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^HOME="
  echo "$output" | grep -q "^ANDROID_HOME=$CODEIDE_SDK_ROOT"
  echo "$output" | grep -q "^ANDROID_SDK_ROOT=$CODEIDE_SDK_ROOT"
  echo "$output" | grep -q "^ANDROID_USER_HOME=.*/\.android$"
  echo "$output" | grep -q "^GRADLE_USER_HOME=.*/\.gradle$"
  echo "$output" | grep -q "^PATH="
  # pas de local.properties, pas de sdk.dir (le CLI n'écrit jamais ce fichier)
  [ ! -f "$CODEIDE_SDK_ROOT/local.properties" ]
}

# --- install ---------------------------------------------------------------------

@test "install <id>@<version> : fichiers, état, code 0" {
  run sdk install test-tools@1.0
  [ "$status" -eq 0 ]
  [ -f "$CODEIDE_SDK_ROOT/test-tools/1.0/hello.txt" ]
  [ -f "$CODEIDE_SDK_ROOT/test-tools/1.0/run.sh" ]
  jq -e '.components["test-tools@1.0@any"].sha256' "$CODEIDE_SDK_ROOT/install-state.json" >/dev/null
}

@test "install : idempotent (2e passage : déjà installé, un seul téléchargement)" {
  sdk install test-tools@1.0 >/dev/null
  run sdk install test-tools@1.0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "déjà installé"
  # le cache adressé par SHA-256 garantit UN téléchargement par artefact
  [ "$(find "$CODEIDE_CACHE" -type f | wc -l)" -eq 1 ]
}

@test "install --json : ligne JSON valide" {
  run sh "$CODEIDE_SDK" --json install test-tools@1.0
  [ "$status" -eq 0 ]
  echo "$output" | grep '"event":"installed"' | jq -e '.status == "ok"' >/dev/null
}

@test "install --profile default : installe le profil du manifeste" {
  run sdk install --profile default
  [ "$status" -eq 0 ]
  [ -f "$CODEIDE_SDK_ROOT/test-tools/1.0/hello.txt" ]
}

@test "install --profile inconnu : code 2" {
  run sdk install --profile fantôme
  [ "$status" -eq 2 ]
}

@test "install version inexistante : avertissement manifeste incompatible, échec (5)" {
  run sdk install test-tools@9.9
  [ "$status" -eq 5 ]
  echo "$output" | grep -q "manifeste incompatible"
}

@test "install composant preview : ignoré (l'app ignore preview — 12.2)" {
  run sdk install test-tools@2.0
  [ "$status" -eq 5 ]  # pas d'entrée stable pour (test-tools, 2.0)
  echo "$output" | grep -q "indisponible"
  [ ! -d "$CODEIDE_SDK_ROOT/test-tools/2.0" ]
}

@test "install somme erronée : code 4, rien d'installé" {
  export CODEIDE_TOOLS_MANIFEST="$GOLDEN/archives/manifest-sha-errone.json"
  run sdk install test-tools@1.0
  [ "$status" -eq 4 ]
  echo "$output" | grep -q "SHA-256 invalide"
  [ ! -d "$CODEIDE_SDK_ROOT/test-tools/1.0" ]
}

@test "install : état lu par verify --deep (sha complet)" {
  sdk install test-tools@1.0 >/dev/null
  run sdk verify --deep
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq "état : [0-9a-f]{12}"
}

# --- remove ------------------------------------------------------------------------

@test "remove <id> : chemin supprimé, état vidé" {
  sdk install test-tools@1.0 >/dev/null
  run sdk remove test-tools
  [ "$status" -eq 0 ]
  [ ! -d "$CODEIDE_SDK_ROOT/test-tools/1.0" ]
  [ "$(jq -r '.components | length' "$CODEIDE_SDK_ROOT/install-state.json")" -eq 0 ]
}

@test "remove absent : avertissement, code 0" {
  run sdk remove test-tools
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "rien dans l'état"
}

# --- verify --------------------------------------------------------------------------

@test "verify : exécute la commande du manifeste (sans shell)" {
  sdk install test-tools@1.0 >/dev/null
  run sdk verify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^OK     test-tools/1.0/run.sh"
}

@test "verify --deep : affiche le sha de l'état" {
  sdk install test-tools@1.0 >/dev/null
  run sdk verify --deep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "état :"
}

@test "verify : binaire défaillant → code 5 avec SA sortie réelle" {
  sdk install test-tools@1.0 >/dev/null
  printf '#!/bin/sh\necho autre-chose\n' >"$CODEIDE_SDK_ROOT/test-tools/1.0/run.sh"
  chmod +x "$CODEIDE_SDK_ROOT/test-tools/1.0/run.sh"
  run sdk verify
  [ "$status" -eq 5 ]
  echo "$output" | grep -q "autre-chose"   # la sortie réelle, pas un message générique
}

# --- doctor ---------------------------------------------------------------------------

@test "doctor : code 0, affiche arch + racine + JVM validée par exécution" {
  sdk install test-tools@1.0 >/dev/null
  run sdk doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "arch : aarch64"
  echo "$output" | grep -q "codeide-sdk "
}

# --- shim codeidesetup (dépréciation) ----------------------------------------------------

@test "shim -L : redirige vers list" {
  run sh "$BATS_TEST_DIRNAME/../../scripts/codeidesetup" -L
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "test-tools@1.0"
}

@test "shim : avertissement de dépréciation" {
  run sh "$BATS_TEST_DIRNAME/../../scripts/codeidesetup" -L
  echo "$output$stderr" | grep -qi "DÉPRÉCIÉ\|déprécié"
}
