# Schema PostgreSQL hiện tại của MLedu

Tài liệu tham chiếu schema vật lý, đối chiếu metadata `mledu-dev` với **21 migration** tới `20261031110000_tests.sql` ngày **31/10/2026**. SQL trong [supabase/migrations](../../supabase/migrations/) là nguồn triển khai; tài liệu này không phải DDL thứ hai hoặc bằng chứng CI/staging/production. [plans.md](plans.md) vẫn quyết định nghiệp vụ.

## Ranh giới schema

| Schema | Nội dung hiện tại | Truy cập |
| --- | --- | --- |
| `app` | 23 bảng ứng dụng bên dưới; enum `account_type`; sequence `student_code_seq`, `weekly_schedules_revision_seq` | Không expose qua Data API; tất cả bảng bật RLS, không cấp quyền đọc/ghi trực tiếp cho `anon`/`authenticated` |
| `api` | RPC truy vấn/lệnh nghiệp vụ; không có bảng | Schema duy nhất expose theo `supabase/config.toml`; từng RPC có grant và kiểm tra actor/scope |
| `app_private` | Helper quyền, chuẩn hóa, transaction/history và composite type `student_input`; không có bảng | Không expose qua Data API |
| `auth`, `storage` | Supabase quản lý | Không liệt kê lại cấu trúc nội bộ; avatar dùng bucket private `avatars` và Storage API |

Luồng nghiệp vụ: Vue → Workers/Hono → RPC. Service-side function không thay kiểm tra phiên/quyền. Không có tenant hoặc phân quyền theo địa điểm.

## Quy ước

- Tên bảng/cột bên dưới là tên SQL thật; mỗi cột liệt kê riêng, đúng kiểu và NULLability.
- `timestamptz` là `timestamp with time zone`; `time` là `time without time zone`. Ngày nghiệp vụ dùng `Asia/Ho_Chi_Minh`.
- `—` ở cột mặc định nghĩa là không có DEFAULT SQL; cột nullable có thể nhận NULL khi bỏ giá trị. Identity được ghi riêng.
- PK/FK/UQ/exclusion và partial unique index được liệt kê theo metadata. Kiểm tra nghiệp vụ trong RPC không được coi là constraint DB nếu SQL không khai báo.
- Các danh mục/hồ sơ có `deleted_*` dùng xóa mềm; không áp giả định này cho mọi bảng. History và sự kiện giữ độc lập với hạn audit 60 ngày.

## Danh mục bảng

| Nhóm | Bảng |
| --- | --- |
| Tài khoản và avatar | [`app.account_profiles`](#appaccount_profiles), [`app.auth_commands`](#appauth_commands), [`app.avatar_uploads`](#appavatar_uploads) |
| Danh mục và học sinh | [`app.catalog_entries`](#appcatalog_entries), [`app.sites`](#appsites), [`app.rooms`](#approoms), [`app.students`](#appstudents), [`app.student_contacts`](#appstudent_contacts) |
| Lớp, phân công và lần tham gia | [`app.classes`](#appclasses), [`app.class_assignments`](#appclass_assignments), [`app.class_students`](#appclass_students), [`app.participations`](#appparticipations), [`app.class_lifecycle_events`](#appclass_lifecycle_events) |
| Lịch và chuyên cần | [`app.weekly_schedules`](#appweekly_schedules), [`app.class_sessions`](#appclass_sessions), [`app.holidays`](#appholidays), [`app.attendance`](#appattendance) |
| Học vụ (GĐ5, đang triển khai) | [`app.test_templates`](#apptest_templates), [`app.test_template_versions`](#apptest_template_versions), [`app.tests`](#apptests), [`app.test_config_versions`](#apptest_config_versions), [mức/phần/kỹ năng của bài](#mức-phần-và-kỹ-năng-của-bài) |
| Audit, lịch sử và outbox | [`app.audit_events`](#appaudit_events), [`app.business_entity_versions`](#appbusiness_entity_versions), [`app.outbox_events`](#appoutbox_events), [`app.outbox_deliveries`](#appoutbox_deliveries) |

## Tài khoản và avatar

### app.account_profiles

`id` đồng thời là FK tới Supabase Auth; `account_type` là enum `admin | receptionist | user`. Giáo viên/trợ giảng là phân công lớp, không phải loại tài khoản. `sessions_valid_after` và `credentials_changed_at` phục vụ kiểm tra phiên/credential. Avatar là path tương đối hoặc NULL; không có FK tới `storage.objects`.

Nguồn: [20261026160100_account_profiles.sql](../../supabase/migrations/20261026160100_account_profiles.sql), [20261027100000_account_auth.sql](../../supabase/migrations/20261027100000_account_auth.sql), [20261027100100_profile_avatar.sql](../../supabase/migrations/20261027100100_profile_avatar.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | — |
| `login_email_key` | `text` | Không | — |
| `full_name` | `text` | Không | — |
| `account_type` | `app.account_type` | Không | `'user'::app.account_type` |
| `is_enabled` | `boolean` | Không | `true` |
| `must_change_password` | `boolean` | Không | `true` |
| `phone` | `text` | Có | — |
| `birth_date` | `date` | Có | — |
| `avatar_path` | `text` | Có | — |
| `sessions_valid_after` | `timestamptz` | Có | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `credentials_changed_at` | `timestamptz` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT`.
- `UNIQUE (login_email_key)`.
- `PRIMARY KEY (id)`.

### app.auth_commands

Lệnh xác thực đã chuẩn bị để phối hợp Auth Admin API với DB/audit. `target_id` và `actor_session_id` không có FK; không suy ra ràng buộc chỉ từ tên cột. Có `expires_at`/`consumed_at`, không phải bảng token khôi phục riêng. Không đưa dữ liệu thật của `payload` vào tài liệu/audit.

Nguồn: [20261027100000_account_auth.sql](../../supabase/migrations/20261027100000_account_auth.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `kind` | `text` | Không | — |
| `source` | `text` | Không | — |
| `actor_id` | `uuid` | Có | — |
| `actor_session_id` | `uuid` | Có | — |
| `operator` | `text` | Có | — |
| `target_id` | `uuid` | Không | — |
| `payload` | `jsonb` | Không | `'{}'::jsonb` |
| `expected_version` | `bigint` | Có | — |
| `request_id` | `text` | Có | — |
| `created_at` | `timestamptz` | Không | `now()` |
| `expires_at` | `timestamptz` | Không | `(clock_timestamp() + '00:01:00'::interval)` |
| `consumed_at` | `timestamptz` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (actor_id) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (id)`.

### app.avatar_uploads

Theo dõi vòng đời file private Storage bằng `path`; phải verified trước committed, không đồng thời committed/discarded. Metadata này không thay cơ chế Storage API.

Nguồn: [20261027100100_profile_avatar.sql](../../supabase/migrations/20261027100100_profile_avatar.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `path` | `text` | Không | — |
| `account_id` | `uuid` | Không | — |
| `created_at` | `timestamptz` | Không | `now()` |
| `verified_at` | `timestamptz` | Có | — |
| `committed_at` | `timestamptz` | Có | — |
| `discarded_at` | `timestamptz` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (account_id) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (path)`.

## Danh mục và học sinh

### app.catalog_entries

`kind` chỉ nhận `subject` hoặc `grade`; tên 1–100 ký tự, trim/NFC. `UNIQUE(kind, name_key)` áp dụng cả bản xóa mềm. FK của lớp chỉ kiểm tra ID tồn tại; RPC kiểm tra đúng loại và trạng thái hoạt động khi chọn mới.

Nguồn: [20261027110000_catalogs.sql](../../supabase/migrations/20261027110000_catalogs.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `kind` | `text` | Không | — |
| `name` | `text` | Không | — |
| `name_key` | `text` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `UNIQUE (kind, name_key)`.
- `PRIMARY KEY (id)`.

### app.sites

Danh mục địa điểm dùng chung toàn trung tâm; không phải tenant hoặc phạm vi phân quyền. `name_key` duy nhất kể cả xóa mềm; `address` bắt buộc, 1–500 ký tự.

Nguồn: [20261027110000_catalogs.sql](../../supabase/migrations/20261027110000_catalogs.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `name` | `text` | Không | — |
| `name_key` | `text` | Không | — |
| `address` | `text` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `UNIQUE (name_key)`.
- `PRIMARY KEY (id)`.

### app.rooms

Phòng thuộc `site_id`; duy nhất theo `(site_id, name_key)` kể cả xóa mềm. Không có tenant, sức chứa hoặc bộ thuộc tính phòng khác trong schema hiện tại.

Nguồn: [20261027110000_catalogs.sql](../../supabase/migrations/20261027110000_catalogs.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `site_id` | `uuid` | Không | — |
| `name` | `text` | Không | — |
| `name_key` | `text` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `UNIQUE (site_id, name_key)`.
- `PRIMARY KEY (id)`.
- `FOREIGN KEY (site_id) REFERENCES app.sites(id)`.

### app.students

`code` duy nhất, sinh từ `student_code_seq` với dạng `HS` + số; giữ ID/mã qua xuất–nhập/khôi phục. Chống trùng tên + số liên hệ dùng chuẩn hóa, RPC và khóa; không có UNIQUE đơn trên tên hoặc số điện thoại.

Nguồn: [20261027120000_students.sql](../../supabase/migrations/20261027120000_students.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `code` | `text` | Không | `('HS'::text \|\| lpad((nextval('app.student_code_seq'::regclass))::text, 6, '0'::text))` |
| `full_name` | `text` | Không | — |
| `name_key` | `text` | Không | — |
| `parent_name` | `text` | Có | — |
| `birth_date` | `date` | Có | — |
| `school` | `text` | Có | — |
| `general_note` | `text` | Có | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `UNIQUE (code)`.
- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (id)`.

### app.student_contacts

PK ghép `(student_id, kind, phone)`; `kind = parent | student`, `position >= 1`. Không có cột `id`, tên liên hệ hoặc hồ sơ tài khoản phụ huynh; tên phụ huynh lưu tại `students.parent_name`.

Nguồn: [20261027120000_students.sql](../../supabase/migrations/20261027120000_students.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `student_id` | `uuid` | Không | — |
| `kind` | `text` | Không | — |
| `phone` | `text` | Không | — |
| `position` | `integer` | Không | — |

Khóa và tham chiếu:

- `PRIMARY KEY (student_id, kind, phone)`.
- `FOREIGN KEY (student_id) REFERENCES app.students(id)`.

## Lớp, phân công và lần tham gia

### app.classes

`subject_id` và `grade_id` cùng trỏ `catalog_entries`; RPC kiểm tra `kind`. Ngày kết thúc không trước ngày mở; `admin_state = open | closed` nhất quán với `closed_at`. `school_year_start` là integer 1000–9998 hoặc NULL, hiển thị hai năm liên tiếp, không ràng buộc ngày lớp. Tên lớp không có UNIQUE.

Nguồn: [20261027130000_classes.sql](../../supabase/migrations/20261027130000_classes.sql), [20261030130000_class_school_year.sql](../../supabase/migrations/20261030130000_class_school_year.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `name` | `text` | Không | — |
| `name_key` | `text` | Không | — |
| `subject_id` | `uuid` | Không | — |
| `grade_id` | `uuid` | Không | — |
| `start_date` | `date` | Không | — |
| `end_date` | `date` | Không | — |
| `note` | `text` | Có | — |
| `admin_state` | `text` | Không | `'open'::text` |
| `closed_at` | `timestamptz` | Có | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |
| `school_year_start` | `integer` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (grade_id) REFERENCES app.catalog_entries(id)`.
- `PRIMARY KEY (id)`.
- `FOREIGN KEY (subject_id) REFERENCES app.catalog_entries(id)`.

### app.class_assignments

`role = teacher | assistant`; `effective_period` phải bằng `dated_period(start_date,end_date,ended_at)`. Exclusion chặn chồng thời hạn cùng người/cùng lớp kể cả khác vai trò. Quyền phụ thuộc phân công hiệu lực hiện tại, không suy từ JWT hoặc lịch sử.

Nguồn: [20261027130000_classes.sql](../../supabase/migrations/20261027130000_classes.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_id` | `uuid` | Không | — |
| `account_id` | `uuid` | Không | — |
| `role` | `text` | Không | — |
| `start_date` | `date` | Không | — |
| `end_date` | `date` | Không | — |
| `subject_note` | `text` | Có | — |
| `ended_at` | `timestamptz` | Có | — |
| `end_kind` | `text` | Có | — |
| `end_reason` | `text` | Có | — |
| `ended_by` | `uuid` | Có | — |
| `effective_period` | `tstzrange` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |

Khóa và tham chiếu:

- `FOREIGN KEY (account_id) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (class_id) REFERENCES app.classes(id)`.
- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (ended_by) REFERENCES app.account_profiles(id)`.
- `EXCLUDE USING gist (class_id WITH =, account_id WITH =, effective_period WITH &&)`.
- `PRIMARY KEY (id)`.

### app.class_students

Hồ sơ học sinh–lớp. Partial unique `(class_id, student_id) WHERE deleted_at IS NULL`; xóa mềm rồi thêm lại có ID mới, không ghi đè hồ sơ cũ.

Nguồn: [20261027140000_enrollments.sql](../../supabase/migrations/20261027140000_enrollments.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_id` | `uuid` | Không | — |
| `student_id` | `uuid` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (class_id) REFERENCES app.classes(id)`.
- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (id)`.
- `FOREIGN KEY (student_id) REFERENCES app.students(id)`.
- `CREATE UNIQUE INDEX class_students_active_key ON app.class_students USING btree (class_id, student_id) WHERE (deleted_at IS NULL)`.

### app.participations

Nhiều lần tham gia trong một `class_student_id`. `leave_date` là ngày bắt đầu nghỉ, phải sau `join_date`; `not_before` chặn lần thêm lại có hiệu lực trước xóa cũ. `effective_period` là khoảng `[)` được tính bằng `participation_period(...)`, chịu mốc ngày lớp và sự kiện kết thúc; exclusion chặn chồng trong một hồ sơ. Khóa ngày đã lưu và kiểm tra actor nằm trong RPC.

Nguồn: [20261027140000_enrollments.sql](../../supabase/migrations/20261027140000_enrollments.sql), [20261027140100_enrollment_history_guards.sql](../../supabase/migrations/20261027140100_enrollment_history_guards.sql), [20261027140200_enrollment_lock_order.sql](../../supabase/migrations/20261027140200_enrollment_lock_order.sql), [20261028100000_student_edit_permissions.sql](../../supabase/migrations/20261028100000_student_edit_permissions.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_student_id` | `uuid` | Không | — |
| `join_date` | `date` | Không | — |
| `leave_date` | `date` | Có | — |
| `class_end_date` | `date` | Không | — |
| `not_before` | `timestamptz` | Có | — |
| `note` | `text` | Có | — |
| `ended_at` | `timestamptz` | Có | — |
| `end_kind` | `text` | Có | — |
| `end_reason` | `text` | Có | — |
| `ended_by` | `uuid` | Có | — |
| `effective_period` | `tstzrange` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |

Khóa và tham chiếu:

- `FOREIGN KEY (class_student_id) REFERENCES app.class_students(id)`.
- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (ended_by) REFERENCES app.account_profiles(id)`.
- `EXCLUDE USING gist (class_student_id WITH =, effective_period WITH &&)`.
- `PRIMARY KEY (id)`.

### app.class_lifecycle_events

Sự kiện `close | reopen | delete | restore` của lớp, lưu bất biến bằng trigger. Không phải bảng khoảng trạng thái có `valid_from`/`valid_to`; các xử lý vòng đời còn gọi hook liên miền theo giai đoạn triển khai.

Nguồn: [20261027140000_enrollments.sql](../../supabase/migrations/20261027140000_enrollments.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_id` | `uuid` | Không | — |
| `kind` | `text` | Không | — |
| `reason` | `text` | Có | — |
| `happened_at` | `timestamptz` | Không | `now()` |
| `actor_id` | `uuid` | Không | — |

Khóa và tham chiếu:

- `FOREIGN KEY (actor_id) REFERENCES app.account_profiles(id)`.
- `FOREIGN KEY (class_id) REFERENCES app.classes(id)`.
- `PRIMARY KEY (id)`.

## Lịch và chuyên cần

### app.weekly_schedules

Mỗi hàng là phiên bản lịch tuần bất biến từ `applies_on`; các slot nằm trong mảng JSONB `slots`, không có một hàng/phòng/thứ riêng. `revision` là identity ALWAYS, unique toàn bảng (sequence `weekly_schedules_revision_seq`). RPC kiểm tra nội dung slot; CHECK chỉ xác nhận JSON array.

Nguồn: [20261030100000_scheduling.sql](../../supabase/migrations/20261030100000_scheduling.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_id` | `uuid` | Không | — |
| `applies_on` | `date` | Không | — |
| `slots` | `jsonb` | Không | — |
| `revision` | `bigint` | Không | `GENERATED ALWAYS AS IDENTITY` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |

Khóa và tham chiếu:

- `FOREIGN KEY (class_id) REFERENCES app.classes(id)`.
- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (id)`.
- `UNIQUE (revision)`.

### app.class_sessions

Buổi thực tế có `kind = weekly | makeup`; `status = scheduled | off | holiday | removed_schedule | removed_class`. `starts_at`/`ends_at` cùng ngày giờ Việt Nam và kết thúc sau bắt đầu. `original_day`/`original_start` định danh lần sinh lịch tuần; partial unique giữ một buổi tuần cho mỗi lớp/ngày/giờ gốc. `room_name`, `site_name`, `site_address` là snapshot; chỉ `room_id` là FK vị trí. Exclusion đặt phòng dùng `[)`, chỉ khi scheduled và có phòng, DEFERRABLE. Không có `weekly_schedule_id`, `holiday_id`, `makeup_for_session_id` hoặc `location_id`.

Nguồn: [20261030100000_scheduling.sql](../../supabase/migrations/20261030100000_scheduling.sql), [20261030120000_scheduling_preview_scope.sql](../../supabase/migrations/20261030120000_scheduling_preview_scope.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_id` | `uuid` | Không | — |
| `kind` | `text` | Không | — |
| `original_day` | `date` | Không | — |
| `original_start` | `time` | Không | — |
| `starts_at` | `timestamptz` | Không | — |
| `ends_at` | `timestamptz` | Không | — |
| `room_id` | `uuid` | Có | — |
| `room_name` | `text` | Có | — |
| `site_name` | `text` | Có | — |
| `site_address` | `text` | Có | — |
| `status` | `text` | Không | — |
| `is_exception` | `boolean` | Không | `false` |
| `resume_status` | `text` | Có | — |
| `holiday_status` | `text` | Có | — |
| `row_version` | `bigint` | Không | `1` |
| `attendance_version` | `bigint` | Không | `0` |
| `created_at` | `timestamptz` | Không | `now()` |

Khóa và tham chiếu:

- `FOREIGN KEY (class_id) REFERENCES app.classes(id)`.
- `PRIMARY KEY (id)`.
- `FOREIGN KEY (room_id) REFERENCES app.rooms(id)`.
- `EXCLUDE USING gist (room_id WITH =, tstzrange(starts_at, ends_at, '[)'::text) WITH &&) WHERE (((status = 'scheduled'::text) AND (room_id IS NOT NULL))) DEFERRABLE`.
- `CREATE UNIQUE INDEX sessions_weekly_occurrence ON app.class_sessions USING btree (class_id, original_day, original_start) WHERE (kind = 'weekly'::text)`.

### app.holidays

PK là `day`, không có `id`, dải ngày hoặc FK từ buổi tới lễ. `active` biểu thị áp dụng/bỏ lễ; phiên bản lịch sử được giữ qua cơ chế history/audit, không tạo bảng lễ thứ hai.

Nguồn: [20261030100000_scheduling.sql](../../supabase/migrations/20261030100000_scheduling.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `day` | `date` | Không | — |
| `name` | `text` | Không | — |
| `active` | `boolean` | Không | — |
| `row_version` | `bigint` | Không | `1` |

Khóa và tham chiếu:

- `PRIMARY KEY (day)`.

### app.attendance

PK `(session_id, student_id)` theo học sinh + buổi thực tế; không FK tới hồ sơ lớp/lần tham gia. `present` là boolean NOT NULL; chưa lưu là chưa có hàng (DTO có thể biểu diễn null), không phải một giá trị enum lưu trong DB. `class_sessions.attendance_version` cùng fingerprint kiểm soát lưu cả roster.

Nguồn: [20261030110000_attendance.sql](../../supabase/migrations/20261030110000_attendance.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `session_id` | `uuid` | Không | — |
| `student_id` | `uuid` | Không | — |
| `present` | `boolean` | Không | — |
| `note` | `text` | Có | — |
| `row_version` | `bigint` | Không | `1` |
| `updated_at` | `timestamptz` | Không | `now()` |
| `updated_by` | `uuid` | Không | — |

Khóa và tham chiếu:

- `PRIMARY KEY (session_id, student_id)`.
- `FOREIGN KEY (session_id) REFERENCES app.class_sessions(id)`.
- `FOREIGN KEY (student_id) REFERENCES app.students(id)`.
- `FOREIGN KEY (updated_by) REFERENCES app.account_profiles(id)`.

## Học vụ

GĐ5 đã có hai feature: thư viện template dùng chung (TEST-02) và bài kiểm tra trong lớp với snapshot cấu hình (TEST-05). Kết quả, IELTS tính điểm, công bố và nhận xét **chưa có migration**; xem [thiết kế học vụ](assessment-schema.md).

### app.test_templates

Gốc ổn định của một template; không có FK lớp/địa điểm. Chỉ Admin hiện hành ghi qua RPC `api.*_test_template`. Xóa mềm chỉ ngừng chọn cho bài mới; trigger chặn `DELETE`.

Nguồn: [20261031100000_test_templates.sql](../../supabase/migrations/20261031100000_test_templates.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `current_version_id` | `uuid` | Không | — |
| `row_version` | `bigint` | Không | `1` |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `updated_at` | `timestamptz` | Không | `now()` |
| `deleted_at` | `timestamptz` | Có | — |
| `deleted_by` | `uuid` | Có | — |
| `deleted_reason` | `text` | Có | — |

Khóa và tham chiếu:

- `PRIMARY KEY (id)`.
- `FOREIGN KEY (id, current_version_id) REFERENCES app.test_template_versions(template_id, id) DEFERRABLE INITIALLY DEFERRED` — gốc và phiên bản đầu tạo trong cùng transaction.
- `FOREIGN KEY (created_by)`, `FOREIGN KEY (deleted_by) REFERENCES app.account_profiles(id)`.
- CHECK đồng bộ ba cột `deleted_*` (lý do 1–1.000 ký tự).

### app.test_template_versions

Phiên bản bất biến: trigger `reject_change` chặn `UPDATE`/`DELETE`/`TRUNCATE`. Tên/mô tả lưu theo phiên bản để bài cũ giữ đúng nguồn. `config` là JSONB có kiểu (số/phân số/chữ/IELTS), CHECK bắt buộc ở dạng đã chuẩn hóa bởi `app_private.test_template_config`; `config_schema_version = 1`. IELTS có `formulaVersion = mledu-ielts-v1` do backend gắn.

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `template_id` | `uuid` | Không | — |
| `revision` | `bigint` | Không | — |
| `name` | `text` | Không | — |
| `description` | `text` | Có | — |
| `config_schema_version` | `smallint` | Không | — |
| `config` | `jsonb` | Không | — |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |

Khóa và tham chiếu:

- `PRIMARY KEY (id)`.
- `UNIQUE (template_id, revision)`; `UNIQUE (template_id, id)` phục vụ FK con trỏ.
- `FOREIGN KEY (template_id) REFERENCES app.test_templates(id)`.
- `FOREIGN KEY (created_by) REFERENCES app.account_profiles(id)`.
- CHECK tên 1–200 ký tự, mô tả NULL hoặc 1–5.000 ký tự (đã trim/NFC).

### app.tests

Bài kiểm tra thuộc một lớp (TEST-05). Cho trùng tên trong lớp. `show_components` là tùy chọn hiển thị toàn bài (TEST-04), nằm ngoài snapshot bất biến; RPC đặt `false` khi cấu hình không có chi tiết. Ghi qua `api.create_test`, `update_test` (tên/ngày/mô tả), `change_test_config`, `set_test_show_components`; trigger chặn `DELETE`/`TRUNCATE`. Cột `deleted_*` dành cho TEST-06, chưa có lệnh xóa/khôi phục.

Nguồn: [20261031110000_tests.sql](../../supabase/migrations/20261031110000_tests.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `class_id` | `uuid` | Không | — |
| `name` | `text` | Không | — |
| `name_key` | `text` | Không | — |
| `test_on` | `date` | Không | — |
| `description` | `text` | Có | — |
| `current_config_id` | `uuid` | Không | — |
| `show_components` | `boolean` | Không | `false` |
| `row_version` | `bigint` | Không | `1` |
| `created_at`, `updated_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |
| `deleted_at`, `deleted_by`, `deleted_reason` | | Có | — |

Khóa và tham chiếu:

- `PRIMARY KEY (id)`; index `(class_id, test_on DESC)`, `(current_config_id)`.
- `FOREIGN KEY (class_id) REFERENCES app.classes(id)`; actor → `app.account_profiles(id)`.
- `FOREIGN KEY (id, current_config_id) REFERENCES app.test_config_versions(test_id, id) DEFERRABLE INITIALLY DEFERRED`.
- CHECK tên 1–200 ký tự, `name_key = name_key(name)`, mô tả NULL hoặc 1–5.000 ký tự, đồng bộ `deleted_*`.

### app.test_config_versions

Snapshot cấu hình bất biến của bài; mỗi lần đổi cấu hình thêm `revision`. `source_template_version_id` chỉ là provenance (NULL khi cấu hình riêng). Trigger `reject_change` chặn `UPDATE`/`DELETE`/`TRUNCATE`.

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `test_id` | `uuid` | Không | — |
| `revision` | `bigint` | Không | — |
| `scale_kind` | `text` | Không | — |
| `input_mode` | `text` | Có | — |
| `max_score` | `numeric` | Có | — |
| `total_questions` | `integer` | Có | — |
| `formula_version` | `text` | Có | — |
| `source_template_version_id` | `uuid` | Có | — |
| `created_at` | `timestamptz` | Không | `now()` |
| `created_by` | `uuid` | Không | — |

Khóa và tham chiếu:

- `PRIMARY KEY (id)`; `UNIQUE (test_id, revision)`, `UNIQUE (test_id, id)`; index `(source_template_version_id)`.
- `FOREIGN KEY (test_id) REFERENCES app.tests(id)`; `FOREIGN KEY (source_template_version_id) REFERENCES app.test_template_versions(id)`.
- CHECK hình dạng theo loại: số (`direct/components`, `max_score > 0`, ≤2 số lẻ), phân số (`total_questions ≥ 1`), chữ (`direct`), IELTS (`input_mode` NULL, có `formula_version`).

### Mức, phần và kỹ năng của bài

- `app.test_letter_levels(id, config_id, code, label, label_key, sort_order)`: UQ `(config_id, id)`, `(config_id, label_key)`, `(config_id, sort_order)`; `code = 'l' || sort_order`, 1–20 mức, nhãn 1–100 ký tự.
- `app.test_components(id, config_id, code, name, name_key, max_score, total_questions, sort_order)`: UQ tương tự; `code = 'c' || sort_order`, 1–50 phần, đúng một loại giới hạn.
- `app.test_ielts_skills(config_id, skill, input_mode, max_questions)`: PK `(config_id, skill)`; `max_questions` chỉ có với L/R `detailed`.

Cả ba bảng chặn `UPDATE`/`DELETE`/`TRUNCATE`. Constraint trigger trì hoãn `app_private.check_test_config` (SECURITY DEFINER, chạy lúc commit) dựng lại cấu hình từ các dòng và bắt buộc nó hợp lệ, đã chuẩn hóa theo cùng validator template; phát hiện số dòng/tổng/mã sai mà CHECK một dòng không chứng minh được.

RLS bật trên mọi bảng; không grant cho `anon`/`authenticated`.

## Audit, lịch sử và outbox

### app.audit_events

`source = app | excel | job | ops`. `entity_refs` và `before_after` là JSONB đã loại bí mật; không có FK đa hình tới đối tượng. `expires_at = created_at + 60 ngày`. Actor có thể NULL cho job/ops; không có `job_id` hoặc `import_id` trong bảng hiện tại.

Nguồn: [20261026160200_audit_history_outbox.sql](../../supabase/migrations/20261026160200_audit_history_outbox.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `actor_id` | `uuid` | Có | — |
| `source` | `text` | Không | — |
| `action` | `text` | Không | — |
| `entity_refs` | `jsonb` | Không | `'{}'::jsonb` |
| `before_after` | `jsonb` | Không | `'{}'::jsonb` |
| `request_id` | `text` | Có | — |
| `created_at` | `timestamptz` | Không | `now()` |
| `expires_at` | `timestamptz` | Không | — |

Khóa và tham chiếu:

- `FOREIGN KEY (actor_id) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (id)`.

### app.business_entity_versions

Lịch sử nghiệp vụ bất biến, giữ không thời hạn, unique `(entity_kind, entity_id, revision)`; `entity_id` là tham chiếu logic do RPC kiểm soát, không FK đa hình. `sanitized_snapshot` loại bí mật.

Nguồn: [20261026160200_audit_history_outbox.sql](../../supabase/migrations/20261026160200_audit_history_outbox.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `entity_kind` | `text` | Không | — |
| `entity_id` | `uuid` | Không | — |
| `revision` | `bigint` | Không | — |
| `sanitized_snapshot` | `jsonb` | Không | — |
| `changed_by` | `uuid` | Có | — |
| `changed_at` | `timestamptz` | Không | `now()` |
| `reason` | `text` | Có | — |

Khóa và tham chiếu:

- `FOREIGN KEY (changed_by) REFERENCES app.account_profiles(id)`.
- `PRIMARY KEY (id)`.
- `UNIQUE (entity_kind, entity_id, revision)`.

### app.outbox_events

Sự kiện bền vững với `event_key` duy nhất. Đối tượng dùng cặp `subject_kind`/`subject_id`, không có FK `class_id`; `minimal_payload` không chứa bí mật. Bảng nền không đồng nghĩa mọi producer/dispatcher ở các giai đoạn sau đã triển khai.

Nguồn: [20261026160200_audit_history_outbox.sql](../../supabase/migrations/20261026160200_audit_history_outbox.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `id` | `uuid` | Không | `gen_random_uuid()` |
| `event_key` | `text` | Không | — |
| `event_kind` | `text` | Không | — |
| `subject_kind` | `text` | Không | — |
| `subject_id` | `uuid` | Không | — |
| `minimal_payload` | `jsonb` | Không | `'{}'::jsonb` |
| `created_at` | `timestamptz` | Không | `now()` |

Khóa và tham chiếu:

- `UNIQUE (event_key)`.
- `PRIMARY KEY (id)`.

### app.outbox_deliveries

PK `(event_id, recipient_id)`; `state = pending | retry | delivered`; `attempt_count >= 0`, `delivered_at` đi cùng trạng thái delivered. Không có bảng `notifications`, `background_jobs` hoặc `job_attempts` trong database hiện tại.

Nguồn: [20261026160200_audit_history_outbox.sql](../../supabase/migrations/20261026160200_audit_history_outbox.sql).

| Cột | Kiểu | NULL | Mặc định |
| --- | --- | --- | --- |
| `event_id` | `uuid` | Không | — |
| `recipient_id` | `uuid` | Không | — |
| `state` | `text` | Không | `'pending'::text` |
| `attempt_count` | `integer` | Không | `0` |
| `next_attempt_at` | `timestamptz` | Có | — |
| `delivered_at` | `timestamptz` | Có | — |
| `created_at` | `timestamptz` | Không | `now()` |

Khóa và tham chiếu:

- `FOREIGN KEY (event_id) REFERENCES app.outbox_events(id)`.
- `PRIMARY KEY (event_id, recipient_id)`.
- `FOREIGN KEY (recipient_id) REFERENCES app.account_profiles(id)`.

## Đối chiếu với ERD thiết kế

[architecture.drawio](../diagrams/architecture.drawio) có các trang thiết kế logic của cả giai đoạn chưa triển khai. Các tên/quan hệ sau trong thiết kế cũ **không phải tên schema hiện tại**:

| Thiết kế logic/đề xuất | Schema hiện tại |
| --- | --- |
| `subjects`, `grade_levels` | `app.catalog_entries` với `kind = 'subject'` hoặc `kind = 'grade'`; lớp dùng `grade_id` |
| `staff_assignments` | `app.class_assignments`; khoảng quyền là `effective_period`, vai trò ở `role` |
| `student_class_profiles` | `app.class_students` |
| `participation_periods`, `joined_on`, `left_on` | `app.participations`, `join_date`, `leave_date`; FK là `class_student_id` |
| `class_state_periods` | Chưa có bảng khoảng trạng thái; hiện lưu sự kiện trong `app.class_lifecycle_events` và trạng thái tại `app.classes` |
| `locations`, `rooms.location_id` | `app.sites`, `app.rooms.site_id` |
| Một hàng `weekly_schedules`/slot | Phiên bản bất biến gồm `applies_on`, mảng `slots` và `revision` |
| `class_sessions.weekly_schedule_id`, `holiday_id`, `makeup_for_session_id` | Không có các cột/FK này; xem trường thật ở `app.class_sessions` |
| `holidays.id`/dải ngày | `app.holidays.day` là PK |
| `attendance_results`/enum trạng thái | `app.attendance` với boolean `present` |
| `outbox_events.class_id` | `subject_kind` + `subject_id` là tham chiếu logic |
| `audit_events.job_id`, `import_id` | Không có; định danh liên quan nằm trong `entity_refs` |

`auth_commands` và `avatar_uploads` là bảng hiện có dù chưa vẽ trong ERD logic. Ngoài các bảng template/bài/snapshot ở trên, các bảng học vụ còn lại (kết quả, IELTS, nhận xét), phụ huynh, học phí, thanh toán, Excel, `notifications`, `background_jobs` và `job_attempts` chưa có migration tạo bảng; không coi chúng là schema đã chạy. Hợp đồng `api` được sinh tại [database.types.ts](../../apps/api/src/generated/database.types.ts), không chứa toàn bộ bảng private `app`.

### Thiết kế học vụ còn lại

[Thiết kế schema template và snapshot bài kiểm tra](assessment-schema.md) ngày **31/10/2026** mô tả TEST-01–06. Thư viện template và bài/snapshot cấu hình (`tests`, `test_config_versions`, mức/phần/kỹ năng; thêm cột `code` theo vị trí cho mức/phần) đã có migration ngày 31/10/2026 như mục [Học vụ](#học-vụ). Kết quả và IELTS vẫn là đề xuất; migration tương lai là nguồn DDL duy nhất.

## Cập nhật tài liệu

Khi có migration mới, đối chiếu cột/NULL/default/identity, PK/FK/index và RLS của DB local đã áp dụng; sửa trực tiếp tài liệu này và phần liên quan trong ERD. Không thêm SQL schema song song hoặc suy schema từ seed/DTO. Khi đọc thiết kế tương lai, luôn kiểm tra migration và trạng thái thực trước khi dùng tên bảng/cột.
