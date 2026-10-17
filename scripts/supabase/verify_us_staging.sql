-- Read-only proof over US chunks. Does NOT read or update JP staging.
WITH elf AS (
  SELECT count(*) AS chunks, count(DISTINCT idx) AS distinct_chunks,
         min(idx) AS first_idx, max(idx) AS last_idx,
         string_agg(decode(payload, 'base64'), ''::bytea ORDER BY idx) AS bytes
  FROM public.bootstrap_transfer WHERE kind = 'us_elf_chunk'
)
SELECT chunks, distinct_chunks, first_idx, last_idx,
       octet_length(bytes) AS bytes,
       encode(sha256(bytes), 'hex') AS sha256,
       chunks = 41 AND distinct_chunks = 41 AND first_idx = 0 AND last_idx = 40
       AND octet_length(bytes) = 3942320
       AND encode(sha256(bytes), 'hex') =
         '48ebf907d8149122ca9bd622ed11c290d5f93173078ea5bd570e1ac5566f13d7' AS verified
FROM elf;
