-- هر اجرای workflow (هر ۵ دقیقه) داده‌ی قبلی را جایگزین می‌کند:
-- در compare.commission برای هر (vehicle, site, company_key, coverage) فقط یک ردیف می‌ماند و n8n با upsert آن را به‌روز می‌کند.
-- تاریخچه‌ی قبلی پیش از پاک‌سازی در compare.commission_history نگه داشته می‌شود (فقط سرور به آن دسترسی دارد).

create table if not exists compare.commission_history (
  id bigint, site text, company_key text, coverage text, rate numeric, captured_at timestamptz, vehicle text
);
insert into compare.commission_history (id, site, company_key, coverage, rate, captured_at, vehicle)
select id, site, company_key, coverage, rate, captured_at, vehicle from compare.commission;
alter table compare.commission_history enable row level security;
revoke all on compare.commission_history from anon, authenticated;

-- فقط آخرین ردیف هر کلید بماند
delete from compare.commission c
using compare.commission d
where c.vehicle = d.vehicle and c.site = d.site and c.company_key = d.company_key and c.coverage = d.coverage
  and (c.captured_at < d.captured_at or (c.captured_at = d.captured_at and c.id < d.id));

alter table compare.commission drop constraint if exists commission_current_uq;
alter table compare.commission
  add constraint commission_current_uq unique (vehicle, site, company_key, coverage);

-- همه‌ی ردیف‌های یک اجرا یک captured_at دارند؛ شرکتی که در آخرین اجرا نبوده (ردیف قدیمی‌تر) نشان داده نمی‌شود
create or replace view compare.current_commission with (security_invoker = true) as
select distinct on (c.vehicle, c.site, c.company_key, c.coverage)
  c.site, c.company_key, c.coverage, c.rate, c.captured_at, c.vehicle
from compare.commission c
join (
  select vehicle, site, coverage, max(captured_at) as last_run
  from compare.commission
  group by vehicle, site, coverage
) l on l.vehicle = c.vehicle and l.site = c.site and l.coverage = c.coverage
   and c.captured_at >= l.last_run - interval '1 minute'
order by c.vehicle, c.site, c.company_key, c.coverage, c.captured_at desc;
