# Quyền sửa học sinh theo phân công

> Thực hiện bằng `superpowers:executing-plans`, tuần tự trên checkout hiện tại; không tạo branch/worktree hoặc commit.

**Goal:** Đồng bộ chức năng đã có với thay đổi 28/10/2026 của STU-04/STU-03.

**Architecture:** Giữ Vue → Hono → RPC. Tách quyền sửa khỏi helper quản trị; RPC kiểm tra phiên, phân công hiện hành, hồ sơ/lớp chưa xóa, version và audit trong transaction. DTO trả quyền sửa để UI hiển thị thao tác đúng phạm vi; backend luôn kiểm tra lại khi ghi.

**Tech Stack:** Vue 3, TypeScript, Hono, PostgreSQL/Supabase, pgTAP, Vitest, Playwright hiện có.

**Spec:** `docs/developer/plans.md` STU-04, STU-03, STU-01/02, CLASS-04; `techstack.md` §4.2; `Implementation-plan.md` GĐ3, quyết định 28/10/2026.

## Ràng buộc và lựa chọn

- Chỉ cập nhật phạm vi đã triển khai. XLS-01/02, IELTS/template, DOCX/biên nhận chưa có module, giữ ở các giai đoạn sau.
- Giáo viên và trợ giảng có cùng quyền sửa: hồ sơ tổng khi có ít nhất một quan hệ lớp hợp lệ; ghi chú/ngày nghỉ chỉ trong chính lớp được phân công.
- Hồ sơ tổng dùng chung; UI phải thông báo thay đổi phản ánh ở mọi lớp. Không tạo bản sao theo lớp.
- Giữ khóa ngày, chống trùng, version, lịch sử và audit. Không mở quyền tạo/thêm/xóa/hủy/khôi phục/chuyển lớp/học lại.
- Bổ sung migration mới; không sửa lịch sử migration. Giữ thứ tự khóa lớp → học sinh → hồ sơ → lần tham gia, kiểm tra phân công sau khóa.
- Giữ form/menu Metis hiện có, xem live và chụp reference trước thay đổi UI; không đổi phong cách hoặc thêm dependency.
- Test trên `mledu-test` cô lập; không reset dữ liệu development/hosted.

## Thực hiện

### 1. Quyền RPC và hợp đồng

- [x] Viết test DB/API cho giáo viên và trợ giảng, ngoài lớp, hồ sơ nhiều lớp, lưu trữ, thu hồi/hết phân công, phiên cũ, quyền quản trị bị chặn, khóa ngày, version đồng thời, chống trùng và rollback audit. Chạy để thấy lỗi do quyền cũ.
- [x] Thêm `supabase/migrations/20261028100000_student_edit_permissions.sql`: quyền sửa riêng, DTO `canEdit`, cập nhật ba RPC sửa; giữ helper quản trị.
- [x] Cập nhật contracts `students.ts`/`enrollments.ts`, kiểm chứng schema/API. API routes hiện đã chuyển tiếp JWT và gọi đúng một RPC; chỉ sửa nếu cần.

### 2. UI và nghiệm thu

- [x] Xem/chụp Metis Users/modal; tham khảo nguồn local cho form/menu/hint.
- [x] `StudentsPage.vue`: hiện Sửa theo `canEdit`, giữ quản trị theo workspace, thêm giải thích hồ sơ dùng chung Việt/Anh.
- [x] `EnrollmentsPanel.vue`: tách note/leave theo `canEdit` khỏi thao tác quản trị, giữ khóa và trạng thái lưu trữ.
- [x] E2E desktop/mobile cho hai vai trò, form/menu, khóa ngày và thông báo; chụp và xem ảnh.
- [x] Chạy DB, integration, concurrency, unit, lint, typecheck, build/artifact và E2E phù hợp; review độc lập chỉ đọc; ghi bằng chứng và gate chưa thử.

## Tiến độ / quyết định khi thực hiện

- Khởi đầu: diff chỉ gồm ba tài liệu yêu cầu. CodeGraph đã kiểm tra đường API/DTO/UI; SQL không được truy vấn graph trả về nên đọc migration trực tiếp.
- Phạm vi đã rõ trong diff và yêu cầu người dùng; thực hiện ngay theo workflow dự án, không mở vòng duyệt thiết kế mới.

- Hoàn tất local 29/10/2026: 417 pgTAP, 49 integration, 7 concurrency, 36 E2E, 34 unit; lint/typecheck/format/build/artifacts đạt. Review độc lập không có lỗi chặn. Chi tiết ở docs/developer/decisions/student-edit-permissions.md.
