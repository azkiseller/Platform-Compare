# داده‌های داشبورد

هر سایت یک فایل دارد که workflow (n8n) بعد از هر اجرا **کل فایل** را بازنویسی می‌کند:

- `site1.json` ازکی ایجنت
- `site2.json` شرکاء
- `site3.json` بیمه پلاس

```json
{
 "site": "site1",
 "coverage": "third",
 "captured_at": "2026-10-26T16:35:25.452Z",
 "rows": [ { "company_key": "arman", "rate": 14 } ]
}
```

`rate` عدد درصد است (یا `null`). تاریخچه‌ی تغییرات در history گیت همین فایل‌ها می‌ماند.
