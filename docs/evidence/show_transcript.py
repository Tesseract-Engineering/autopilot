import json,sys
for l in open(sys.argv[1]):
    try: d=json.loads(l)
    except: continue
    t=d.get('type'); st=d.get('subtype','')
    if t=='system' and 'hook' in st:
        keep={k:d[k] for k in d if k not in('session_id','uuid','type','subtype')}
        print('HOOK', st, json.dumps(keep)[:1200])
    elif t=='assistant':
        for c in d['message']['content']:
            if c['type']=='text': print('ASSISTANT:', c['text'][:400])
            elif c['type']=='tool_use': print('TOOL:', c['name'], json.dumps(c['input'])[:200])
    elif t=='user':
        cont=d['message'].get('content')
        if isinstance(cont,str): print('USER:', cont[:800])
        else:
            for c in cont or []:
                if c.get('type')=='tool_result': print('RESULT:', str(c.get('content'))[:300])
                elif c.get('type')=='text': print('USER-TEXT:', c['text'][:800])
    elif t=='result': print('FINAL', d.get('subtype'), 'turns=',d.get('num_turns'), str(d.get('result'))[:300])
