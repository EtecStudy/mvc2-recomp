-- Executed as migration us_iop_metadata_inventory_v2 (2026-10-17).
-- Derived tracker metadata only; never writes Storage or Japanese records.
-- Unknown runtime state/base/instruction counts intentionally remain defaults.
INSERT INTO public.elf_modules (target_id,name,kind,size_bytes,notes)
SELECT t.id,s.payload::jsonb->>'path','iop_irx',
 (s.payload::jsonb->>'bytes')::bigint,
 'USA static metadata only; not loaded/executed. SHA-256='||(s.payload::jsonb->>'sha256')||
 '; imports='||jsonb_array_length(s.payload::jsonb->'imports')||
 '; exports='||jsonb_array_length(s.payload::jsonb->'exports')||
 '. Source us_iop_module_v2/us_rom_module_v2; R_MIPS_32 zero export slots preserved. Runtime base and instruction count unknown.'
FROM public.bootstrap_transfer s CROSS JOIN public.build_targets t
WHERE s.kind IN ('us_iop_module_v2','us_rom_module_v2')
 AND t.slug='mvc2-slus-204-86'
 AND EXISTS(SELECT 1 FROM public.bootstrap_transfer
            WHERE kind='us_iop_complete_v2' AND payload::jsonb->>'failed'='0')
ON CONFLICT (target_id,name) DO NOTHING;

WITH hashes AS (
 SELECT payload::jsonb->>'path' AS path,payload::jsonb->>'sha256' AS sha
 FROM public.bootstrap_transfer WHERE kind='us_iop_module_v2'
 UNION ALL
 SELECT payload::jsonb->>'path',payload::jsonb->>'sha256'
 FROM public.bootstrap_transfer WHERE kind='us_romdir_v1'
 UNION ALL
 SELECT e->>'path',e->>'sha256'
 FROM public.bootstrap_transfer s
 CROSS JOIN LATERAL jsonb_array_elements(s.payload::jsonb->'afs') e
 WHERE s.kind='us_asset_headers_v1'
)
UPDATE public.disc_files d
SET sha256=h.sha,
 notes=coalesce(d.notes,'')||' Content SHA-256 verified read-only in USA IOP/assets pass 2026-10-17.',
 updated_at=now()
FROM hashes h,public.build_targets t
WHERE d.target_id=t.id AND t.slug='mvc2-slus-204-86'
 AND d.path='/'||h.path AND d.sha256 IS NULL;
