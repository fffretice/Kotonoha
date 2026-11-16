#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p work outputs/Models
proxy=()
if [[ -n "${KOTONOHA_PROXY:-}" ]]; then proxy=(--proxy "$KOTONOHA_PROXY"); fi
curl "${proxy[@]}" -fL --retry 3 --connect-timeout 20 --continue-at - 'https://github.com/ggml-org/llama.cpp/releases/download/b12428/llama-b12428-bin-macos-arm64.tar.gz' -o work/llama-fast.tar.gz
python3 - <<'PY'
import hashlib,tarfile,pathlib,os
archive=pathlib.Path('work/llama-fast.tar.gz')
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='7d72477a2a375cc1d93e308b34e26fb9a608c2f93750517d2bafc59af578d3e2','Runtime hash mismatch'
folder=pathlib.Path('work/runtime');folder.mkdir(exist_ok=True)
with tarfile.open(archive) as t:
 for m in t.getmembers():
  name=m.name.split('/')[-1]
  if name in ['llama-server','LICENSE'] or '.dylib' in name or name.endswith('.metallib'):
   dst=folder/name
   if m.isfile():
    dst.write_bytes(t.extractfile(m).read());dst.chmod(m.mode)
   elif m.issym() and '/' not in m.linkname and not dst.is_symlink():
    dst.symlink_to(m.linkname)
print('Verified local inference engine')
PY
if [[ "${1:-}" == "--model" ]]; then
  curl "${proxy[@]}" -fL --retry 3 --connect-timeout 20 --continue-at - 'https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true' -o outputs/Models/Qwen3-8B-Q4_K_M.gguf.part
  python3 - <<'PY'
import hashlib,pathlib
p=pathlib.Path('outputs/Models/Qwen3-8B-Q4_K_M.gguf.part');h=hashlib.sha256()
with p.open('rb') as f:
 for b in iter(lambda:f.read(16*1024*1024),b''):h.update(b)
assert h.hexdigest()=='d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785','Model hash mismatch'
p.rename(p.with_suffix(''))
print('Verified Qwen3-8B model')
PY
fi
./scripts/build.sh
