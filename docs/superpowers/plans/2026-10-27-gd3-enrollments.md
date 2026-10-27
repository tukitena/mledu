# GĐ3 — Hồ sơ lớp và lần tham gia

> Thực hiện bằng `superpowers:executing-plans`, tuần tự trong checkout hiện tại theo CLAUDE.md. Không tạo branch/worktree; giữ các thay đổi đã có.

**Goal:** Hoàn thiện STU-03/CLASS-04 xuyên SQL, API, contracts và UI; nối ảnh hưởng xóa học sinh và nền vòng đời lớp.

**Architecture:** Vue gọi Hono; mỗi lệnh gọi một RPC có kiểm tra quyền, version, lịch sử và audit trong transaction. Tiếp tục migration enrollments đang có. Các hook lịch/phí giữ trong transaction cho GĐ4/6; chưa nghiệm thu toàn bộ CLASS-05.

**Tech Stack:** Vue 3, TypeScript, Hono, PostgreSQL/Supabase, Zod, Bootstrap.

**Spec:** `docs/developer/plans.md` STU-01–03, CLASS-03–05; `docs/developer/Implementation-plan.md` GĐ3.

## Constraints và review

- Asia/Ho_Chi_Minh; ngày nghỉ loại trừ 00:00, sự kiện xóa cắt tại thời điểm thực tế.
- Ngày vào bất biến, ngày nghỉ ghi một lần; không chồng lần tham gia trong cùng hồ sơ.
- Học lại dùng hồ sơ cũ; xóa/thêm lại tạo hồ sơ mới, không tham gia trước lần xóa cũ.
- User chỉ đọc lớp có phân công hiện hành; mọi lệnh thay đổi dành cho Admin/Receptionist.
- Audit lỗi phải rollback toàn lệnh, kể cả hai phía chuyển lớp.
- Kiểm tra gia hạn không hồi sinh khoảng đã kết thúc, đồng thời nhập học, phiên/quyền bị thu hồi và trạng thái hiển thị.
- UI dùng bảng/tab/modal Metis đã xem trực tiếp; Việt/Anh, sáng/tối, desktop/mobile.

## Task 1: SQL và hợp đồng API

Files: migration `20261027140000_enrollments.sql`, migration bổ sung nếu sửa phần đã áp dụng; `supabase/tests/database/participation_periods.test.sql`; `packages/contracts/src/enrollments.ts`, `common.ts`; `apps/api/src/modules/enrollments/routes.ts`; router lớp/học sinh/app; database types.

- [x] Kiểm tra SQL đã có bằng pgTAP, bổ sung regression cho biên thời gian/gia hạn và audit rollback cả hai phía chuyển lớp.
- [x] Viết `apps/api/tests/integration/class-transfer.test.ts`: nhập học, học lại, xóa/thêm lại, khóa ngày, phân quyền, chuyển thành công/lỗi đích và đồng thời.
- [x] Chạy thấy test đỏ vì endpoint chưa có; thêm DTO/schema/routes với một RPC mỗi lệnh.
- [x] Chạy pgTAP và test tích hợp đạt; kiểm tra typecheck.

Interfaces: ClassStudent chứa các Participation; enroll/leave/note/cancel/delete/transfer trả ClassStudent; preview xóa trả số lần đang học/tương lai; vòng đời lớp trả ClassSummary.

## Task 2: UI tham gia và lịch sử

Files: `apps/web/src/features/classes/EnrollmentsPanel.vue`, `ClassDetailPage.vue`, dialog vòng đời; học sinh; locales; `tests/e2e/enrollments.spec.ts`.

- [x] Xem/chụp Metis Users và modal; đối chiếu template local.
- [x] Viết và chạy e2e đỏ cho đăng ký → nghỉ → học lại/chuyển → xem lịch sử.
- [x] Thêm tab học sinh, tìm/chọn học sinh, các lệnh có xác nhận/lý do; giữ ngày đã khóa; hiển thị sự kiện kết thúc và lớp đóng.
- [x] Thêm preview xóa học sinh và đóng/xóa lớp; khôi phục về đóng.
- [x] Kiểm thử desktop/mobile và xem ảnh sáng/tối, Việt/Anh.

## Task 3: Xác minh và ghi nhận

- [x] Chạy lint, format, typecheck, unit, DB, integration, e2e, build và check artifacts phù hợp.
- [x] Review độc lập chỉ đọc; sửa lỗi quan trọng bằng test hồi quy.
- [x] Cập nhật quyết định GĐ3 và checklist theo bằng chứng; ghi rõ CI/hosted, lịch/phí chưa nghiệm thu.

## Execution ledger

- Baseline: `0d8ebb3`; đã có thay đổi database.types.ts, migration enrollments và pgTAP chưa commit.
- Ban đầu DB local đã áp dụng migration 140000. pgTAP chạy 60 test nhưng plan 56; một expectation ended/cancelled sai do thêm và xóa cùng timestamp transaction. Đã sửa theo khoảng thực tế, giữ kiểm thử kết thúc giữa ngày riêng; suite hiện có 72 test đạt.
- Ruling: thực hiện trực tiếp theo workflow đã duyệt ở CLAUDE.md, không mở thêm vòng phê duyệt thiết kế hoặc tạo worktree.
- Đã áp dụng thêm migration 140100 (khóa lịch sử/mốc xóa) và 140200 (thứ tự khóa). Không reset DB.
- Review chỉ đọc nêu lỗi Học lại kế thừa ngày nghỉ cũ và deadlock khi xóa/sửa đồng thời; đã tái hiện đỏ rồi sửa xanh bằng E2E và hai kết nối PostgreSQL. Thêm case chuyển hai chiều cùng học sinh.
- Theo trao đổi với người dùng, gộp bản dịch về `vi.ts`/`en.ts`; không giữ file locale riêng cho enrollments.
- Hoàn tất local: lint/format/typecheck, 34 unit, 350 pgTAP, 1 kiểm thử khóa DB, 47 integration, 32 E2E (`--workers=2`), build khi thiếu đường dẫn `template/`, artifacts. Đã khôi phục thư mục tham chiếu.
- Có một timeout test phân công mobile cũ ở lần E2E số worker mặc định; lần toàn bộ với 2 worker đạt. Giới hạn visual, CI/hosted và lịch/phí được ghi tại [quyết định GĐ3](../../developer/decisions/gd3-enrollments.md).
