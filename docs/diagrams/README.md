# ERD MLedu

Mở [architecture.drawio](architecture.drawio) bằng draw.io Desktop hoặc diagrams.net. File chứa **54 thực thể logic**, một trang mục lục và **9 trang ERD chi tiết**. Bảng, thuộc tính, đường nối và ghi chú đều chỉnh sửa được; mục lục và bảng có phụ đề `THAM CHIẾU` liên kết tới trang tương ứng.

Đây là **thiết kế đề xuất từ đặc tả**, không phải sơ đồ reverse-engineer từ database đang chạy. Nguồn nghiệp vụ là [plans.md](../developer/plans.md); lựa chọn nền tảng theo [techstack-va-chi-phi.md](../developer/techstack-va-chi-phi.md), đặc biệt các mục 1, 4, 5 và 6. Tên bảng, kiểu dữ liệu, việc gộp tháng/kỳ và cách lưu phiên bản là lựa chọn mô hình hóa để review, chưa phải migration triển khai. Các giai đoạn và cấu trúc source được đề xuất trong [kế hoạch triển khai MLedu](../superpowers/plans/2026-10-26-trien-khai-mledu.md).

## Các trang

| Trang | Nội dung | Đối chiếu chính |
| --- | --- | --- |
| 00 | Mục lục, ký hiệu và phạm vi thiết kế | Tổng quan, C.1.1, tech stack mục 1/4 |
| 01 | Auth, tài khoản, học sinh, liên hệ, lớp, phân công và lần tham gia | AUTH-01–08, STU-01–04, CLASS-01–05, CAT-01 |
| 02 | Địa điểm, phòng, lịch tuần, ngày lễ, buổi thực tế và điểm danh | SCHED-01–06, ATT-01 |
| 03 | Bài kiểm tra, mẫu chữ, cấu hình có phiên bản, kết quả và điểm thành phần | TEST-01–06, ACAD-01 |
| 04 | Nhận xét gắn bài/đợt, trang lớp và liên kết phụ huynh | COMMENT-01–03, ACAD-01, PORTAL-01–03 |
| 05 | Hình thức thu, tháng/kỳ, mức gốc, nghĩa vụ và điều chỉnh học phí | FEE-01–04, FEE-07–10 |
| 06 | Cấu hình ngoài học phí, lựa chọn học sinh theo thời gian và lần phát sinh | FEE-07, FEE-11 |
| 07 | Lần thu, chi tiết tiền thực nhận và sự kiện Admin gỡ thu sai | FEE-03, FEE-05–06, DASH-01 |
| 08 | File private, lô nhập, staging/preview và dấu chống nhập lại | XLS-01–06, AUD-01 |
| 09 | Phiên bản nghiệp vụ dài hạn, audit, job, outbox và thông báo | AUD-01, NOTIF-01, tech stack mục 5 |

REPORT-01 và DASH-01 dùng dữ liệu buổi/điểm danh, nghĩa vụ và chi tiết thu; không cần thêm bảng lưu bản in hoặc tổng dashboard. UX-01 lưu lựa chọn ngôn ngữ/giao diện trên trình duyệt, nên không có bảng tùy chọn theo tài khoản.

## Ký hiệu và phạm vi

- `PK`: khóa chính; nhiều thuộc tính có `PK` trong một bảng tạo khóa ghép. `FK`: khóa ngoại; `UQ`: duy nhất; `IDX`: chỉ mục; `?`: cho phép NULL; `SYS`: hệ thống ghi; `C`: constraint hoặc kiểm tra nghiệp vụ.
- Đường nối đi từ bảng cha tới bảng con. Đầu cha là `1` hoặc `0..1` nếu FK tùy chọn; đầu con là `0..N`, hoặc `0..1` nếu FK duy nhất. Các đường giao nhau dùng cầu vượt, không có nghĩa nối chung.
- Đường trên mỗi trang là phần quan hệ liên quan tới trang đó. FK tới actor hoặc bảng ở trang khác vẫn có trong metadata bảng; danh mục cuối tài liệu ghi đầy đủ đích tham chiếu.
- Chỉ hiển thị thuộc tính quan trọng. `phone, birth_date` hoặc `starts_on, ends_on` là cách rút gọn nhiều cột, không phải một cột SQL. Các bảng nghiệp vụ dùng timestamp, actor, lý do và `row_version` theo phạm vi; không suy rằng mọi bảng đều có cùng bộ cột hoặc cùng chính sách xóa mềm.
- `auth.users`, `auth.sessions` và `storage.objects` là lược trích các thực thể do Supabase quản lý. Không thiết kế lại schema nội bộ của nền tảng. Avatar dùng `account_profiles.avatar_path`, không tạo FK tới `storage.objects`. FK `import_batches.source_object_id` chỉ tham chiếu file nhập tạm; khi dọn file cần bỏ tham chiếu hoặc `ON DELETE SET NULL`, giữ metadata lô nhập.

## Các quyết định mô hình quan trọng

1. **Tách học sinh, hồ sơ lớp và lần tham gia.** Một học sinh có thể có nhiều hồ sơ lịch sử trong cùng lớp nhưng tối đa một hồ sơ chưa xóa. Học lại trong hồ sơ cũ thêm một khoảng tham gia; xóa rồi thêm lại tạo hồ sơ mới. Chuyển lớp cập nhật nguồn và đích trong cùng giao dịch, không chuyển tiền hoặc kết quả.
2. **Học vụ giữ định danh theo học sinh.** Điểm danh duy nhất theo học sinh/buổi; điểm và nhận xét gắn bài duy nhất theo học sinh/bài; nhận xét đợt theo học sinh/đợt. Không FK các kết quả này tới lần tham gia để tránh nhân bản khi học lại. RPC kiểm tra hợp các khoảng tham gia của đúng lớp.
3. **Lưu thời gian nghiệp vụ rõ ràng.** Dùng `Asia/Ho_Chi_Minh`; ngày vào bao gồm, ngày nghỉ loại trừ từ 00:00. Kết thúc do sự kiện giữa ngày có timestamp riêng. Khoảng đã kết thúc không tự hồi sinh khi lớp được gia hạn/khôi phục. Lịch sử khoảng lớp Mở/Đóng/Lưu trữ phục vụ chạy bù nghĩa vụ.
4. **Mẫu chữ và cấu hình bài có phiên bản.** Mỗi bài chụp riêng bộ mức chữ. Các phần/kết quả/mức chữ phải cùng bài và phiên bản; cần FK ghép hoặc kiểm tra giao dịch ngoài các FK đơn được vẽ. `current_config_id` phải thuộc đúng bài; vòng tham chiếu bài/cấu hình cần ràng buộc trì hoãn trong giao dịch tạo. Các giá trị thuộc cấu hình cũ được lưu trong lịch sử, không tiếp tục làm kết quả hiện hành.
5. **Công bố ở từng kết quả/nhận xét.** `published_at` và `published_by` đi cùng nhau. Nhận xét không phụ thuộc vào dòng điểm và có công bố độc lập. Điểm thành phần không có trạng thái công bố riêng; tổng là giá trị suy ra hoặc cache do backend quản lý. Vắng là loại kết quả riêng, không tạo điểm giả. Trước khi ép sang numeric, API/RPC phải từ chối đầu vào có hơn hai số lẻ để tránh PostgreSQL tự làm tròn.
6. **Một mô hình tháng/kỳ cho học phí.** `billing_periods` phân biệt `monthly` và `term`, khớp hình thức thu của lớp. Tháng duy nhất theo lớp/ngày đầu tháng; kỳ nhiều tháng không giao ngày, dùng cả hai đầu. Kỳ đã có nghĩa vụ khóa tên/ngày. Phiên bản mức gốc chỉ áp dụng khoản tạo sau; nghĩa vụ học phí giữ mức đã chụp, kể cả sau gỡ thu.
7. **Gộp nghĩa vụ, tách nguồn phát sinh.** `receivables` thuộc hồ sơ lớp. Học phí bắt buộc có kỳ và phiên bản mức, không có lần ngoài học phí; khoản ngoài bắt buộc có lần phát sinh, không có nguồn mức học phí. Nguồn và hồ sơ phải cùng lớp. Khóa chống trùng bao gồm cả dòng đã hủy để kích hoạt đúng khoản cũ hoặc ngăn tác vụ tự sinh lại.
8. **Điều chỉnh không cộng dồn các phiên bản.** Giá trị học phí hiện hành dùng bản điều chỉnh mới nhất; bản gỡ đóng góp 0. Các bản cũ giữ nguyên. Khoản ngoài học phí chưa thu được sửa tên/số tiền theo FEE-11 với lý do và lịch sử, không áp khóa bất biến mức gốc học phí sang mọi khoản ngoài.
9. **Giữ lựa chọn khoản ngoài theo thời gian.** Cấu hình gồm các phiên bản, lựa chọn học sinh có mốc hiệu lực và lần phát sinh riêng. Nghĩa vụ thực tế vẫn gắn hồ sơ lớp. Định kỳ theo kỳ chỉ dùng kỳ học phí có sẵn; thay cấu hình hoặc thêm đối tượng không tạo khoản hồi tố. Khóa lần phát sinh không phụ thuộc revision cấu hình.
10. **Thu đủ một khoản và giữ bản thu cũ.** Một lần thu đúng một học sinh/một lớp, có thể chứa nhiều khoản và nhiều hồ sơ lịch sử của chính học sinh/lớp đó. RPC kiểm tra sự phù hợp này, phiên bản tiền, điều chỉnh và việc thu đủ. Một khoản có tối đa một chi tiết thu chưa gỡ. Gỡ sai gắn sự kiện Admin vào chi tiết đã chọn; snapshot tiền cũ không đổi. `void_action_id` phải thuộc cùng lần thu của chi tiết. Không thêm trả góp, hoàn tiền, quá hạn hoặc khóa sổ chưa có trong đặc tả.
11. **Lịch sử dài hạn tách khỏi audit.** `business_entity_versions` là phương án lưu phiên bản trước/sau dạng JSONB, loại trừ bí mật, với khóa loại đối tượng/id/phiên bản. Đây là tham chiếu logic được RPC kiểm soát, không giả định PostgreSQL có FK đa hình. Các bảng lịch sử chuyên biệt như mức phí, điều chỉnh và gỡ thu vẫn giữ bất biến theo miền. Chỉ audit và thông báo có thời hạn 60 ngày theo đặc tả.
12. **Excel và thông báo có chống trùng riêng.** Dấu nhập thành công giữ không thời hạn theo hash và scope đã chuẩn hóa; chỉ ghi khi cả file có thay đổi và áp dụng thành công. Một lô có tối đa một audit hiện còn trong thời hạn lưu. Outbox/delivery giữ khóa sự kiện/người nhận để việc dọn thông báo không làm mất dấu chống trùng.
13. **Avatar lưu path, file nằm trong Storage.** `account_profiles.avatar_path` là `text NULL`, lưu đường dẫn tương đối trong bucket private `avatars`, ví dụ `<user_id>/<file_id>.webp`. Tên bucket dùng cấu hình ứng dụng; không lưu binary/Base64 hoặc signed URL vào hồ sơ. API kiểm tra quyền sở hữu, loại ảnh và giới hạn 5.000.000 byte trước khi cập nhật path cùng audit. File chưa được hồ sơ tham chiếu là file chờ xử lý; lỗi cập nhật phải giữ avatar cũ và dọn file mới. Đọc ảnh qua URL có thời hạn hoặc luồng tải được cấp quyền. Chi tiết tại [tech stack mục 4.5](../developer/techstack-va-chi-phi.md#45-avatar-và-luồng-lưu-file).

## Những điều ERD không tự bảo đảm

RLS, RPC/constraint, khóa và kiểm thử vẫn phải chứng minh các quy tắc: không chồng phân công/lần tham gia, không trùng phòng khi gửi đồng thời, khóa ngày đã lưu, cùng lớp/cùng cấu hình, khóa sửa công bố, không thu trùng, rollback khi audit lỗi và quyền thay đổi ngay trong phiên. Sơ đồ không phải bằng chứng các cơ chế đó đã được triển khai.

Supabase Auth cần kiểm chứng riêng theo tech stack mục 6: link đặt lại mật khẩu 5 phút/một lần dùng, thu hồi phiên, bắt đổi mật khẩu tạm và tính nguyên khối giữa Auth Admin API với audit DB. Không thêm một bảng token riêng rồi coi các yêu cầu đó đã được giải quyết.

Phụ huynh vẫn chưa xác thực: API Workers nhận link/SĐT, kiểm tra và chỉ trả dữ liệu đúng phạm vi; không tạo bảng tài khoản phụ huynh hoặc mở quyền `anon` đọc dữ liệu học sinh/tài chính. `class_portals.link_token` là tên trường thiết kế, không chứa token thực trong tài liệu; khi triển khai phải loại trường này khỏi audit và payload lịch sử không phù hợp.

## Kiểm tra và cập nhật

```powershell
python .agents/skills/drawio-skill/scripts/validate.py docs/diagrams/architecture.drawio --score
```

Đã render kiểm tra bằng draw.io Desktop 32.6.1. Đường nối có thể giao nhau ở hành lang nhưng không xuyên bảng; cầu vượt phân biệt giao hình học với quan hệ nối chung. Sau khi thay đổi bảng hoặc quan hệ, chạy kiểm tra cấu trúc và xem lại bản render.

Danh mục FK bên dưới liệt kê cả các quan hệ không lặp lại trên mọi trang. FK ghép `notifications(event_id, recipient_id)` tới `outbox_deliveries` được ghi riêng ở cuối.

## Danh mục tham chiếu

| Bảng | Trang đầy đủ | FK tới bảng/cột |
| --- | --- | --- |
| `auth.users` | core | — |
| `auth.sessions` | core | `user_id` → `auth.users` |
| `account_profiles` | core | `id` → `auth.users` |
| `students` | core | — |
| `student_contacts` | core | `student_id` → `students` |
| `subjects` | core | — |
| `grade_levels` | core | — |
| `classes` | core | `subject_id` → `subjects`; `grade_level_id` → `grade_levels` |
| `class_state_periods` | core | `class_id` → `classes`; `changed_by` → `account_profiles` |
| `student_class_profiles` | core | `student_id` → `students`; `class_id` → `classes` |
| `participation_periods` | core | `class_profile_id` → `student_class_profiles` |
| `staff_assignments` | core | `account_id` → `account_profiles`; `class_id` → `classes` |
| `locations` | schedule | — |
| `rooms` | schedule | `location_id` → `locations` |
| `weekly_schedules` | schedule | `class_id` → `classes`; `room_id` → `rooms` |
| `holidays` | schedule | — |
| `class_sessions` | schedule | `class_id` → `classes`; `weekly_schedule_id` → `weekly_schedules`; `room_id` → `rooms`; `holiday_id` → `holidays`; `makeup_for_session_id` → `class_sessions` |
| `attendance_results` | schedule | `student_id` → `students`; `session_id` → `class_sessions`; `updated_by` → `account_profiles` |
| `letter_templates` | academic | `class_id` → `classes` |
| `letter_template_versions` | academic | `template_id` → `letter_templates` |
| `letter_template_levels` | academic | `template_version_id` → `letter_template_versions` |
| `tests` | academic | `class_id` → `classes`; `current_config_id` → `test_config_versions` |
| `test_config_versions` | academic | `test_id` → `tests`; `source_template_version_id` → `letter_template_versions` |
| `test_letter_levels` | academic | `config_id` → `test_config_versions` |
| `test_components` | academic | `config_id` → `test_config_versions` |
| `test_results` | academic | `student_id` → `students`; `test_id` → `tests`; `config_id` → `test_config_versions`; `letter_level_id` → `test_letter_levels`; `published_by` → `account_profiles` |
| `component_results` | academic | `result_id` → `test_results`; `component_id` → `test_components` |
| `test_comments` | comments | `student_id` → `students`; `test_id` → `tests`; `published_by` → `account_profiles` |
| `comment_rounds` | comments | `class_id` → `classes` |
| `round_comments` | comments | `student_id` → `students`; `round_id` → `comment_rounds`; `published_by` → `account_profiles` |
| `class_portals` | comments | `class_id` → `classes` |
| `class_billing_settings` | tuition | `class_id` → `classes`; `configured_by` → `account_profiles` |
| `billing_periods` | tuition | `class_id` → `class_billing_settings.class_id` |
| `tuition_rate_versions` | tuition | `billing_period_id` → `billing_periods`; `changed_by` → `account_profiles` |
| `receivables` | tuition | `class_profile_id` → `student_class_profiles`; `billing_period_id` → `billing_periods`; `rate_version_id` → `tuition_rate_versions`; `extra_occurrence_id` → `extra_charge_occurrences` |
| `tuition_adjustment_versions` | tuition | `receivable_id` → `receivables`; `changed_by` → `account_profiles` |
| `extra_charge_rules` | extras | `class_id` → `classes` |
| `extra_charge_rule_versions` | extras | `rule_id` → `extra_charge_rules` |
| `extra_charge_targets` | extras | `rule_id` → `extra_charge_rules`; `student_id` → `students` |
| `extra_charge_occurrences` | extras | `rule_id` → `extra_charge_rules`; `rule_version_id` → `extra_charge_rule_versions`; `billing_period_id` → `billing_periods` |
| `payments` | payments | `student_id` → `students`; `class_id` → `classes`; `collected_by` → `account_profiles` |
| `payment_void_actions` | payments | `payment_id` → `payments`; `voided_by` → `account_profiles` |
| `payment_lines` | payments | `payment_id` → `payments`; `receivable_id` → `receivables`; `adjustment_version_id` → `tuition_adjustment_versions`; `void_action_id` → `payment_void_actions` |
| `storage.objects` | imports | — |
| `import_batches` | imports | `uploaded_by` → `account_profiles`; `source_object_id` → `storage.objects`; `class_id` → `classes`; `test_id` → `tests`; `round_id` → `comment_rounds` |
| `import_staging_rows` | imports | `import_id` → `import_batches` |
| `import_success_fingerprints` | imports | `import_id` → `import_batches` |
| `business_entity_versions` | operations | `changed_by` → `account_profiles` |
| `background_jobs` | operations | `outbox_event_id` → `outbox_events` |
| `job_attempts` | operations | `job_id` → `background_jobs` |
| `outbox_events` | operations | `class_id` → `classes` |
| `outbox_deliveries` | operations | `event_id` → `outbox_events`; `recipient_id` → `account_profiles` |
| `notifications` | operations | `event_id` → `outbox_events`; `recipient_id` → `account_profiles` |
| `audit_events` | operations | `actor_id` → `account_profiles`; `job_id` → `background_jobs`; `import_id` → `import_batches` |

FK ghép bổ sung: `notifications(event_id, recipient_id)` → `outbox_deliveries(event_id, recipient_id)`; duy nhất theo cặp để mỗi bản ghi giao nhận có tối đa một thông báo hiện hữu.
