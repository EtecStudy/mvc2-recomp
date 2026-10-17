import test from 'node:test';
import assert from 'node:assert/strict';
import {parseElf,parseRomDir} from '../scripts/supabase/iop_inventory.mjs';
function fixture(){
 const b=new Uint8Array(0x250),d=new DataView(b.buffer),u16=(o,v)=>d.setUint16(o,v,true),u32=(o,v)=>d.setUint32(o,v,true);
 b.set([127,69,76,70,1,1,1]);u16(16,0xff80);u16(18,8);u32(28,52);u32(32,0x200);u16(40,52);u16(42,32);u16(44,1);u16(46,40);u16(48,2);
 u32(52,1);u32(56,0x80);u32(68,0x100);u32(72,0x100);u32(76,7);
 u32(0x200+40+4,1);u32(0x200+40+8,6);u32(0x200+40+16,0x80);u32(0x200+40+20,0x100);
 u32(0x80,0x41e00000);u16(0x88,0x101);b.set(new TextEncoder().encode('loadcore'),0x8c);u32(0x94,0x03e00008);u32(0x98,0x24000006);
 u32(0xc0,0x41c00000);u16(0xc8,0x102);b.set(new TextEncoder().encode('testlib'),0xcc);u32(0xd4,0x40);u32(0xd8,0x48);
 return {b,d};
}
test('ELF tables, import ordinal and exports are bounded and decoded',()=>{
 const {b}=fixture(),m=parseElf(b);assert.equal(m.elf_type,0xff80);assert.equal(m.imports[0].name,'loadcore');assert.deepEqual(m.imports[0].ordinals,[6]);assert.equal(m.imports[0].version,0x101);assert.equal(m.imports[0].complete,true);assert.deepEqual(m.exports[0].function_offsets,['0x00000040','0x00000048']);
});
test('malformed/truncated ELF rejected; malformed import not called complete',()=>{
 assert.throws(()=>parseElf(new Uint8Array(51)));let {b,d}=fixture();d.setUint32(56,0xffffffff,true);assert.throws(()=>parseElf(b));({b,d}=fixture());d.setUint32(0x98,0x25000006,true);const table=parseElf(b).imports[0];assert.equal(table.complete,false);assert.deepEqual(table.ordinals,[]);
});
test('ROMDIR accepts only self-consistent aligned extents and termination',()=>{
 const b=new Uint8Array(112),d=new DataView(b.buffer),entry=(o,name,size)=>{b.set(new TextEncoder().encode(name),o);d.setUint32(o+12,size,true);};
 entry(32,'RESET',32);entry(48,'ROMDIR',64);entry(64,'MODULE',4);
 const rom=parseRomDir(b);assert.equal(rom.table_offset,32);assert.deepEqual(rom.entries.map(e=>e.file_offset),[0,32,96]);
 d.setUint32(48+12,16,true);assert.throws(()=>parseRomDir(b));
});

test('relocated zero export is a function slot, not an export terminator',()=>{
 const f=fixture(),b=new Uint8Array(0x300);b.set(f.b);const d=new DataView(b.buffer);
 d.setUint16(48,3,true);d.setUint32(0x250+4,9,true);d.setUint32(0x250+16,0x2c0,true);d.setUint32(0x250+20,8,true);d.setUint32(0x250+36,8,true);
 d.setUint32(0xd4,0,true); // _start at relative offset zero, fixed up on load
 d.setUint32(0x2c0,0x54,true);d.setUint32(0x2c4,2,true); // R_MIPS_32 for export slot
 const table=parseElf(b).exports[0];
 assert.deepEqual(table.function_offsets,['0x00000000','0x00000048']);
 assert.deepEqual(table.zero_relocation_slots,[0]);assert.equal(table.complete,true);
});
