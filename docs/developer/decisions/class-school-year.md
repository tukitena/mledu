# CLASS-03 — Năm học tùy chọn của lớp

Ngày triển khai và kiểm chứng local: **30/10/2026**.

Người dùng đã chọn năm học chuẩn hai năm liên tiếp, không ràng buộc ngày lớp,
và duyệt [thiết kế](../../superpowers/specs/2026-10-30-class-school-year-design.md).
Yêu cầu và nghiệm thu được bổ sung trực tiếp tại CLASS-03 trong `plans.md`.

## Hành vi và dữ liệu

- `app.classes.school_year_start` là integer 1000–9998 hoặc NULL. Ví dụ 2026
  hiển thị `2026–2027`; NULL là **Không thuộc năm học**. Migration không gán năm
  từ ngày lớp, không sửa dữ liệu nghiệp vụ/lịch/phân công/học phí hiện có.
- Admin/Receptionist tạo, đổi hoặc bỏ năm học qua form lớp hiện có. Bảng và
  chi tiết lớp hiển thị cùng giá trị; có Việt/Anh và hỗ trợ theme hiện hành.
- Query `schoolYear=all|none|YYYY` lọc cùng tìm tên trước khi đếm/phân trang.
  `schoolYears` lấy từ toàn phạm vi lớp được đọc và cùng trạng thái xóa, độc lập
  tìm tên/năm/trang. User chỉ thấy lớp và các năm có phân công hiệu lực.
- Đổi filter về trang 1; chỉ phản hồi request mới nhất được cập nhật UI. Giữ
  năm đang chọn trong select kể cả khi lớp cuối cùng của năm đó vừa chuyển năm.
- API/SQL kiểm tra lại dữ liệu/quyền và optimistic version. Snapshot lịch sử
  và audit ghi năm học trong cùng transaction. Lỗi audit rollback cả dữ liệu,
  version và lịch sử. Payload cũ bỏ trường giữ nguyên năm khi sửa, NULL rõ ràng
  mới bỏ năm. Overload RPC cũ khóa lớp rồi chuyển tiếp tới lệnh mới.
- Chặn `validity.badInput` của number input: gõ `e`/số mũ chưa hoàn chỉnh có thể
  trả chuỗi rỗng nhưng không được hiểu là thao tác bỏ năm học.

Migration: `20261030130000_class_school_year.sql`. Đã đối chiếu lịch sử migration
rồi áp dụng tiến thành công trên **mledu-test** và **mledu-dev**, không reset/seed
lại dev. Dev có 0 lớp trước/sau; bảo toàn các lớp có sẵn được kiểm chứng bằng
fixture/test DB và việc cột mới nullable không có backfill. DB API types sinh
lại từ mledu-test. Chưa áp dụng staging/production.

ERD giữ bố cục/ID trước đó; thêm một hàng nullable vào bảng lớp trang 01 và
đồng bộ metadata lớp trên 9 trang. Đã render/xem bảng lớp, chạy validate:
**0 lỗi, 28 cảnh báo giao đường có sẵn; 0 xuyên bảng, 0 chồng bảng**.

## Bằng chứng

| Lệnh | Kết quả thực tế |
| --- | --- |
| `npm run test:db` | 526/526 pgTAP, gồm 27 test năm học |
| `npm run test:integration` | 53/53, Worker + Supabase test thật |
| `npm run test:db:concurrency` | 12/12, khóa/đặt phòng/quyền sau khi chờ khóa |
| `npm run test:unit` | 40/40: contracts 17, API 17, web 6 (ngoài sandbox) |
| `npm run test:e2e -- --workers=2` | 42/42 desktop/mobile, gồm tạo/lọc/đổi/bỏ năm học và badInput |
| `npm run lint`, `npm run typecheck`, `npm run format:check`, `git diff --check` | Đạt |
| `npm run build`, `npm run check:artifacts` | Đạt khi tạm bỏ `template/` khỏi đường dẫn tham chiếu, đã khôi phục; Worker dry-run, artifact sạch |

Đã thấy test fail trước triển khai vì thiếu trường/filter và UI; review chỉ đọc
phát hiện badInput, đã tái hiện E2E fail rồi sửa và chạy lại xanh. Các lỗi test
ban đầu (tên cột audit trong test, thông báo session_invalid và menu ngôn ngữ
mobile) đã sửa theo schema/hành vi thực. Unit API trong sandbox từng không khởi
động `cloudflare:test-internal`; chạy ngoài sandbox đạt, không đổi dependency
hoặc cấu hình để xử lý giới hạn môi trường.

## Tham chiếu UI và giới hạn

Đã mở live Metis **Users** và **Forms** trong Chromium riêng, đọc source local
`src-modern/users.html`, `forms.html` và license MIT trước sửa UI. Chụp và xem ảnh
1280×720, 412×839; đo form/select 14px, line-height 21px, padding 7px/12px, radius
6px; select nhỏ trong Users 12.25px, cao 28.375px. Dùng form control cỡ thường
của MLedu/Metis cho trường và filter, bảng responsive/card hiện có. Filter mobile
xếp dòng để giữ thao tác thuận tiện, khác toolbar cố định của demo Users.

Đã xem ảnh MLedu ở cùng CSS viewport desktop 1280×720 và Pixel 7 412×839
(device scale 2.625), Việt/sáng và Anh/tối; form/modal, filter và bảng đều hoạt
động, không tràn ngang toàn trang. Tham chiếu/ảnh đo trong
`tmp/class-school-year/`; ảnh E2E trong `test-results/classes-optional-school-*/`.
Không tuyên bố pixel-perfect; không thêm runtime import từ template.

Chưa có CI GitHub hoặc nghiệm thu hosted cho thay đổi chưa commit này. Các gate
Auth/audit liên hệ thống và giai đoạn khác giữ nguyên. Không commit/push/deploy.
Bước tiếp theo duy nhất: kiểm chứng CI/hosted của thay đổi này khi có lần phát
hành được cho phép.
