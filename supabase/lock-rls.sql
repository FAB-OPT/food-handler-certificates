-- ════════════════════════════════════════════════════════════════════
-- ล็อกสิทธิ์ Supabase — ต้องล็อกอินก่อนถึงจะแตะข้อมูลได้
--
-- ปัญหา: ทุกตารางตั้ง policy เป็น "for all to anon using (true)" ซึ่งแปลว่า
-- ใครก็ตามที่เปิดหน้าเว็บแล้วก๊อป publishable key ออกไป (คีย์อยู่ในหน้าเว็บ
-- สาธารณะ ปิดไม่ได้) สามารถอ่าน แก้ หรือลบข้อมูลทั้งหมดได้จากเทอร์มินัล
--
-- วัดจากของจริงเมื่อ 7 ก.ย. 2569 ด้วยคีย์ที่อยู่ในหน้าเว็บ:
--   fh_employees      1,987 แถว  — ชื่อพนักงาน + เลขบัตรประชาชน
--   fh_certificates     829 แถว
--   fh_requests         343 แถว  — ชื่อ + เลขบัตรประชาชน
--   fh_config             6 แถว  — รายชื่อผู้ใช้และรหัสเข้าระบบของทุกคน
-- ทั้งหมดอ่านได้โดยไม่ต้องล็อกอินอะไรเลย
--
-- ที่แก้: เปลี่ยนจาก "to anon" เป็น "to authenticated"
-- แอปทุกตัวล็อกอินแบบไม่ระบุตัวตนให้เองตอนเปิดหน้า ผู้ใช้ไม่ต้องทำอะไรเพิ่ม
--
-- ที่ยังไม่ได้แก้: ล็อกอินแบบไม่ระบุตัวตนทำให้ทุกคนที่เข้าหน้าเว็บได้สิทธิ์
-- เท่ากัน จึงยังไม่ใช่การแยกสิทธิ์รายคน แต่ปิดช่องที่ใหญ่กว่าและง่ายกว่ามาก
-- คือการยิงตรงเข้า API จากนอกระบบ
--
-- ═══ ต้องทำก่อนรันไฟล์นี้ ═══
-- 1. Supabase Dashboard → Authentication → Sign In / Providers
--    → เปิด "Allow anonymous sign-ins"
-- 2. เว็บสามหน้าที่แก้แล้วต้องขึ้นออนไลน์ก่อน:
--    hub/index.html · hub/modules/online-form.html · Training Record/index.html
--    ถ้าล็อก policy ก่อนโค้ดขึ้น ระบบจะใช้งานไม่ได้ทันที
--
-- รันไฟล์นี้ได้กับ "ทั้งสองโปรเจกต์" (วนทุกตารางใน public เอง ไม่ต้องแก้ชื่อ)
--   FAB HUB / Training Record  →  cyjfgperenakjeazsfgf
--   แบบฟอร์มออนไลน์            →  pzspcjqlxoqnbtvlfjsy
--
-- ถอยกลับได้: เปลี่ยน 'authenticated' บรรทัดล่างเป็น 'anon' แล้วรันใหม่
-- ════════════════════════════════════════════════════════════════════

do $$
declare
  t record;
  p record;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    -- เปิด RLS ทุกตาราง — ตารางที่ลืมเปิดคือตารางที่ policy ไม่มีผลเลย
    execute format('alter table public.%I enable row level security', t.tablename);

    -- ล้าง policy เดิมของตารางนั้นให้หมด แล้วสร้างใหม่ชุดเดียว
    -- (ล้างทั้งหมดเพราะ policy เก่าชื่อไม่เหมือนกันทุกตาราง ไล่ทีละชื่อจะตกหล่น)
    for p in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t.tablename
    loop
      execute format('drop policy %I on public.%I', p.policyname, t.tablename);
    end loop;

    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true)',
      t.tablename || '_auth_all', t.tablename);
  end loop;
end $$;


-- ───────────── ตรวจผลหลังรัน ─────────────
-- ทุกแถวต้องเป็น rls_on = true และ roles = {authenticated}
-- ถ้าเห็น {anon} หรือ {public} แถวไหน แปลว่าตารางนั้นยังเปิดอยู่
select
  c.relname                          as ตาราง,
  c.relrowsecurity                   as rls_on,
  coalesce(p.policyname, '(ไม่มี)')  as policy,
  p.roles                            as ใครใช้ได้,
  p.cmd                              as คำสั่ง
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p on p.schemaname = 'public' and p.tablename = c.relname
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
