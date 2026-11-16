#!/usr/bin/env python3
"""Offline legacy-layout copy. Publish a fresh destination only after all checks pass."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import sqlite3

SHORT=re.compile(r'[A-Za-z0-9_-]{1,8}(\.[A-Za-z0-9_-]{1,3})?\Z')

def file_path(files,kind,identity):
    digest=hashlib.sha256(identity.encode('utf-8')).hexdigest()
    result=files/kind
    for offset in range(0,56,8):result/=digest[offset:offset+8]
    return result/(digest[56:]+'.bin')

def backup(source,target):
    target.parent.mkdir(parents=True,exist_ok=True)
    # URI read-only prevents typo paths creating an empty source database.
    with sqlite3.connect(source.resolve().as_uri()+'?mode=ro',uri=True) as src:
        with sqlite3.connect(target) as dst:
            src.backup(dst)
            assert dst.execute('PRAGMA integrity_check').fetchone()==('ok',),'Invalid source database'
            dst.execute('PRAGMA journal_mode=DELETE')

def migrate(source,destination):
    source=Path(source).absolute();destination=Path(destination).absolute()
    if not source.is_dir() or source.is_symlink():raise ValueError('Source must be a real data directory')
    if destination.exists() or destination.is_symlink():raise ValueError('Destination must not exist')
    if destination==source or source in destination.parents or destination in source.parents:
        raise ValueError('Source and destination must be separate trees')
    for path in source.rglob('*'):
        if path.is_symlink():raise ValueError('Symlinks require manual review: '+str(path))
    allowed={'admin','local','domains','certs','temp'}
    if any(path.name not in allowed for path in source.iterdir()):raise ValueError('Unrecognized source root entries')
    admin=source/'admin/db/data.db'
    if not admin.is_file():raise ValueError('Legacy admin/db/data.db is required')
    destination.parent.mkdir(parents=True,exist_ok=True)
    stage=None
    for counter in range(1,1000000):
        candidate=destination.parent/f'm{counter:07x}'
        if candidate in [source,destination]:continue
        try:candidate.mkdir(mode=0o700);stage=candidate;break
        except FileExistsError:continue
    if stage is None:raise ValueError('No migration staging directory available')
    try:
        registry=stage/'admin/files/db/wekan.db'
        backup(admin,registry)
        with sqlite3.connect(registry) as db:
            db.execute('CREATE TABLE IF NOT EXISTS tenantdirs(id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id BETWEEN 1 AND 268435455),host TEXT NOT NULL UNIQUE)')
            db.execute('INSERT OR IGNORE INTO tenantdirs(host) SELECT host FROM domains ORDER BY host')
            mappings={host:f'd{identity:07x}' for identity,host in db.execute('SELECT id,host FROM tenantdirs')}
        tenants=[('admin',source/'admin',stage/'admin'),('local',source/'local',stage/'local')]
        domains=source/'domains'
        if domains.exists():
            for tenant in domains.iterdir():
                if tenant.name not in mappings:raise ValueError('Unregistered tenant directory: '+tenant.name)
                tenants.append((tenant.name,tenant,stage/'domains'/mappings[tenant.name]))
        for host,old,new in tenants:
            if not old.exists():continue
            if not (old/'db/data.db').is_file():raise ValueError('Missing tenant database: '+host)
            if any(p.name not in {'db','files'} for p in old.iterdir()):raise ValueError('Unrecognized tenant entries: '+host)
            if any(p.name not in {'data.db','data.db-wal','data.db-shm','data.db-journal'} for p in (old/'db').iterdir()):
                raise ValueError('Unrecognized database files: '+host)
            files=new/'files'
            if host!='admin':backup(old/'db/data.db',files/'db/wekan.db')
            for kind in ['attachme','avatars']:
                target=files/kind;target.mkdir(parents=True,exist_ok=True)
                origin=old/'files'/('attachments' if kind=='attachme' else kind)
                if origin.exists():
                    for item in origin.iterdir():
                        if not item.is_file():raise ValueError('Nested legacy file store needs manual review: '+str(item))
                        path=file_path(files,kind,item.name);path.parent.mkdir(parents=True,exist_ok=True)
                        shutil.copy2(item,path)
            oldfiles=old/'files'
            if oldfiles.exists() and any(p.name not in {'attachments','avatars'} for p in oldfiles.iterdir()):
                raise ValueError('Unrecognized files directory entries: '+host)
        certs=source/'certs'
        if certs.exists():
            for tenant in certs.iterdir():
                key=tenant.name if tenant.name in {'admin','local'} else mappings.get(tenant.name)
                if not key:raise ValueError('Unregistered certificate tenant: '+tenant.name)
                shutil.copytree(tenant,stage/'certs'/key)
        for path in stage.rglob('*'):
            if not SHORT.fullmatch(path.name):raise ValueError('Non-8.3 destination component: '+str(path))
        # Destination remains absent on every preparation failure; original is untouched.
        if destination.exists() or destination.is_symlink():raise ValueError('Destination appeared during migration')
        stage.rename(destination)
        stage=None
    finally:
        if stage is not None:shutil.rmtree(stage)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source');parser.add_argument('destination')
    args=parser.parse_args()
    try:migrate(args.source,args.destination)
    except (ValueError,OSError,sqlite3.Error,AssertionError) as error:parser.exit(1,str(error)+'\n')
    print('Copied and verified. Keep the server stopped while switching data roots; retain the original as backup. Fresh sign-in is required.')
