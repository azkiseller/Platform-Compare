# راه‌اندازی workflowها روی Supabase جدید

دو فایل:
- `Insurance Compare - 206 1397.json` → تب خودرو (`vehicle = 206_1397`)، هر ۶ ساعت، دقیقه‌ی ۵
- `Insurance Compare - moto 1403.json` → تب موتور (`vehicle = moto_1403`)، هر ۶ ساعت، دقیقه‌ی ۲۰

هر دو به پروژه‌ی Supabase جدید (`akaczqhvyemkjnwzgjzr`) می‌نویسند. هیچ رمز یا کلیدی داخل فایل‌ها نیست.

## ۱. قبل از import
workflow قدیمی را که به Supabase قبلی می‌نویسد **غیرفعال** کنید.

## ۲. Credentialها (Credentials ← Add ← «Custom Auth»)
نام‌ها را **دقیقاً** همین بگذارید تا هنگام import خودکار به نودها وصل شوند.

| نام credential | JSON |
|---|---|
| `Custom Auth account` | `{"headers":{"apikey":"sb_secret_..."}}` ← Secret key پروژه‌ی جدید (Project Settings ← API Keys) |
| `Shoraka Login` | `{"body":{"username":"…","password":"…"}}` |
| `Azkiagent Login` | `{"body":{"username":"…","password":"…"}}` |
| `Plusbimeh Mobile` | `{"body":{"MobileNumber":"…"}}` |
| `Plusbimeh Password` | `{"body":{"Password":"…"}}` |

- `Custom Auth account` اگر از قبل هست، فقط محتوایش را با کلید پروژه‌ی جدید عوض کنید. اگر کلید قدیمی `service_role` (JWT) استفاده می‌کنید:
  `{"headers":{"apikey":"<key>","Authorization":"Bearer <key>"}}`
- رمزهای شوراکا و پلاس‌بیمه را متفاوت بگذارید و رمزهایی را که در فایل قدیمی بودند عوض کنید.

## ۳. Import و فعال‌سازی
1. Workflows ← Import from File ← هر دو فایل.
2. روی نودهای Login باز کنید و مطمئن شوید credential درست انتخاب شده (اگر نام‌ها فرق داشته باشد، دستی انتخاب کنید).
3. یک بار «Execute Workflow» بزنید و نود آخر هر شاخه را نگاه کنید:
   - `Pack` (ازکی)، `Site2 Output` (شوراکا)، `Site3 Output` (پلاس‌بیمه)
   - `Check Errors` اگر سایتی شکست خورده باشد اجرا را ناموفق می‌کند و نام سایت و پیام خطا را می‌نویسد.
   - در `Site3 Output` ردیفی با `unmapped` یعنی شرکتی در پلاس‌بیمه هست که در نگاشت `KEYS` (نود Normalize Site3) نیست.
4. هر دو را Active کنید.

## رفتار در خطا
اگر یک سایت خطا بدهد (لاگین، پاسخ نامعتبر، یا رد شدن ثبت در Supabase)، خطا به نود `Failed SiteN` می‌رود و دو سایت دیگر کامل اجرا و ثبت می‌شوند.
`Check Errors` در پایان اجرا گزارش می‌دهد؛ چون n8n شاخه‌ها را از بالا به پایین اجرا می‌کند، **شاخه‌ی شوراکا باید پایین‌ترین شاخه روی بوم بماند.**

## هنوز باز
- سناریوی خودرو در سه سایت یکسان نیست: شوراکا «بدون بیمه‌نامه‌ی قبلی»، ازکی و پلاس‌بیمه «با بیمه‌نامه‌ی قبلی».
- ازکی خودرو: پارامتر `vehicleUsageModel=[object Object]` و `draftId` ثابت (ممکن است منقضی شود).
