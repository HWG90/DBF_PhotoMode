"""Read-only audit of the installed LLL manifest and private module closure."""
import argparse
import hashlib
import json
from pathlib import Path
import re

IMPORT=re.compile(r"\b(?:mod|host)\s*\.\s*require\s*\(\s*['\"](src/[^'\"]+\.lua)['\"]")

def audit(directory):
    directory=Path(directory).resolve()
    manifest=json.loads((directory/'manifest.json').read_text())
    spec=manifest['lll'];declared=spec['modules']
    actual=sorted(p.relative_to(directory).as_posix()for p in (directory/'src').rglob('*.lua'))
    errors=[]
    if len(declared)!=len(set(declared)):errors.append('Duplicate declared modules')
    if sorted(declared)!=actual:
        errors.append('Module inventory mismatch: undeclared='+str(sorted(set(actual)-set(declared)))+' missing='+str(sorted(set(declared)-set(actual))))
    rows={}
    for name in [spec['entry'],*declared]:
        target=(directory/name).resolve()
        if not target.is_relative_to(directory)or not target.is_file():
            errors.append('Unreadable or unsafe module: '+name);continue
        body=target.read_bytes();rows[name]=hashlib.sha256(body).hexdigest()
        for dependency in IMPORT.findall(body.decode('utf-8')):
            if dependency not in declared:errors.append(name+': undeclared private import '+dependency)
    return {'directory':str(directory),'passed':not errors,'declared_modules':len(declared),
            'actual_modules':len(actual),'errors':errors,'module_sha256':rows,'game_process_accessed':False}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path);parser.add_argument('--receipt',type=Path)
    args=parser.parse_args();report=audit(args.directory)
    if args.receipt:
        args.receipt.parent.mkdir(parents=True,exist_ok=True)
        args.receipt.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if k!='module_sha256'},indent=2))
    return 0 if report['passed']else 1

if __name__=='__main__':raise SystemExit(main())
