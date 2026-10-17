// Bundle with iop_inventory.mjs (remove its `export ` keywords) for deployment.
// Replace sentinel ONLY in an ignored local deployment copy; delete after use.
const TOKEN = '__TEMPORARY_STAGE_TOKEN__';
Deno.serve(async req => {
  if (req.method !== 'POST' || req.headers.get('x-stage-token') !== TOKEN || TOKEN.startsWith('__')) return new Response('Forbidden',{status:403});
  const base=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const auth={apikey:key,Authorization:`Bearer ${key}`};
  async function object(path){const r=await fetch(`${base}/storage/v1/object/ps2recomp/${path}`,{headers:auth});if(!r.ok)throw Error(`Storage ${path}: ${r.status}`);return new Uint8Array(await r.arrayBuffer());}
  async function list(prefix){const r=await fetch(`${base}/storage/v1/object/list/ps2recomp`,{method:'POST',headers:{...auth,'Content-Type':'application/json'},body:JSON.stringify({prefix,limit:100,sortBy:{column:'name',order:'asc'}})});if(!r.ok)throw Error(`List ${r.status}`);const rows=await r.json();if(rows.length>=100)throw Error('Listing may be truncated');return rows;}
  async function stage(kind,idx,payload){const r=await fetch(`${base}/rest/v1/bootstrap_transfer`,{method:'POST',headers:{...auth,'Content-Type':'application/json'},body:JSON.stringify({kind,idx,payload:JSON.stringify(payload)})});if(!r.ok)throw Error(`Stage ${kind}: ${r.status}`);}
  try {
    const prior=await fetch(`${base}/rest/v1/bootstrap_transfer?kind=eq.us_iop_complete_v2&select=id&limit=1`,{headers:auth});
    if(!prior.ok)throw Error(`Completion check ${prior.status}`);
    if((await prior.json()).length)return Response.json({error:'v2 already complete; refusing duplicate staging'},{status:409});
    const elf=await object('SLUS_204.86');
    if(await sha256(elf)!=='48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7')throw Error('US ELF changed');
    const files=(await list('MODULES')).filter(f=>/^[A-Z0-9_.-]+\.IRX$/.test(f.name));
    let failed=0;
    for(let i=0;i<files.length;i++){
      const path='MODULES/'+files[i].name,b=await object(path);let facts;
      try{facts=parseElf(b);}catch(e){facts={error:String(e)};failed++;}
      await stage('us_iop_module_v2',i,{path,bytes:b.length,sha256:await sha256(b),...facts});
    }
    const rom=await object('MODULES/IOPRP255.IMG'),directory=parseRomDir(rom);
    await stage('us_romdir_v2',0,{path:'MODULES/IOPRP255.IMG',bytes:rom.length,sha256:await sha256(rom),...directory});
    let romModules=0;
    for(const e of directory.entries){const b=rom.subarray(e.file_offset,e.file_offset+e.bytes);
      if(b[0]===127&&b[1]===69&&b[2]===76&&b[3]===70){let facts;try{facts=parseElf(b);}catch(error){facts={error:String(error)};failed++;}await stage('us_rom_module_v2',romModules++,{path:'MODULES/IOPRP255.IMG#'+e.name,bytes:b.length,sha256:await sha256(b),...facts});}
      if(e.name==='IOPBTCONF')await stage('us_iopbtconf_v2',0,{name:e.name,text:new TextDecoder().decode(b)});
    }
    const afs=[];for(const f of (await list('PS2')).filter(f=>/^[A-Z0-9_.-]+\.AFS$/.test(f.name))){const path='PS2/'+f.name,b=await object(path),d=new DataView(b.buffer);if(b.length<8||d.getUint32(0,true)!==0x00534641)throw Error(`Not AFS: ${path}`);const count=d.getUint32(4,true);if(8+count*8>b.length)throw Error('AFS directory out of bounds');let required=0,nonempty=0;for(let i=0;i<count;i++){const off=d.getUint32(8+i*8,true),size=d.getUint32(12+i*8,true);required=Math.max(required,off+size);if(size)nonempty++;}afs.push({path,bytes:b.length,sha256:await sha256(b),entries:count,nonempty_entries:nonempty,required_payload_end:required,payload_extents_in_bounds:required<=b.length});}
    const filelist=await object('PS2/0FLIST.DIR');
    await stage('us_asset_headers_v2',0,{afs,filelist_bytes:filelist.length,filelist_sha256:await sha256(filelist),filelist_printable_text:[...filelist].every(n=>n===0||n===9||n===10||n===13||(n>=32&&n<=126))?new TextDecoder().decode(filelist):null,warning:'Only uploaded AFS payload extents checked, not disc completeness or filename-table validity.'});
    const summary={serial:'SLUS_204.86',disk_irx:files.length,rom_entries:directory.entries.length,rom_elf_modules:romModules,failed,afs:afs.length,finished_at:new Date().toISOString(),originals_written:false};
    await stage('us_iop_complete_v2',0,summary);return Response.json(summary);
  }catch(e){try{await stage('us_iop_error_v2',0,{error:String(e)});}catch{}return Response.json({error:String(e)},{status:500});}
});
