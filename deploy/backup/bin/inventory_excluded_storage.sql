\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'

select case
  when to_regclass('storage.buckets_vectors') is null then
    $$select 'storage.buckets_vectors', 'f', 0::bigint$$
  else
    $$select 'storage.buckets_vectors', 't', count(*)::bigint from storage.buckets_vectors$$
end \gexec

select case
  when to_regclass('storage.vector_indexes') is null then
    $$select 'storage.vector_indexes', 'f', 0::bigint$$
  else
    $$select 'storage.vector_indexes', 't', count(*)::bigint from storage.vector_indexes$$
end \gexec
