begin;

with rows(content_hash,object_path,mime_type,metadata) as (
    values
    ('8527c8faba38d77c8ecdc13a4e567b9424940440790528921a93f43a16f06011',
     'KWEICHOW_MOUTAI/2021/2021H1-publication-archive.html',
     'text/html',
     '{"source_role":"publication_event","byte_size_pending":true}'::jsonb),
    ('709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71',
     'KWEICHOW_MOUTAI/2021/2021H1-numeric-archive.html',
     'text/html',
     '{"source_role":"numeric_cross_check","byte_size_pending":true}'::jsonb),
    ('c7a935619b026f92f45978727d0d1c3535416f25bd667fd6a5b527625a38661a',
     'KWEICHOW_MOUTAI/2021/2021-08-30-price-cross-check.html',
     'text/html',
     '{"source_role":"price_cross_check","byte_size_pending":true}'::jsonb)
)
insert into audit.evidence_objects (
    document_id,bucket_id,object_path,content_hash,byte_size,mime_type,
    upload_status,metadata
)
select d.document_id,'research-evidence',rows.object_path,rows.content_hash,
       0,rows.mime_type,'registered',rows.metadata
from rows
join raw.documents d on d.content_hash=rows.content_hash
on conflict (document_id) do update set
    object_path=excluded.object_path,
    content_hash=excluded.content_hash,
    mime_type=excluded.mime_type,
    metadata=audit.evidence_objects.metadata || excluded.metadata;

commit;
