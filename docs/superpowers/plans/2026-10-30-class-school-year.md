# Class School Year Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in the current checkout, sequentially; no worktrees or parallel writes.

**Goal:** Thêm năm học tùy chọn và lọc lớp theo CLASS-03.

**Architecture:** Nullable integer `app.classes.school_year_start`; RPC đảm bảo validation, version, history và audit nguyên khối. Contract/API đưa trường và bộ lọc tới Vue, không thay quyền hay ngày lớp.

**Tech Stack:** PostgreSQL/Supabase, Hono/TypeScript, Zod, Vue/Bootstrap.

**Spec:** [Thiết kế đã duyệt](../specs/2026-10-30-class-school-year-design.md).

## Global Constraints

- Năm bắt đầu 1000–9998 hoặc NULL, hiển thị hai năm liên tiếp, không ràng buộc ngày lớp.
- Lớp cũ giữ NULL; giữ quyền hiện hành, audit/history, version, dữ liệu và diff không liên quan.
- Tham chiếu live Metis và source local trước khi sửa UI; không thêm dependency/runtime từ template.
- Không reset dev, không commit/push/deploy.

## Review Focus

- Bỏ filter khác với lọc NULL; query không hợp lệ phải bị từ chối.
- Lọc trước phân trang, option lấy toàn phạm vi được phép xem, không lộ lớp khác.
- Thay năm là thay đổi cần version và audit; lỗi audit rollback cả trường và history.
- Payload cũ không được vô tình xóa năm khi sửa lớp; duy trì tương thích RPC hiện có.
- UI đổi filter về trang 1, không nhận phản hồi cũ ghi đè filter mới.

## Task 1 — Database và API

Files: migration mới `supabase/migrations/20261030130000_class_school_year.sql`,
`supabase/tests/database/class_school_year.test.sql`, `packages/contracts/src/classes.ts`,
`packages/contracts/src/classes.test.ts`, `apps/api/src/modules/classes/routes.ts`,
`apps/api/src/generated/database.types.ts`, `apps/api/tests/integration/classes.test.ts`.

Interface: `schoolYearStart: number | null`, query `schoolYear=all|none|YYYY`,
response `schoolYears: number[]` trong ClassPage (các năm trong toàn phạm vi được phép đọc).

- [x] Viết/chạy test contract và DB thất bại: giá trị biên, all/none/năm, pagination, quyền, version và rollback audit.
- [x] Thêm migration tiến, snapshot/DTO, RPC create/update/list và option được scope theo quyền; cập nhật contract/routes.
- [x] Áp dụng local test có kiểm tra danh tính; sinh DB types; chạy DB và API integration.

## Task 2 — UI, tài liệu và nghiệm thu

Files: `apps/web/src/features/classes/{ClassesPage,ClassFormDialog,ClassDetailPage}.vue`,
`apps/web/src/locales/{vi,en}.ts`, `tests/e2e/classes.spec.ts`, `docs/developer/plans.md`,
`docs/developer/Implementation-plan.md`, decision record và ERD nếu có thể sửa có phạm vi.

- [x] Xem/chụp live Metis, đọc source local cho form/select/table; ghi kích thước.
- [x] Thêm trường năm bắt đầu, preview nhãn năm học, cột, detail và filter; giữ layout hiện hành.
- [x] E2E tạo/đổi/bỏ/lọc năm học ở desktop/mobile; chụp Việt/sáng, Anh/tối.
- [x] Chạy unit, DB, integration, E2E, lint, typecheck, build, artifact và diff checks phù hợp.
- [x] Cập nhật CLASS-03, kế hoạch và bằng chứng thực tế; áp dụng migration tiến local dev nếu sẵn sàng; báo gate còn mở.
