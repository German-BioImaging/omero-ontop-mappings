#!/usr/bin/env bash
set -euo pipefail

# Install omero-py and omero-rdf using python's built-in venv. 
VENV_DIR="Omero_venv"
os="$(uname -s)"
arch="$(uname -m)"

echo "== OMERO installer =="
echo "OS: $os | Arch: $arch"

# Ubuntu 
if [[ "$os" == "Linux" ]]; then
  if [[ "$arch" != "x86_64" ]]; then
    echo "ERROR: Linux install supports x86_64 only."
    exit 1
  fi

  if ! command -v python3.10 >/dev/null 2>&1; then
    echo "Installing Python 3.10 "
    sudo apt-get update -y
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -y
    sudo apt-get install -y python3.10 python3.10-venv python3.10-dev build-essential
  else
    sudo apt-get install -y python3.10-venv python3.10-dev build-essential
  fi

  rm -rf "$VENV_DIR"
  /usr/bin/python3.10 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install -U pip setuptools wheel
  pip install https://github.com/glencoesoftware/zeroc-ice-py-linux-x86_64/releases/download/20240202/zeroc_ice-3.6.5-cp310-cp310-manylinux_2_28_x86_64.whl
  pip install omero-py omero-rdf pytest rdflib requests

# MAC
elif [[ "$os" == "Darwin" ]]; then
  
  /opt/homebrew/bin/python3.11 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install -U pip setuptools wheel
  pip install https://github.com/glencoesoftware/zeroc-ice-py-macos-universal2/releases/download/20240131/zeroc_ice-3.6.5-cp311-cp311-macosx_11_0_universal2.whl
  pip install omero-py omero-rdf pytest rdflib requests
else
  echo "Unsupported OS: $os"
  exit 1
fi

python - <<'PY'
from importlib.metadata import version
import Ice
print("omero-py:", version("omero-py"))
print("omero-rdf:", version("omero-rdf"))
print("Ice:", Ice.stringVersion())
PY

