#!/usr/bin/env python3
"""Generate the built-in model field contract from schema.sql; no runtime Python."""
import json
import sys
from pathlib import Path
import sqlite3
root=Path(__file__).resolve().parents[1]
collections={'boards':'boards','swimlanes':'swimlanes','lists':'lists','cards':'cards','card_comments':'card_comments','checklists':'checklists','checklist_items':'checklistItems','custom_fields':'customFields','users':'users','activities':'activities','attachments':'attachments'}
booleans=set('archived collapsed isOvertime starred wip_enabled wip_soft dueComplete showActivities showListOnMinicard showChecklistAtMinicard hideFinishedChecklistIfItemsAreHidden hideCheckedChecklistItems hideAllChecklistItems isFinished showOnCard automaticallyOnCard alwaysOnCard showLabelOnMiniCard showSumAtTopOfList readOnly adminOnly isAdmin loginDisabled createdThroughApi'.split())
managed={'boards':['labels','members','orgs','teams','domains'],'cards':['members','assignees','labelIds','customFields','cardDependencies'],'custom_fields':['boardIds','settings.dropdownItems'],'users':['emails']}
db=sqlite3.connect(':memory:');db.executescript((root/'src/schema.sql').read_text())
models=[]
for table,collection in collections.items():
    fields=[]
    for _,name,typ,required,default,pk in db.execute('PRAGMA table_info('+table+')'):
        path='_id' if name=='id' else name
        kind='scalar'
        if name in ['settings_json','extra_json','data_json']:path='';kind='extra'
        elif name in ['services_json','profile_json']:path=name[:-5];kind='json'
        elif name.startswith('wip_'):path='wipLimit.'+name[4:]
        if name in booleans:kind='bool'
        elif name.endswith('At') or name in ['heartbeat','lastConnectionDate','dateLastActivity']:kind='date'
        if table=='attachments' and name in ['boardId','swimlaneId','listId','cardId']:path='meta.'+name
        if table=='custom_fields' and name in ['currencyCode','stringtemplateFormat','stringtemplateSeparator']:path='settings.'+name
        if table=='custom_fields' and name=='settings_json':path='settings';kind='extra'
        value=db.execute('SELECT '+default).fetchone()[0] if default is not None else None
        fields.append(dict(name=name,path=path,kind=kind,type=typ,required=bool(required or pk),default=value))
    for field in fields:
        if field['kind']=='extra' and field['path']:
            prefix=field['path']+'.'
            paths=[item['path'] for item in fields]+managed.get(table,[])
            field['exclude']=sorted({path[len(prefix):].split('.')[0] for path in paths if path.startswith(prefix)})
    foreign_keys=[dict(column=row[3],parent=row[2],key=row[4],delete=row[6]) for row in db.execute('PRAGMA foreign_key_list('+table+')')]
    unique_keys=[[col[2] for col in db.execute('PRAGMA index_info('+index[1]+')')] for index in db.execute('PRAGMA index_list('+table+')') if index[2] and index[3]!='pk']
    models.append(dict(table=table,collection=collection,fields=fields,managed=managed.get(table,[]),foreignKeys=foreign_keys,uniqueKeys=unique_keys))
relations=[]
relation_map={
 'board_labels':('boards','boardId','labels',False),
 'board_members':('boards','boardId','members',False),
 'board_orgs':('boards','boardId','orgs',False),
 'board_teams':('boards','boardId','teams',False),
 'board_domains':('boards','boardId','domains',False),
 'card_members':('cards','cardId','members',True),
 'card_assignees':('cards','cardId','assignees',True),
 'card_labels':('cards','cardId','labelIds',True),
 'card_custom_field_values':('cards','cardId','customFields',False),
 'card_dependencies':('cards','cardId','cardDependencies',False),
 'custom_field_boards':('custom_fields','customFieldId','boardIds',True),
 'custom_field_dropdown_items':('custom_fields','customFieldId','settings.dropdownItems',False),
 'user_emails':('users','userId','emails',False),
}
for table,(parent,parent_key,path,scalar) in relation_map.items():
    fields=[];keys=[]
    for _,name,typ,required,default,pk in db.execute('PRAGMA table_info('+table+')'):
        if name==parent_key:continue
        field_path='_id' if (table in ['board_labels','custom_field_dropdown_items'] and name=='id') or name=='customFieldId' else name
        if table=='card_dependencies' and name=='targetCardId':field_path='cardId'
        kind='bool' if name.startswith('is') or name=='verified' else 'scalar'
        value=db.execute('SELECT '+default).fetchone()[0] if default is not None else None
        fields.append(dict(name=name,path=field_path,kind=kind,type=typ,required=bool(required or pk),default=value))
        if pk:keys.append(field_path)
    relations.append(dict(table=table,parent=parent,parentKey=parent_key,path=path,scalar=scalar,fields=fields,keys=keys))
def constant(name,data):
    text=json.dumps(data,ensure_ascii=False,separators=(',',':'))
    lines=[text[i:i+180] for i in range(0,len(text),180)]
    return 'const '+name+'=\n'+'+\n'.join("  '"+line.replace("'","''")+"'" for line in lines)+';\n'
output='unit wlmodels;\n{$mode objfpc}{$H+}\ninterface\n// Generated by releases/genmodel.py from schema.sql. Do not edit by hand.\n'+constant('ModelJson',models)+constant('RelationJson',relations)+'implementation\nend.\n'
target=root/'src/wlmodels.pas'
if '--check' in sys.argv:
    if not target.exists() or target.read_text()!=output:raise SystemExit('Run releases/genmodel.py after changing schema.sql')
else:target.write_text(output)
