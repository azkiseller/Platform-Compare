-- سهمیه‌ی رزرو برای خودروهای سرچ‌شده: پر کردن پس‌زمینه‌ی ماتریس در هر پنجره حداکثر bg_max کار برمی‌دارد
-- و بقیه‌ی سقف فقط برای سرچ‌ها می‌ماند (شرکاء: ۵ از ۱۰ در هر ۱۰ دقیقه).
alter table compare.site_budget
  add column if not exists bg_max int,               -- null = بدون محدودیت جدا برای پس‌زمینه
  add column if not exists bg_used int not null default 0;
update compare.site_budget set bg_max = 5 where site = 'site2';

create or replace function compare.claim_coverage_jobs(p_site text, p_n integer)
returns table(job_id bigint, year integer, vehicle_type text, type_id text, brand text, brand_id text,
              model text, model_id text, usage text, usage_id text)
language plpgsql security definer
set search_path to 'compare', 'public'
as $$
declare b compare.site_budget; n int; bg_allow int; pr_ids bigint[]; bg_ids bigint[];
begin
  update compare.coverage_jobs set status = 'pending'
   where site = p_site and status = 'running' and locked_at < now() - interval '15 minutes';

  select * into b from compare.site_budget where site = p_site for update;
  if not found then
    n := coalesce(p_n, 10);
  else
    if b.blocked_until is not null and b.blocked_until > now() then return; end if;
    if b.window_start < now() - make_interval(secs => b.window_seconds) then
      update compare.site_budget set window_start = now(), used = 0, bg_used = 0 where site = p_site;
      b.used := 0; b.bg_used := 0;
    end if;
    n := least(coalesce(p_n, b.per_tick), b.per_tick, b.max_per_window - b.used);
  end if;
  if n <= 0 then return; end if;

  -- اول سرچ‌شده‌ها
  select coalesce(array_agg(x.id), '{}') into pr_ids from (
    select j.id from compare.coverage_jobs j
     where j.site = p_site and j.status = 'pending' and j.priority > 0
     order by j.requested_at limit n
     for update skip locked) x;
  -- بعد پس‌زمینه، در حد سهمیه‌ی آزاد آن
  bg_allow := n - cardinality(pr_ids);
  if b.site is not null and b.bg_max is not null then bg_allow := least(bg_allow, b.bg_max - b.bg_used); end if;
  bg_ids := '{}';
  if bg_allow > 0 then
    select coalesce(array_agg(x.id), '{}') into bg_ids from (
      select j.id from compare.coverage_jobs j
       where j.site = p_site and j.status = 'pending' and j.priority = 0
       order by j.id limit bg_allow
       for update skip locked) x;
  end if;
  if cardinality(pr_ids) + cardinality(bg_ids) = 0 then return; end if;

  if b.site is not null then
    update compare.site_budget
       set used = used + cardinality(pr_ids) + cardinality(bg_ids), bg_used = bg_used + cardinality(bg_ids)
     where site = p_site;
  end if;

  return query
  update compare.coverage_jobs j
     set status = 'running', locked_at = now(), attempts = j.attempts + 1
    from compare.catalog k
   where j.id = any(pr_ids || bg_ids) and k.id = j.catalog_id
  returning j.id, j.year, k.vehicle_type, k.type_id, k.brand, k.brand_id, k.model, k.model_id, k.usage, k.usage_id;
end $$;
revoke all on function compare.claim_coverage_jobs(text, integer) from public, anon, authenticated;
