# Danh mục và lớp — Sắp xếp tên và bộ lọc

Yêu cầu trực tiếp và kiểm chứng local ngày **30/10/2026**, theo CAT-01, CLASS-01/03, SCHED-03/05 và UX-01. Quy tắc được bổ sung trong `plans.md` theo yêu cầu người dùng.

## Hành vi

- Môn, khối, địa điểm, phòng và lớp mặc định so số ký tự của tên hiển thị tăng dần, rồi khóa tên chuẩn hóa theo từ điển (`COLLATE "C"`), tên hiển thị và ID để ổn định. Phòng không nhóm địa điểm trước tên; bản lưu trữ cũng tuân theo cùng thứ tự khi được phép liệt kê.
- `GET /v1/classes` thêm `gradeId`, `subjectId`, `status`, `staffId`; kết hợp với tìm tên/năm học trước đếm và phân trang. Trạng thái `all|open|closed|upcoming|running|ended`; nhóm Mở/Đóng dùng trạng thái quản trị, nhóm thời gian dùng ngày `Asia/Ho_Chi_Minh`.
- Nhân sự lọc theo phân công giáo viên/trợ giảng đang hiệu lực, cùng điều kiện với cột nhân sự hiện tại. Phân công tương lai hoặc đã kết thúc không khớp.
- `filterOptions` có `grades`, `subjects`, `staff`, chỉ từ toàn bộ lớp hiện được đọc (cùng trạng thái xóa); không phụ thuộc tìm kiếm/bộ lọc/trang. Giữ danh mục đã lưu trữ còn được lớp tham chiếu. Không gọi endpoint quản trị tài khoản hoặc mở quyền mới để lấy options.
- UI giữ bộ lọc năm học, thêm bốn dropdown VI/EN và tự quay về trang 1 khi đổi bộ lọc. Phản hồi cũ bị bỏ qua; đổi workspace xóa bộ lọc và dữ liệu cũ.

Migration `20261030140000_class_list_filters.sql` chỉ thay RPC đọc, không đổi bảng/cột hoặc dữ liệu nghiệp vụ. Đã áp dụng tiến trên **mledu-test** và **mledu-dev**. Dev giữ nguyên **29 lớp, 15 danh mục** trước/sau; không reset dev, không chạy staging/production. Types API sinh lại từ test DB. Tài liệu `schema.md` trước đó đối chiếu 16 migration; migration thứ 17 này không đổi schema bảng được mô tả.

## Kiểm chứng thực tế

| Lệnh | Kết quả |
| --- | --- |
| `npm run test:db` | **545/545** pgTAP, gồm 19 assertions mới |
| `npm run test:unit` | **41/41**: contracts 18, API 17, web 6 |
| `npm run test:integration` | **54/54**, Worker + Supabase local thật |
| `npm run test:e2e -- tests/e2e/classes.spec.ts tests/e2e/catalogs.spec.ts --workers=2` | **12/12**, desktop/mobile, lọc kết hợp/kết quả rỗng và VI/EN/sáng/tối |
| `npm run lint`, `npm run typecheck`, `npm run format:check`, `git diff --check` | Đạt |
| `npm run build`, `npm run check:artifacts` | Đạt khi tạm chuyển `template/` ra khỏi đường dẫn tham chiếu; đã khôi phục trong `finally`; Worker dry-run |

Đã thấy test contracts fail do bỏ qua filters và DB fail vì thứ tự cũ/chưa có chữ ký RPC mới trước triển khai. E2E ban đầu fail do backend chưa có metadata mới. Review chỉ đọc phát hiện fixture dùng ngày UTC; đã sửa sang ngày Việt Nam và chạy lại toàn bộ DB đạt. Lần DB suite đầu chạy cùng integration bị test API khớp prefix chung; đã tách prefix và chạy tuần tự đạt. Không có finding còn mở sau review.

## Metis và giới hạn

Đã mở live Metis **Users** trong Edge, thử dropdown và đọc computed styles của thanh tìm kiếm/select. Đã đọc local `template/metis-v1.0.0/src-modern/users.html` và license MIT; xem ảnh tham chiếu desktop/mobile sẵn có trong `tmp/class-school-year/`.

API chụp live tab mới timeout (`Page.captureScreenshot`), native capture cũng timeout; không khẳng định có ảnh live mới. UI dùng card, input group và Bootstrap select hiện có; control cỡ thường của MLedu giữ thao tác mobile, grid ba cột trên desktop và một cột trên điện thoại thay toolbar cố định của demo.

Đã chụp/xem MLedu desktop **1280×720** và mobile **412×839** (DPR 2.625), Việt/sáng và Anh/tối; không tràn ngang toàn trang, bảng cuộn trong card. Ảnh kết quả giữ trong `tmp/class-list-filters/`, ảnh đầy đủ từ E2E trong `test-results/classes-class-filters-comb-*/`. Không tuyên bố pixel-perfect, không thêm dependency/runtime import từ template.

Chưa commit/push/deploy; chưa có CI GitHub hoặc nghiệm thu hosted cho thay đổi này. Bước tiếp theo duy nhất là kiểm chứng CI/hosted khi có lần phát hành được cho phép; các gate Auth/audit và giai đoạn khác giữ nguyên.
