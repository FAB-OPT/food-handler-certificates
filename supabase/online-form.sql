-- ════════════════════════════════════════════════════════════════════
-- ระบบแบบฟอร์มออนไลน์ (Online Form)  —  modules/online-form.html
--
-- โครงแบบทั่วไป: ตัวคำถามเก็บเป็นข้อมูลในตาราง ไม่ได้ฝังในโค้ด
-- เพิ่มฟอร์มชุดใหม่ในอนาคตทำผ่านหน้าแอดมินได้เลย ไม่ต้องแก้ไฟล์ HTML
--
-- โปรเจกต์: FAB HUB (pzspcjqlxoqnbtvlfjsy)
-- วิธีใช้: Supabase → SQL Editor → วางทั้งไฟล์ → Run (รันซ้ำได้ ไม่พัง)
--
-- 3 ตาราง
--   of_forms      = ตัวแบบฟอร์ม (หมวด/คำถาม/เกณฑ์คะแนน/สถานะเปิด-ปิด)
--   of_people     = รายชื่อผู้ถูกประเมิน (ล็อกไว้ ผู้กรอกเลือกได้เท่านั้น)
--   of_responses  = คำตอบและคะแนน
-- ════════════════════════════════════════════════════════════════════

-- ── ตัวแบบฟอร์ม ─────────────────────────────────────────────────────
create table if not exists public.of_forms (
  id          bigserial primary key,
  key         text not null unique,        -- รหัสฟอร์ม เช่น 'silver-gold'
  title       text not null,
  description text default '',
  emoji       text default '📋',
  round       text default '',             -- รอบเก็บข้อมูล เช่น 'รอบที่ 1 / 2569'
  status      text not null default 'draft',  -- draft = ยังไม่เปิด · open = เปิดกรอก · closed = ปิดแล้ว

  -- ฟอร์มนี้ต้องเลือก "คนที่ถูกประเมิน" ไหม
  subject_required boolean not null default true,
  subject_filter   jsonb   not null default '{}'::jsonb,  -- เช่น {"level":["silver","gold"]}

  -- โครงคำถาม (ดูรูปแบบท้ายไฟล์)
  scale       jsonb not null default '[]'::jsonb,
  sections    jsonb not null default '[]'::jsonb,
  closing     jsonb not null default '[]'::jsonb,
  rules       jsonb not null default '{}'::jsonb,

  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists of_forms_status_idx on public.of_forms (status);


-- ── รายชื่อผู้ถูกประเมิน ────────────────────────────────────────────
-- ผู้กรอกไม่ได้มาจากตารางนี้ — ใช้บัญชีที่ล็อกอินฮับอยู่แล้ว
create table if not exists public.of_people (
  id         bigserial primary key,
  name       text not null,
  branch     text not null default '',
  level      text default '',            -- silver / gold (หรือค่าอื่นในอนาคต)
  station    text default '',            -- service / kitchen
  position   text default '',
  emp_code   text default '',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists of_people_branch_idx on public.of_people (branch);
create index if not exists of_people_level_idx  on public.of_people (level);

-- กันชื่อซ้ำในสาขาเดียวกัน (ใช้เป็นคีย์ตอนนำเข้ารายชื่อจาก Excel ด้วย)
create unique index if not exists of_people_uniq
  on public.of_people (branch, name);


-- ── คำตอบ ───────────────────────────────────────────────────────────
create table if not exists public.of_responses (
  id            bigserial primary key,
  form_key      text not null,
  form_title    text default '',
  round         text default '',

  -- ผู้กรอก = บัญชีที่ล็อกอินฮับ (fab_session)
  rater_key     text not null default '',   -- รหัสผู้ใช้/PIN สาขา
  rater_name    text default '',
  rater_role    text default '',            -- branch / admin / bzm / ...
  rater_branch  text default '',

  -- ผู้ถูกประเมิน (0 = ฟอร์มที่ไม่ต้องเลือกคน)
  subject_id     bigint not null default 0,
  subject_name   text default '',
  subject_branch text default '',
  subject_meta   jsonb not null default '{}'::jsonb,  -- {"level":"silver","station":"service"}

  answers       jsonb not null default '{}'::jsonb,   -- {"ss_A1":4,"ss_A2":"na",...}
  sections      jsonb not null default '{}'::jsonb,   -- คะแนนรายหมวดที่คำนวณแล้ว
  total_pct     numeric,
  avg_score     numeric,
  verdict       text default '',                      -- pass / fail
  verdict_note  text default '',
  texts         jsonb not null default '{}'::jsonb,   -- คำตอบปลายเปิดท้ายฟอร์ม

  created_at    timestamptz not null default now()
);

create index if not exists of_resp_form_idx    on public.of_responses (form_key, round);
create index if not exists of_resp_subject_idx on public.of_responses (subject_id);
create index if not exists of_resp_branch_idx  on public.of_responses (subject_branch);

-- ★ หัวใจของการ "ตอบได้ครั้งเดียว"
--   ผู้กรอก 1 คน ต่อ ผู้ถูกประเมิน 1 คน ต่อ ฟอร์ม ต่อ รอบ = 1 ครั้ง
--   subject_id เป็น 0 สำหรับฟอร์มที่ไม่มีผู้ถูกประเมิน → กลายเป็น 1 คนตอบได้ครั้งเดียว
--   ส่งซ้ำ ฐานข้อมูลปฏิเสธเอง (error 23505) หน้าเว็บจะบอกว่ากรอกไปแล้ว
create unique index if not exists of_resp_once
  on public.of_responses (form_key, round, rater_key, subject_id);


-- ── สิทธิ์การเข้าถึง ─────────────────────────────────────────────────
-- หน้าเว็บเป็นไฟล์ static ใช้ publishable key ฝั่งผู้ใช้
-- การแบ่งสิทธิ์ "สาขาเห็นแค่ฟอร์ม · แอดมินเห็นผล" ทำที่หน้าจอตาม fab_session
-- ไม่ใช่ที่ฐานข้อมูล — คนที่รู้วิธีเรียก API ตรง ๆ ยังอ่านข้อมูลได้
-- ถ้าต้องปิดสนิทต้องต่อ Supabase Auth เพิ่ม
alter table public.of_forms     enable row level security;
alter table public.of_people    enable row level security;
alter table public.of_responses enable row level security;

drop policy if exists of_forms_all on public.of_forms;
create policy of_forms_all on public.of_forms for all using (true) with check (true);

drop policy if exists of_people_all on public.of_people;
create policy of_people_all on public.of_people for all using (true) with check (true);

drop policy if exists of_resp_all on public.of_responses;
create policy of_resp_all on public.of_responses for all using (true) with check (true);


-- ── ล้างตารางรุ่นทดลอง sg_* ที่สร้างไว้ก่อนหน้า (ถ้ามี) ──────────────
drop table if exists public.sg_assessments;
drop table if exists public.sg_people;


-- ════════════════════════════════════════════════════════════════════
-- รูปแบบข้อมูลใน of_forms  (หน้าแอดมินสร้างให้อัตโนมัติ ไม่ต้องพิมพ์เอง)
--
-- scale    [{"v":1,"label":"1","hint":"ยังทำไม่ได้"}, ..., {"v":"na","label":"N/A"}]
--
-- sections [{"sid":"ss_A",              ← รหัสไม่ซ้ำทั้งฟอร์ม
--            "label":"A",               ← ตัวอักษรที่แสดง
--            "name":"บุคลิกภาพ ...",
--            "w":15,                    ← น้ำหนัก % (รวมกันได้ 100 ต่อ 1 เส้นทาง)
--            "when":{"level":"silver","station":"service"},  ← ว่างไว้ = ใช้กับทุกคน
--            "q":["คำถามข้อ 1","คำถามข้อ 2"]}]
--
-- closing  [{"key":"strengths","type":"text","label":"จุดแข็ง...","required":false},
--           {"key":"readiness","type":"choice","label":"ความพร้อม...",
--            "options":["พร้อม","ยังไม่พร้อม"],"required":true}]
--
-- rules    {"pass":{"by":"level","map":{"silver":70,"gold":80},"default":70},
--           "knockouts":[
--             {"type":"minScore","section":"A","min":2,
--              "note":"มีข้อในหมวด A ได้ 1 คะแนน"},
--             {"type":"minPct","section":"D","pct":70,"when":{"level":"gold"},
--              "note":"หมวด D ต่ำกว่า 70%"}]}
-- ════════════════════════════════════════════════════════════════════
