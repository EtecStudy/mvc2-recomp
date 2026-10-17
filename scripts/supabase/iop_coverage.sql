-- Read-only v2 only: null export slots with R_MIPS_32 were preserved.
-- Major-version matching reflects pinned IopImportRegistry::findLibrary.
-- This is static span availability, NOT a successful runtime link test.
WITH modules AS (
 SELECT payload::jsonb AS m FROM public.bootstrap_transfer
 WHERE kind IN ('us_iop_module_v2','us_rom_module_v2')
), imports AS (
 SELECT m->>'path' AS path,t->>'name' AS lib,(t->>'version')::int AS version,t->'ordinals' AS ordinals
 FROM modules CROSS JOIN LATERAL jsonb_array_elements(m->'imports') t
), exports AS (
 SELECT m->>'path' AS path,t->>'name' AS lib,(t->>'version')::int AS version,
        jsonb_array_length(t->'function_offsets') AS slots
 FROM modules CROSS JOIN LATERAL jsonb_array_elements(m->'exports') t
), coverage AS (
 SELECT i.*, CASE
  WHEN EXISTS(SELECT 1 FROM exports e WHERE e.lib=i.lib AND (e.version>>8)=(i.version>>8)
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(i.ordinals) o WHERE o::int>=e.slots))
   THEN 'ordinal_span_available'
  WHEN EXISTS(SELECT 1 FROM exports e WHERE e.lib=i.lib) THEN 'version_or_ordinal_gap'
  ELSE 'no_uploaded_export' END AS status FROM imports i
)
SELECT status,count(*) AS tables,string_agg(DISTINCT lib,',' ORDER BY lib) AS libraries
FROM coverage GROUP BY status ORDER BY status;
