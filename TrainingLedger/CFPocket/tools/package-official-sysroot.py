from pathlib import Path
import tarfile, argparse, tempfile
parser=argparse.ArgumentParser()
parser.add_argument('sdk',type=Path,help='Extracted official wasi-sdk 33 directory')
parser.add_argument('archive',type=Path,help='Original wasi-sdk 33 tar.gz')
args=parser.parse_args()
sdk=args.sdk; base=sdk/'share/wasi-sysroot'; out=Path(__file__).resolve().parents[1]/'Resources/Runtime/cpp/sysroot22.tar'
entries={}
for p in sorted((base/'include/wasm32-wasip1').rglob('*')):
 rel=p.relative_to(base).as_posix()
 if '/eh/' in rel or rel.endswith('/eh'):continue
 if p.is_file():entries[rel]=p
for p in sorted((base/'lib/wasm32-wasip1').rglob('*')):
 if not p.is_file() or '/eh/' in str(p) or p.suffix=='.so':continue
 rel=p.relative_to(base).as_posix();entries[rel]=p
 if p.parent.name=='noeh':entries['lib/wasm32-wasip1/'+p.name]=p
for p in sorted((sdk/'lib/clang/22/include').rglob('*')):
 if p.is_file():entries[p.relative_to(sdk).as_posix()]=p
with tarfile.open(args.archive) as t:
 m=next(m for m in t.getmembers() if m.name.endswith('/lib/clang/22/lib/wasm32-unknown-wasip1/libclang_rt.builtins.a'))
 temporary=tempfile.TemporaryDirectory(); b=Path(temporary.name)/'official-builtins.a';b.write_bytes(t.extractfile(m).read());entries['lib/wasm32-wasip1/libclang_rt.builtins.a']=b
with tarfile.open(out,'w',format=tarfile.USTAR_FORMAT,dereference=True) as t:
 directories=set()
 for rel,p in entries.items():
  dirs=list(Path(rel).parents)[:-1]
  for d in reversed(dirs):
   if str(d) not in directories:
    info=tarfile.TarInfo(str(d));info.type=tarfile.DIRTYPE;info.mode=0o755;t.addfile(info);directories.add(str(d))
  t.add(p,arcname=rel,recursive=False)
print('Official SDK tar',len(entries),'files',len(directories),'directories',out.stat().st_size,'bytes')
