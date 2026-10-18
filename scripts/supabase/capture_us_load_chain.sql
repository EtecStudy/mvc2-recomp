-- Read-only bounded windows, NOT full ELF delivery. Do not commit returned bytes.
-- Copy only under ignored game/working/slus_20486/load_chain and check each SHA.
WITH elf AS (
 SELECT string_agg(decode(payload,'base64'),''::bytea ORDER BY idx) AS b
 FROM public.bootstrap_transfer WHERE kind='us_elf_chunk'
), ranges(name,va,n) AS (
 VALUES ('load_core',1096048,552),('load_entry',1096600,160),('load_bind',1094040,400)
), slices AS (
 SELECT name,va,n,substring(b FROM (va-1048448+1) FOR n) AS bytes
 FROM ranges CROSS JOIN elf
 WHERE octet_length(b)=3942320 AND encode(sha256(b),'hex')=
  '48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7'
)
SELECT name,'0x'||lpad(to_hex(va),8,'0') AS va,n,
 encode(sha256(bytes),'hex') AS sha256,encode(bytes,'hex') AS hex
FROM slices ORDER BY va;
