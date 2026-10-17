-- Read-only, bounded fact/byte capture. Original Storage and JP rows untouched.
-- Results are small; write bytes ONLY under ignored game/working/, verify all
-- individual hashes before running scripts/fase1_windows.sh. NOT the full ELF.
WITH elf AS (
  SELECT string_agg(decode(payload, 'base64'), ''::bytea ORDER BY idx) AS b
  FROM public.bootstrap_transfer WHERE kind = 'us_elf_chunk'
), windows(name, va, n) AS (
  VALUES ('boot',1048576,128), ('usb_init',4113840,288),
         ('audio_init',4300416,320), ('network_init',4325664,256)
), slices AS (
  SELECT name, va, n, substring(b FROM (va - 1048448 + 1) FOR n) AS bytes
  FROM windows CROSS JOIN elf
  WHERE octet_length(b) = 3942320 AND encode(sha256(b),'hex') =
    '48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7'
)
SELECT name, to_hex(va) AS va, n, encode(sha256(bytes),'hex') AS sha256,
       encode(bytes,'hex') AS hex
FROM slices ORDER BY va;
