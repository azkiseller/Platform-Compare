-- تب‌های داشبورد: خودرو (206_1397) و موتور (moto_1403)
-- روی پروژه‌ی جدید Supabase (akaczqhvyemkjnwzgjzr) اجرا شده است.
-- ردیف‌های قبلی همه مربوط به ۲۰۶ تیپ ۲ مدل ۱۳۹۷ هستند؛ پیش‌فرض فقط برای پر کردن آن‌هاست
-- و بعد برداشته می‌شود تا ردیفی که vehicle ندارد بی‌صدا «خودرو» ثبت نشود.
alter table compare.commission
  add column if not exists vehicle text not null default '206_1397';
alter table compare.commission alter column vehicle drop default;

alter table compare.commission drop constraint if exists commission_vehicle_check;
alter table compare.commission
  add constraint commission_vehicle_check check (vehicle in ('206_1397', 'moto_1403'));

-- برای ویوی current_commission (آخرین اجرا در هر وسیله/سایت) و latest_commission
create index if not exists commission_vehicle_latest_idx
  on compare.commission (vehicle, site, coverage, captured_at desc);

-- null یعنی سایت کارمزد نشان نداده (نه صفر)
alter table compare.commission alter column rate drop not null;

-- داشبورد از این ویو می‌خواند: ردیف‌های آخرین اجرای هر سایت، جدا برای هر وسیله.
-- شرکتی که در آخرین اجرا نبوده دیگر نشان داده نمی‌شود (نرخ کهنه نمی‌ماند).
-- ستون vehicle آخر اضافه شده تا create or replace روی ویوی موجود کار کند.
create or replace view compare.current_commission with (security_invoker = true) as
select distinct on (c.vehicle, c.site, c.company_key, c.coverage)
  c.site, c.company_key, c.coverage, c.rate, c.captured_at, c.vehicle
from compare.commission c
join (
  select vehicle, site, coverage, max(captured_at) as last_run
  from compare.commission
  group by vehicle, site, coverage
) l on l.vehicle = c.vehicle and l.site = c.site and l.coverage = c.coverage
   and c.captured_at >= l.last_run - interval '10 minutes'
order by c.vehicle, c.site, c.company_key, c.coverage, c.captured_at desc;

-- آخرین رکورد هر شرکت (حتی اگر در آخرین اجرا نبوده)، جدا برای هر وسیله
create or replace view compare.latest_commission with (security_invoker = true) as
select distinct on (vehicle, site, company_key, coverage)
  site, company_key, coverage, rate, captured_at, vehicle
from compare.commission
order by vehicle, site, company_key, coverage, captured_at desc;

create or replace view compare.commission_compare with (security_invoker = true) as
select company_key, coverage,
  max(rate) filter (where site = 'site1') as site1,
  max(rate) filter (where site = 'site2') as site2,
  max(rate) filter (where site = 'site3') as site3,
  min(rate) as min_rate,
  max(rate) as max_rate,
  case when min(rate) > 0 then round((max(rate) - min(rate)) / min(rate) * 100, 1) end as spread_pct,
  (array_agg(site order by rate desc nulls last))[1] as best_site,
  max(captured_at) as last_captured,
  vehicle
from compare.latest_commission
group by vehicle, company_key, coverage;

grant select on compare.current_commission, compare.latest_commission, compare.commission_compare to anon, authenticated;
