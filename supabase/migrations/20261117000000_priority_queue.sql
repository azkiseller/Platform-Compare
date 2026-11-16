-- صف اولویت‌دار ماتریس: هر خودرویی که کسی در صفحه سرچ کند جلوی صف می‌رود و در اجرای بعدی
-- (ورک‌فلو هر ۱۵ ثانیه) بررسی می‌شود؛ بقیه‌ی ماتریس آهسته و در حد سقف هر سایت پر می‌شود.

alter table compare.coverage_jobs
  add column if not exists priority smallint not null default 0,
  add column if not exists requested_at timestamptz;

create index if not exists coverage_jobs_prio_idx
  on compare.coverage_jobs (site, requested_at) where status = 'pending' and priority > 0;

-- سقف درخواست هر سایت (برای اینکه سایت‌ها مسدودمان نکنند) — با SQL قابل تغییر است
create table if not exists compare.site_budget (
  site text primary key,
  per_tick int not null,            -- حداکثر کار در هر اجرای ورک‌فلو
  max_per_window int not null,      -- سقف کار در هر پنجره‌ی زمانی
  window_seconds int not null,
  window_start timestamptz not null default now(),
  used int not null default 0,
  blocked_until timestamptz,        -- بعد از خطای 429 تا این زمان چیزی برداشته نمی‌شود
  stale_hours int not null default 24  -- نتیجه‌ی قدیمی‌تر از این، با سرچ دوباره بررسی می‌شود
);
alter table compare.site_budget enable row level security;
insert into compare.site_budget (site, per_tick, max_per_window, window_seconds) values
  ('site1', 3, 30, 60),     -- ازکی
  ('site2', 1, 10, 600),    -- شرکاء: بعد از ~۲۰ درخواست ۸ دقیقه مسدود می‌کند
  ('site3', 3, 30, 60)      -- پلاس‌بیمه
on conflict (site) do nothing;

-- برداشتن کار: اول سرچ‌شده‌ها (به ترتیب زمان درخواست)، بعد بقیه‌ی ماتریس؛ در حد سقف سایت
create or replace function compare.claim_coverage_jobs(p_site text, p_n integer)
returns table(job_id bigint, year integer, vehicle_type text, type_id text, brand text, brand_id text,
              model text, model_id text, usage text, usage_id text)
language plpgsql security definer
set search_path to 'compare', 'public'
as $$
declare b compare.site_budget; n int; took int;
begin
  -- کارهای اجرای قطع‌شده برگردند به صف
  update compare.coverage_jobs set status = 'pending'
   where site = p_site and status = 'running' and locked_at < now() - interval '15 minutes';

  select * into b from compare.site_budget where site = p_site for update;
  if not found then
    n := coalesce(p_n, 10);
  else
    if b.blocked_until is not null and b.blocked_until > now() then return; end if;
    if b.window_start < now() - make_interval(secs => b.window_seconds) then
      update compare.site_budget set window_start = now(), used = 0 where site = p_site;
      b.used := 0;
    end if;
    n := least(coalesce(p_n, b.per_tick), b.per_tick, b.max_per_window - b.used);
  end if;
  if n <= 0 then return; end if;

  return query
  with pr as (
    select j.id from compare.coverage_jobs j
     where j.site = p_site and j.status = 'pending' and j.priority > 0
     order by j.requested_at limit n
     for update skip locked),
  rest as (
    select j.id from compare.coverage_jobs j
     where j.site = p_site and j.status = 'pending' and j.priority = 0
     order by j.id limit greatest(n - (select count(*) from pr), 0)
     for update skip locked),
  c as (select id from pr union all select id from rest)
  update compare.coverage_jobs j
     set status = 'running', locked_at = now(), attempts = j.attempts + 1
    from c, compare.catalog k
   where j.id = c.id and k.id = j.catalog_id
  returning j.id, j.year, k.vehicle_type, k.type_id, k.brand, k.brand_id, k.model, k.model_id, k.usage, k.usage_id;
  get diagnostics took = row_count;

  if b.site is not null and took > 0 then
    update compare.site_budget set used = used + took where site = p_site;
  end if;
end $$;

-- ثبت نتیجه: 429/440/401/403 (محدودیت یا نشست) جزو تلاش‌ها حساب نمی‌شوند؛ 429 سایت را موقتاً متوقف می‌کند
create or replace function compare.complete_coverage_jobs(p_results jsonb)
returns integer
language plpgsql security definer
set search_path to 'compare', 'public'
as $$
declare n int; w int; s text;
begin
  update compare.coverage_jobs j set
    status = case when r.error is null then 'done'
                  when r.error ~ '^HTTP (429|440|401|403)\M' then 'pending'
                  when j.attempts >= 3 then 'error' else 'pending' end,
    attempts = case when r.error ~ '^HTTP (429|440|401|403)\M' then greatest(j.attempts - 1, 0) else j.attempts end,
    done_at = case when r.error is null then now() else j.done_at end,
    companies = case when r.error is null then coalesce(r.companies, '[]'::jsonb) else j.companies end,
    n_companies = case when r.error is null then jsonb_array_length(coalesce(r.companies, '[]'::jsonb)) else j.n_companies end,
    last_error = r.error,
    locked_at = null,
    priority = case when r.error is null then 0 else j.priority end,
    requested_at = case when r.error is null then null else j.requested_at end
  from jsonb_to_recordset(p_results) as r(job_id bigint, companies jsonb, error text)
  where j.id = r.job_id;
  get diagnostics n = row_count;

  select max(coalesce(substring(r.error from 'available in ([0-9]+) second')::int, 300)), min(j.site)
    into w, s
    from jsonb_to_recordset(p_results) as r(job_id bigint, error text)
    join compare.coverage_jobs j on j.id = r.job_id
   where r.error ~ '^HTTP 429';
  if w is not null then
    update compare.site_budget
       set blocked_until = greatest(coalesce(blocked_until, now()), now() + make_interval(secs => w + 15))
     where site = s;
  end if;
  return n;
end $$;

-- خواندن نتیجه برای صفحه + گذاشتن خودروی سرچ‌شده در صف فوری
-- (اگر بررسی نشده، خطا خورده یا نتیجه‌اش از stale_hours قدیمی‌تر است). نتیجه‌ی قبلی تا رسیدن نتیجه‌ی تازه نمایش داده می‌شود.
drop function if exists compare.coverage_lookup(integer, jsonb);
create function compare.coverage_lookup(p_year integer, p_items jsonb)
returns jsonb
language plpgsql volatile security definer
set search_path to 'compare', 'public'
as $$
declare it record; kid bigint; j compare.coverage_jobs; b compare.site_budget; o jsonb := '{}'::jsonb; ahead int;
begin
  if p_year is null or p_year < 1300 or p_year > 1500 then raise exception 'سال نامعتبر است'; end if;
  for it in select e.key, e.value from jsonb_each(coalesce(p_items, '{}'::jsonb)) e where e.key in ('site1', 'site2', 'site3') loop
    select k.id into kid from compare.catalog k
     where k.site = it.key and k.type_id = it.value->>'type_id' and k.brand_id = it.value->>'brand_id'
       and k.model_id = coalesce(it.value->>'model_id', '') and k.usage_id = it.value->>'usage_id'
     limit 1;
    if kid is null then o := o || jsonb_build_object(it.key, jsonb_build_object('status', 'none')); continue; end if;
    select * into b from compare.site_budget where site = it.key;

    select * into j from compare.coverage_jobs where catalog_id = kid and year = p_year for update;
    if not found then
      insert into compare.coverage_jobs (catalog_id, site, year, priority, requested_at)
      values (kid, it.key, p_year, 1, now())
      on conflict (catalog_id, year) do update set priority = 1, requested_at = coalesce(compare.coverage_jobs.requested_at, now())
      returning * into j;
    elsif j.status = 'pending' and j.priority = 0 then
      update compare.coverage_jobs set priority = 1, requested_at = now() where id = j.id returning * into j;
    elsif j.status = 'error'
       or (j.status = 'done' and j.done_at < now() - make_interval(hours => coalesce(b.stale_hours, 24))) then
      update compare.coverage_jobs set status = 'pending', attempts = 0, priority = 1, requested_at = now()
       where id = j.id returning * into j;
    end if;

    ahead := null;
    if j.status = 'pending' and j.priority > 0 then
      select count(*) into ahead from compare.coverage_jobs x
       where x.site = it.key and x.status = 'pending' and x.priority > 0 and x.requested_at < j.requested_at;
    end if;
    o := o || jsonb_build_object(it.key, jsonb_build_object(
      'status', j.status,
      'done_at', j.done_at,
      'companies', j.companies,
      'ahead', ahead,
      'blocked_until', case when b.blocked_until > now() then b.blocked_until end,
      'error', case when j.status = 'error' then left(j.last_error, 200) end));
  end loop;
  return o;
end $$;
revoke all on function compare.coverage_lookup(integer, jsonb) from public;
grant execute on function compare.coverage_lookup(integer, jsonb) to anon, authenticated;
revoke all on function compare.claim_coverage_jobs(text, integer) from public, anon, authenticated;
revoke all on function compare.complete_coverage_jobs(jsonb) from public, anon, authenticated;

-- کارهایی که به خاطر 429/440 تلاش‌شان سوخت، دوباره سهم کامل داشته باشند
update compare.coverage_jobs set attempts = 0
 where status in ('pending', 'running') and last_error ~ '^HTTP (429|440)';

notify pgrst, 'reload schema';
