-- ۱) شرکاء و پلاس‌بیمه فقط خودروهای سرچ‌شده را بررسی کنند (پر کردن پس‌زمینه خاموش؛ ازکی مثل قبل)
update compare.site_budget set bg_max = 0 where site in ('site2', 'site3');

-- ۲) خطای لاگین «Try spacing your requests out…» (پیام n8n برای 429) هم محدودیت حساب شود:
--    جزو تلاش‌ها نیست و سایت ۲ دقیقه استراحت می‌کند (قبلاً HTTP 000 ثبت می‌شد و کار به «خطا» می‌رسید)
create or replace function compare.complete_coverage_jobs(p_results jsonb)
returns integer
language plpgsql security definer
set search_path to 'compare', 'public'
as $$
declare n int; w int; s text;
begin
  create temp table if not exists _res (job_id bigint, companies jsonb, error text, nocov boolean, transient boolean, limited boolean) on commit drop;
  truncate _res;
  insert into _res
  select r.job_id, r.companies, r.error,
         coalesce(r.error ~ 'سال ساخت وارد شده کمتر از سال ساخت مجاز', false),
         coalesce(r.error ~ '^HTTP (429|440|401|403)\M' or r.error ~ '^HTTP \d{3} login:', false),
         coalesce(r.error ~ '^HTTP 429' or r.error ~* 'too many requests|try spacing your requests', false)
    from jsonb_to_recordset(p_results) as r(job_id bigint, companies jsonb, error text);

  update compare.coverage_jobs j set
    status = case when r.error is null or r.nocov then 'done'
                  when r.transient or r.limited then 'pending'
                  when j.attempts >= 3 then 'error' else 'pending' end,
    attempts = case when r.transient or r.limited then greatest(j.attempts - 1, 0) else j.attempts end,
    done_at = case when r.error is null or r.nocov then now() else j.done_at end,
    companies = case when r.nocov then '[]'::jsonb when r.error is null then coalesce(r.companies, '[]'::jsonb) else j.companies end,
    n_companies = case when r.nocov then 0 when r.error is null then jsonb_array_length(coalesce(r.companies, '[]'::jsonb)) else j.n_companies end,
    last_error = case when r.nocov then 'این سال برای این مدل در سایت ارائه نمی‌شود' else r.error end,
    locked_at = null,
    priority = case when r.error is null or r.nocov then 0 else j.priority end,
    requested_at = case when r.error is null or r.nocov then null else j.requested_at end
  from _res r
  where j.id = r.job_id;
  get diagnostics n = row_count;

  update compare.coverage_jobs o set status = 'done', done_at = now(), companies = '[]'::jsonb, n_companies = 0,
         last_error = 'این سال برای این مدل در سایت ارائه نمی‌شود', priority = 0, requested_at = null, locked_at = null
    from _res r join compare.coverage_jobs j on j.id = r.job_id
   where r.nocov and o.catalog_id = j.catalog_id and o.year < j.year and o.status = 'pending';

  select max(coalesce(substring(r.error from 'available in ([0-9]+) second')::int, case when r.error ~ 'login:' then 120 else 300 end)), min(j.site)
    into w, s
    from _res r join compare.coverage_jobs j on j.id = r.job_id
   where r.limited;
  if w is not null then
    update compare.site_budget
       set blocked_until = greatest(coalesce(blocked_until, now()), now() + make_interval(secs => w + 15))
     where site = s;
  end if;
  return n;
end $$;
revoke all on function compare.complete_coverage_jobs(jsonb) from public, anon, authenticated;

-- کارهایی که فقط به خاطر خطای لاگین به «خطا» رسیدند برگردند به صف
update compare.coverage_jobs set status = 'pending', attempts = 0
 where status = 'error' and last_error ~ '^HTTP \d{3} login:';
