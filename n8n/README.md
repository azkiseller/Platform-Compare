# راه‌اندازی workflow روی Supabase جدید

یک فایل: `Insurance Compare - car and moto.json` (نام در n8n: «Insurance Compare – خودرو و موتور»)

- هر ۵ دقیقه اجرا می‌شود و داده‌ی هر شرکت/سایت/وسیله را **جایگزین** داده‌ی قبلی می‌کند (upsert روی `vehicle, site, company_key, coverage`). پیش‌نیاز: migration `20261109150000_commission_latest_only.sql`.
- هر سایت **یک بار** لاگین می‌کند و با همان نشست قیمت هر دو وسیله را می‌گیرد:
  خودرو `206_1397` (۲۰۶ تیپ ۲، ۱۳۹۷) و موتور `moto_1403` (تک‌سیلندر، ۱۴۰۳).
- به پروژه‌ی Supabase جدید (`akaczqhvyemkjnwzgjzr`) می‌نویسد. هیچ رمز یا کلیدی داخل فایل نیست.

روی بوم سه ردیف رنگی هست (پلاس‌بیمه، ازکی، شوراکا)؛ در هر ردیف شاخه‌ی بالا خودرو و پایین موتور است.

## ۱. قبل از import
workflowهای قبلی (هم نسخه‌ی قدیمی که به Supabase قبلی می‌نویسد، هم دو فایل جدای خودرو/موتور اگر import کرده‌اید) را **غیرفعال یا حذف** کنید.

## ۲. تنظیمات: فقط دو جا

### الف) نود `Settings` (اولین نود بعد از Schedule)
همه‌ی مقدارهای قابل‌تغییر اینجاست و بقیه‌ی نودها از آن می‌خوانند:

| فیلد | چه چیزی |
|---|---|
| `supabaseUrl` | `https://akaczqhvyemkjnwzgjzr.supabase.co` (بدون `/` آخر) |
| `shorakaUsername` / `shorakaPassword` | لاگین شوراکا |
| `azkiUsername` / `azkiPassword` | لاگین ازکی ایجنت |
| `plusbimehMobile` / `plusbimehPassword` | لاگین پلاس‌بیمه |
| `plusbimehDeviceToken` / `plusbimehInquiryToken` | توکن‌های ثابت پلاس‌بیمه؛ دست نزنید |

فایل داخل مخزن به‌جای مقدار واقعی `SHORAKA_USERNAME` و … دارد؛ رمز واقعی را **هرگز** در مخزن commit نکنید.

### ب) credential «Custom Auth account» (کلید Supabase)
Overview ← Credentials ← «Custom Auth account». هر ۱۲ نود Supabase از همین استفاده می‌کنند.

**JSON** — با Secret key جدید (Project Settings ← API Keys ← Secret keys، با `sb_secret_` شروع می‌شود):
```json
{
  "headers": {
    "apikey": "sb_secret_..."
  }
}
```
خط `Authorization` را **پاک کنید**؛ این کلید در Authorization قبول نمی‌شود.

یا با کلید Legacy `service_role` (API Keys ← Legacy API keys ← service_role؛ با `eyJ` شروع می‌شود):
```json
{
  "headers": {
    "apikey": "eyJ...",
    "Authorization": "Bearer eyJ..."
  }
}
```
هر دو مقدار همان کلید است؛ در دومی کلمه‌ی `Bearer` و یک فاصله قبلش. کلید پروژه‌ی **قبلی** (که در وسطش `ssqqjkhzgcgojbacjitq` دارد) کار نمی‌کند.

**Allowed HTTP Request Domains** ← `Specific Domains` ← `akaczqhvyemkjnwzgjzr.supabase.co`
(تا این کلید فقط به Supabase خودتان فرستاده شود.)

## ۳. Import و فعال‌سازی
1. Workflows ← Import from File ← همین فایل.
2. اگر فایل مخزن را import کرده‌اید، مقدارهای نود `Settings` را پر کنید. روی یکی از نودهای Supabase مطمئن شوید credential «Custom Auth account» انتخاب شده.
3. یک بار «Execute Workflow» بزنید و نود آخر هر شاخه را نگاه کنید:
   - `Pack Car/Moto` (ازکی)، `Site2 Output Car/Moto` (شوراکا)، `Site3 Output Car/Moto` (پلاس‌بیمه)
   - `Check Errors` اگر سایتی شکست خورده باشد اجرا را ناموفق می‌کند و نام سایت و پیام خطا را می‌نویسد.
   - در `Site3 Output` ردیفی با `unmapped` یعنی شرکتی در پلاس‌بیمه هست که در نگاشت `KEYS` (نودهای Normalize Site3 Car/Moto) نیست.
4. Active کنید.

## رفتار در خطا
هر سایت و هر وسیله جداست: اگر مثلاً قیمت موتور شوراکا خطا بدهد، خودروی شوراکا و دو سایت دیگر کامل ثبت می‌شوند. خطا به نود `Failed SiteN Car/Moto` می‌رود.
اگر لاگین یک سایت خطا بدهد، هر دو وسیله‌ی همان سایت از دست می‌روند (در گزارش با `both`).
`Check Errors` در پایان اجرا، اگر چیزی شکست خورده باشد، اجرا را «ناموفق» می‌کند و می‌نویسد کدام سایت/وسیله و در کدام نود؛ مثلاً
`site3/moto_1403 [Insert Commission Site3 Moto]: HTTP 400 …`.
چون n8n شاخه‌ها را از بالا به پایین اجرا می‌کند، **ردیف شوراکا و در آن شاخه‌ی موتور باید پایین‌ترین شاخه روی بوم بماند.**

## هنوز باز
- سناریوی خودرو در سه سایت یکسان نیست: شوراکا «بدون بیمه‌نامه‌ی قبلی»، ازکی و پلاس‌بیمه «با بیمه‌نامه‌ی قبلی».
- ازکی خودرو: پارامتر `vehicleUsageModel=[object Object]` و `draftId` ثابت (ممکن است منقضی شود).
