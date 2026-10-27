# Chốt GĐ 0 và bàn giao sang GĐ 1

Ngày: **26/10/2026**, múi giờ Asia/Ho_Chi_Minh.

**Trạng thái: đóng đợt thử nghiệm GĐ 0 theo quyết định của người dùng; chuyển
giai đoạn hiện hành sang GĐ 1.** Đây là quyết định chuyển công việc, không phải
xác nhận toàn bộ tiêu chí kỹ thuật/nghiệp vụ đã đạt. Không thay đổi `plans.md`.

## Kết quả được giữ lại

- Tích hợp native ban/unban, kiểm tra quyền/phiên tại request và token hook:
  các test tích hợp local đạt.
- Thử nghiệm Auth/audit nguyên khối cho ban/unban và Admin cấp mật khẩu tạm:
  chứng minh được commit/rollback cùng mật khẩu, phiên và trạng thái ứng dụng.
- Nhóm tích hợp: **26/26 đạt**. Toàn bộ test nhanh: **35/38 đạt**, ba test
  recovery native còn thất bại; không bỏ hoặc sửa kỳ vọng các test này.
- Link recovery hết hạn sau 301 giây thực đã được đo ở vòng trước.
- Giữ mã nguồn, migration, test, lockfile và các biên bản để chạy lại/đối chiếu;
  schema `spike_private` vẫn là thử nghiệm, chưa phải schema production.

Bằng chứng tổng hợp đã lưu tại [gd0-auth-results.json](evidence/gd0-auth-results.json).
Chi tiết: [Auth/audit](auth-audit.md), [transaction Auth/audit](auth-audit-transaction.md).
Các số liệu là kết quả đã ghi nhận trước khi chốt, không phải tuyên bố vừa chạy
lại toàn bộ test trong lần dọn dẹp này.

## Công việc chuyển tiếp

| Mã | Công việc cần làm | Điều kiện phải đạt |
| --- | --- | --- |
| G1-01 | Xác minh recovery đồng thời trên phiên bản/luồng hosted sẽ dùng, gồm PKCE; xác định và kiểm chứng cách xử lý | Trước nghiệm thu Auth GĐ 2; một link chỉ hoàn tất một lần khi dùng đồng thời |
| G1-02 | Thử avatar private, kiểm tra file thật, lỗi audit và đổi đồng thời | Trước chốt triển khai avatar GĐ 2; chưa có bằng chứng đạt từ GĐ 0 |
| G1-03 | ~~Benchmark Excel gần giới hạn dung lượng, 5.000 dòng và bài 50 thành phần~~ | **Đóng 27/10/2026, không đo.** Đọc file tại trình duyệt bằng SheetJS CE 0.20.3, chấp nhận độ trễ; không còn là điều kiện chặn. Kiểm thử chức năng file 5.000 dòng vẫn thuộc gate GĐ 8 (techstack §5.1) |
| G1-04 | Đối chiếu ERD với 60 chức năng, khóa học vụ/tài chính và lịch sử | Trước chốt migration nghiệp vụ chính thức; sơ đồ hiện có là đầu vào review |
| G1-05 | Đưa thiết kế Auth/audit đã thử vào thiết kế chính thức; bổ sung self-service, reset và các phần AUTH còn thiếu | Trước nghiệm thu nhóm Auth; không mở route production từ prototype |

Cập nhật 27/10/2026 ([biên bản GĐ 2](gd2-auth-profile.md)): G1-01 và G1-02 đạt trên
local (reset một lần ở tầng MLedu; avatar đủ ca lỗi), **chưa thử hosted** nên vẫn mở;
G1-05 đã đưa thiết kế vào migration chính thức.

GĐ 1 được bắt đầu với workspace, Vue/Worker local, contracts, nền DB/RLS/audit/
outbox và CI theo [kế hoạch](../Implementation-plan.md). Các mục chuyển tiếp được
theo dõi cùng giai đoạn; build/typecheck hoặc nhóm test tích hợp xanh không thay
cho nghiệm thu Auth, avatar và Excel. Chưa có triển khai production/dữ liệu thật.

## Dọn file tạm

Đã tổng hợp số liệu cần giữ vào hồ sơ. Dọn `tmp/`, gồm log các lần chạy, báo cáo
JSON sinh lại được, cấu hình kết nối/khóa local và preview/script dựng ERD tạm.
Sơ đồ chính thức ở `docs/diagrams/` và test nguồn được giữ để tái tạo kết quả.

Sau dọn, chạy `npm run local:auth` trước khi chạy test hoặc API. Lệnh này tạo lại
`tmp/` và cấu hình local; không cần khôi phục các file đã xóa. Không reset Docker,
database hay xóa dependency trong bước chốt này.
