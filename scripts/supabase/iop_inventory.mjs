// Read-only IRX/ROMDIR metadata parser. No relocation or execution is claimed.
const decoder = new TextDecoder();
export const hex = n => '0x' + (n >>> 0).toString(16).padStart(8, '0');
function reader(b) {
  const d = new DataView(b.buffer, b.byteOffset, b.byteLength);
  function range(o, n) { if (!Number.isInteger(o) || !Number.isInteger(n) || o < 0 || n < 0 || o + n > b.length) throw Error('Binary range out of bounds'); }
  return {range, u16(o) {range(o,2);return d.getUint16(o,true);}, u32(o) {range(o,4);return d.getUint32(o,true);},
    name(o,n) {range(o,n);let e=o;while(e<o+n&&b[e])e++;return decoder.decode(b.subarray(o,e));}};
}
export function parseElf(b) {
  const r=reader(b);r.range(0,52);
  if(b[0]!==127||b[1]!==69||b[2]!==76||b[3]!==70||b[4]!==1||b[5]!==1||r.u16(18)!==8)throw Error('Not ELF32 LE MIPS');
  const ph=[],sh=[];const pn=r.u16(44),sn=r.u16(48),po=r.u32(28),so=r.u32(32),ps=r.u16(42),ss=r.u16(46);
  if(pn>4096||sn>4096||(pn&&ps<32)||(sn&&ss<40))throw Error('Invalid ELF tables');
  r.range(po,pn*ps);r.range(so,sn*ss);
  for(let i=0;i<pn;i++){const o=po+i*ps;const p={type:r.u32(o),offset:r.u32(o+4),va:r.u32(o+8),filesz:r.u32(o+16),memsz:r.u32(o+20),flags:r.u32(o+24)};r.range(p.offset,p.filesz);ph.push(p);}
  for(let i=0;i<sn;i++){const o=so+i*ss;const s={name_index:r.u32(o),type:r.u32(o+4),flags:r.u32(o+8),va:r.u32(o+12),offset:r.u32(o+16),size:r.u32(o+20),entsize:r.u32(o+36)};if(s.type!==8&&s.size)r.range(s.offset,s.size);sh.push(s);}
  const names=sh[r.u16(50)];for(const s of sh)s.name=names&&s.name_index<names.size?r.name(names.offset+s.name_index,names.size-s.name_index):'';
  const regions=sh.filter(s=>(s.flags&2)&&s.type!==8&&s.size).map(s=>({offset:s.offset,size:s.size,va:s.va}));
  if(!regions.length)for(const p of ph)if(p.type===1&&p.filesz)regions.push({offset:p.offset,size:p.filesz,va:p.va});
  // IRX export slot zero can be _start at link offset 0, not a terminator.
  // R_MIPS_32 on that slot makes it non-null after relocation. Do not truncate.
  const relocations={},relocated32=new Set();
  for(const s of sh)if(s.type===9||s.type===4){const width=s.entsize||(s.type===9?8:12);if(width<(s.type===9?8:12)||s.size%width)throw Error('Bad relocation entries');for(let o=s.offset;o+width<=s.offset+s.size;o+=width){const type=r.u32(o+4)&255;relocations[type]=(relocations[type]||0)+1;if(type===2)relocated32.add(r.u32(o));}}
  const imports=[],exports=[],seen=new Set();
  for(const region of regions){const end=region.offset+region.size;for(let o=(region.offset+3)&~3;o+20<=end;o+=4){const magic=r.u32(o);if(![0x41e00000,0x41c00000].includes(magic)||seen.has(o))continue;
    const name=r.name(o+12,8);if(!/^[A-Za-z0-9_]{1,8}$/.test(name))continue;seen.add(o);
    const table={name,version:r.u16(o+8),flags:r.u16(o+10),file_offset:o,link_va:hex(region.va+o-region.offset),complete:false};
    if(magic===0x41e00000){table.ordinals=[];for(let c=o+20;c+8<=end;c+=8){const a=r.u32(c),z=r.u32(c+4);if(a===0&&z===0){table.complete=true;break;}if(a!==0x03e00008||(z>>>16)!==0x2400)break;table.ordinals.push(z&65535);if(table.ordinals.length>4096)throw Error('Too many imports');}imports.push(table);}
    else{table.function_offsets=[];table.zero_relocation_slots=[];for(let c=o+20;c+4<=end;c+=4){const a=r.u32(c);if(a===0&&!relocated32.has(region.va+c-region.offset)){table.complete=true;break;}if(a===0)table.zero_relocation_slots.push(table.function_offsets.length);table.function_offsets.push(hex(a));if(table.function_offsets.length>4096)throw Error('Too many exports');}exports.push(table);}
  }}

  return {elf_type:r.u16(16),entry:hex(r.u32(24)),flags:hex(r.u32(36)),program_headers:ph,sections:sh.map(s=>({name:s.name,type:s.type,flags:s.flags,offset:s.offset,size:s.size,link_va:hex(s.va)})),imports,exports,relocations,
    warning:'Link-time offsets only for relocatable IRX; no runtime load base, compatibility or execution inferred.'};
}
export function parseRomDir(b) {
  const r=reader(b),align=n=>Math.ceil(n/16)*16;
  for(let start=0;start+16<=Math.min(b.length,65536);start+=16){if(r.name(start,10)!=='RESET')continue;
    const entries=[];let extent=0,terminated=false,valid=true;
    for(let i=0;i<1024&&start+16*(i+1)<=b.length;i++){const o=start+i*16,name=r.name(o,10);if(!name){terminated=true;break;}if(!/^[A-Za-z0-9_.$-]{1,10}$/.test(name)){valid=false;break;}
      const size=r.u32(o+12);if(extent+size>b.length){valid=false;break;}
      entries.push({name,file_offset:extent,bytes:size,extinfo_bytes:r.u16(o+10)});extent+=align(size);
    }
    const dir=entries.find(e=>e.name==='ROMDIR');
    if(valid&&terminated&&dir&&dir.file_offset===start&&dir.bytes>=(entries.length+1)*16){return {table_offset:start,used_aligned_bytes:extent,entries};}
  }
  throw Error('No self-consistent RESET/ROMDIR table found');
}
export async function sha256(b) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',b))].map(n=>n.toString(16).padStart(2,'0')).join('');
}
