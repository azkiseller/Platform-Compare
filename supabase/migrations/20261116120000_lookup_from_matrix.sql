-- تب «استعلام خودرو» داشبورد: کاتالوگ و نتیجه‌ها مستقیم از دیتابیس (خروجی ورک‌فلوی Coverage Matrix)،
-- بدون نیاز به n8n محلی. فقط خواندن؛ چیزی نوشته نمی‌شود.

-- کاتالوگ خودروها (فهرست عمومی برند/مدل/کاربری هر سایت؛ داده‌ی حساسی ندارد)
grant execute on function compare.catalog_tree() to anon, authenticated;

-- نتیجه‌ی ماتریس برای یک خودروی انتخاب‌شده در هر سایت و یک سال ساخت
-- p_items: {"site1": {"type_id","brand_id","model_id","usage_id"}, "site2": {...}, ...}
-- خروجی: {"site1": {"status": done|pending|running|error|none, "done_at", "companies": [...], "error"}, ...}
create or replace function compare.coverage_lookup(p_year integer, p_items jsonb)
returns jsonb
language sql stable security definer
set search_path to 'compare', 'public'
as $$
  select coalesce(jsonb_object_agg(it.key, coalesce(
    (select jsonb_build_object(
              'status', j.status,
              'done_at', j.done_at,
              'companies', case when j.status = 'done' then coalesce(j.companies, '[]'::jsonb) end,
              'error', case when j.status = 'error' then left(j.last_error, 200) end)
       from compare.catalog k
       join compare.coverage_jobs j on j.catalog_id = k.id and j.year = p_year
      where k.site = it.key
        and k.type_id = it.value->>'type_id' and k.brand_id = it.value->>'brand_id'
        and k.model_id = coalesce(it.value->>'model_id', '') and k.usage_id = it.value->>'usage_id'
      limit 1),
    jsonb_build_object('status', 'none'))), '{}'::jsonb)
  from jsonb_each(coalesce(p_items, '{}'::jsonb)) it
  where it.key in ('site1', 'site2', 'site3');
$$;
revoke all on function compare.coverage_lookup(integer, jsonb) from public;
grant execute on function compare.coverage_lookup(integer, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
