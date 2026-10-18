import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sdk', ROOT/'scripts/match_sdk_window.py')
sdk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sdk)


class SdkTests(unittest.TestCase):
    def database(self, data, relocations, name='unit_function'):
        normalized, _ = sdk.normalize(data, relocations)
        return {'unit_library': {name: {hashlib.sha1(normalized).hexdigest(): {'variant': {
            'type':'FUNCTION','size':len(data),'versions':['unit fixture'], 'relocations':relocations}}}}}

    def test_full_masked_hash_not_prefix_or_call_address(self):
        data = struct.pack('<16I',0x0c040000,0x3c040001,*([0x2402002a]*14))
        relocs = {'0':{'type':'MIPS_26','symbol':'unit_callee'}, '4':{'type':'MIPS_HI16','symbol':'unit_data'}}
        db = self.database(data, relocs)
        changed = struct.pack('<II',0x0c080000,0x3c040099)+data[8:]
        matches = sdk.match_prefix(changed, db, 0x100000)
        self.assertEqual(sdk.classify(matches),'unique_full_hash_match')
        self.assertEqual(matches[0]['unmasked_bits'],470)
        self.assertEqual(matches[0]['annotated_direct_transfers'][0]['target'],'0x00200000')
        self.assertFalse(matches[0]['annotated_direct_transfers'][0]['target_body_hash_verified_by_this_record'])
        bad = changed[:8]+b'\0'*4+changed[12:]
        self.assertEqual(sdk.match_prefix(bad,db,0x100000),[])
        self.assertEqual(sdk.match_prefix(data[:32],db,0x100000),[])

    def test_short_signature_and_ambiguity_do_not_assign_identity(self):
        data = struct.pack('<8I',0x0c040000,*([0]*7))
        relocs = {'0':{'type':'MIPS_26','symbol':'unit_callee'}}
        db = self.database(data,relocs)
        candidates = sdk.match_prefix(data,db,0x100000)
        self.assertEqual(candidates[0]['unmasked_bits'],230)
        self.assertEqual(sdk.classify(candidates),'short_signature_candidate')
        db['unit_library']['second_identity']=db['unit_library']['unit_function']
        self.assertEqual(sdk.classify(sdk.match_prefix(data,db,0x100000)),'ambiguous_identity')

    def test_relocation_validation(self):
        for r in ({'0':{'type':'unknown'}},{'1':{'type':'MIPS_26'}},
                  {'32':{'type':'MIPS_26'}},{'-4':{'type':'MIPS_26'}},
                  {'0':{'type':'NONE'},'00':{'type':'NONE'}}):
            with self.subTest(relocations=r),self.assertRaises(ValueError): sdk.normalize(bytes(32),r)
        data = struct.pack('<I',0x2402002a)+bytes(28)
        db = self.database(data,{'0':{'type':'MIPS_26','symbol':'not_a_call'}})
        with self.assertRaisesRegex(ValueError,'not a J/JAL'): sdk.match_prefix(data,db,0x100000)

    def test_header_chunk_length_verified(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'source.h'
            p.write_text('kSymbolsJsonChunks[] = {R"PS2SDB({})PS2SDB", 2}\n    };')
            self.assertEqual(sdk.load_embedded(p),{})
            p.write_text(p.read_text().replace(', 2}',', 3}'))
            with self.assertRaises(ValueError): sdk.load_embedded(p)

    def test_window_hash_gate_and_offsets(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t);(p/'unit.bin').write_bytes(bytes(32))
            w={'name':'unit','bytes':32,'sha256':hashlib.sha256(bytes(32)).hexdigest(),'entry_offsets':[0]}
            m={'windows':[w]}
            self.assertEqual(sdk.verify_windows(p,m),32)
            w['entry_offsets']=[1]
            with self.assertRaises(ValueError): sdk.verify_windows(p,m)
            w['entry_offsets']=[0];w['sha256']='invalid'
            with self.assertRaisesRegex(ValueError,'Unverified'): sdk.verify_windows(p,m)
            w['name']='../escape'
            with self.assertRaisesRegex(ValueError,'Unsafe'): sdk.verify_windows(p,m)


if __name__ == '__main__': unittest.main()
