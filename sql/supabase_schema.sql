-- 小马课表 Supabase 云同步建表脚本（WB_SPEC_211 第 1 节，SQL 全文）
--
-- 项目：xiaoma-timetable（Singapore）
-- 执行方式：Supabase Dashboard → SQL Editor（或 psql 连接数据库）粘贴执行。
-- 本脚本不含任何真实 key（anon key 只走 --dart-define，不进代码/文档/git）。
--
-- 设计要点：
--   * 三张表均开 RLS，只给 anon「select + insert + update」，故意不给 delete
--     —— anon 删不掉云端行，云端删除只走 Dashboard（差异说明 3）。
--   * 远程 id 规则：courses=`course:<semesterId>:<localId>`、
--     notes=`note:<localId>`、exams=`exam:<semesterId>:<localId>`。

create table if not exists courses (
  id text primary key,
  semester_id int not null,
  name text not null,
  teacher text,
  classroom text,
  color_value int not null,
  day_of_week int not null,
  start_section int not null,
  end_section int not null,
  weeks_json text not null,
  week_type int not null default 0,
  note text,
  exam_date_ms bigint,
  exam_end_time text,
  exam_place text,
  updated_at timestamptz not null default now()
);

create table if not exists notes (
  id text primary key,
  date text not null,
  content text not null,
  created_at_ms bigint not null,
  updated_at timestamptz not null default now()
);

create table if not exists exams (
  id text primary key,
  course_remote_id text not null,
  date text not null,
  start_time text,
  end_time text,
  place text,
  updated_at timestamptz not null default now()
);

alter table courses enable row level security;
alter table notes enable row level security;
alter table exams enable row level security;

create policy "anon read write" on courses for select using (true);
create policy "anon insert" on courses for insert with check (true);
create policy "anon update" on courses for update using (true) with check (true);

create policy "anon read write" on notes for select using (true);
create policy "anon insert" on notes for insert with check (true);
create policy "anon update" on notes for update using (true) with check (true);

create policy "anon read write" on exams for select using (true);
create policy "anon insert" on exams for insert with check (true);
create policy "anon update" on exams for update using (true) with check (true);

-- 验证查询（执行后逐条确认）：
--   1) 三张表已建：
--      select table_name from information_schema.tables
--      where table_schema = 'public' and table_name in ('courses','notes','exams');
--   2) RLS 已开：
--      select relname, relrowsecurity from pg_class
--      where relname in ('courses','notes','exams');
--   3) 无 delete 策略（查询结果里不应出现 'delete'）：
--      select tablename, policyname, cmd from pg_policies
--      where tablename in ('courses','notes','exams') order by tablename, cmd;
