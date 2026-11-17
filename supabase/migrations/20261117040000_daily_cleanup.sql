-- مدل «فقط سرچ‌ها، فقط همان روز»: نتیجه‌ها تا پایان همان روز (به وقت تهران) نگه داشته می‌شوند و بعد پاک می‌شوند؛
-- سرچ بعدی همان خودرو دوباره در صف قرار می‌گیرد. پر کردن پس‌زمینه برای هیچ سایتی انجام نمی‌شود.
create extension if not exists pg_cron;

update compare.site_budget set bg_max = 0 where site = 'site1';

create or replace function compare.daily_cleanup()
returns integer
language plpgsql security definer
set search_path to 'compare', 'public'
as $$
declare n int; cut timestamptz := date_trunc('day', now() at time zone 'Asia/Tehran') at time zone 'Asia/Tehran';
begin
  -- همه‌چیز جز کارهای در حال اجرا و سرچ‌هایی که هنوز در صف‌اند، اگر مال قبل از امروز باشد
  delete from compare.coverage_jobs
   where status <> 'running'
     and not (status = 'pending' and priority > 0)
     and coalesce(done_at, locked_at, '-infinity'::timestamptz) < cut;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function compare.daily_cleanup() from public, anon, authenticated;

-- هر شب ساعت ۰۰:۰۱ تهران (۲۰:۳۱ UTC)
select cron.schedule('compare-daily-cleanup', '31 20 * * *', 'select compare.daily_cleanup()');
