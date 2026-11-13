from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]/'Resources/Runtime'
manifest={
 'schemaVersion':1,'generatedAt':'2026-11-12',
 'cpp':{'compiler':'Clang/LLD 22.1.8 WASM','compilerRelease':'https://github.com/cppstudio-io/wasm-clang-runtime/releases/tag/v0.1.0','sysroot':'Official WebAssembly/wasi-sdk 33, noeh libc++ (teaching iostream removed)','sysrootRelease':'https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-33','memfs':'rebuilt from upstream source using Clang 22 and WASI libc; MAX_NODES=8192'},
 'python':{'runtime':'Pyodide 314.0.7','interpreter':'CPython 3.14.2','release':'https://github.com/pyodide/pyodide/releases/tag/314.0.7'},
 'patches':['separate fd stdout/stderr forwarding','USTAR filename prefix handling','64KiB output hard stop','one Worker per job','loopback-only local resources'],
 'files':{}
}
for p in sorted(root.rglob('*')):
 if p.is_file() and p.name!='manifest.json':manifest['files'][str(p.relative_to(root))]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Runtime files',len(manifest['files']),'total',sum(x['bytes'] for x in manifest['files'].values()))
