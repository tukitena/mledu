# Chuẩn hóa ngày trên UI — 30/10/2026

Yêu cầu người dùng: ngày hiển thị và nhập theo **dd-mm-yyyy** (đã xác nhận năm 4 chữ số); tên tháng theo ngôn ngữ ứng dụng, độc lập locale trình duyệt. Phạm vi UX-01 trên toàn bộ frontend hiện có. ISO trong API/DB, múi giờ nghiệp vụ và nhãn năm học không đổi.

Thực hiện tuần tự trong checkout hiện tại:

1. Bổ sung kiểm thử formatter ngày/ngày giờ, parser ngày nhập và năm nhuận; chạy để xác nhận lỗi cũ.
2. Formatter dùng chung; DateInput dùng Bootstrap/Metis Forms và mini-calendar, hỗ trợ nhập bàn phím, lịch Việt/Anh, min/max, rỗng/required/disabled, popover trong modal. Mode tháng dùng tên tháng theo app locale.
3. Áp dụng cho toàn bộ ô ngày/tháng và phần ngày hiển thị (lịch, preview, nghỉ lễ, chuyên cần, cảnh báo, lịch sử); cập nhật UX-01 và các E2E tương ứng. Không thêm dependency.
4. Kiểm tra lint, format, typecheck, unit, E2E, build/artifacts; chụp và so sánh desktop/mobile, Việt/Anh, sáng/tối với trình duyệt tiếng Anh. Rà soát cuối độc lập, chỉ đọc.

Điểm cần kiểm chứng: ngày không tồn tại không được gửi; xóa ngày tùy chọn thành NULL; không giữ giá trị hợp lệ cũ khi đang nhập sai; form novalidate vẫn chặn ngày lỗi; min/max và ngày disabled; lịch không bị cắt trong modal/mobile; đổi ngôn ngữ không đổi ISO hoặc ngày nghiệp vụ.

## Kết quả local

- Hoàn thành formatter/parser và DateInput trên toàn bộ ô ngày/tháng hiện có; lịch, preview, lễ, chuyên cần, cảnh báo và lịch sử dùng formatter chung. Không đổi API/DB hoặc nhãn năm học. UX-01 đã ghi nhận yêu cầu được xác nhận.
- Bổ sung tiếp theo theo yêu cầu người dùng: cột thao tác buổi học dùng RowActionMenu `…` giống các bảng khác; giữ nguyên điều kiện quyền/trạng thái/thời điểm và chế độ chỉ đọc điểm danh.
- Chỉnh tiếp theo phản hồi tiêu đề bảng: bảng buổi học dùng `data-table` chung với lớp/học sinh (chữ hoa, màu/độ đậm, nền, đường kẻ và khoảng cách), có `scope="col"`, cột Thao tác căn phải. Đối chiếu Metis Users live/local; 2 UI desktop/mobile, format/lint, typecheck và build frontend đạt; ảnh tại `tmp/schedule-header-qa/`.
- Unit frontend: **8 đạt**; contracts: **18 đạt**. `npm run test:unit` toàn workspace vẫn lỗi khởi động API Workers với `cloudflare:test-internal`, chưa coi bộ API unit là đạt.
- `npm run test:ui`: **12 đạt** desktop/mobile. Sau bổ sung menu/chỉnh vị trí popup, chạy lại các case bị ảnh hưởng: ngày **2 đạt**, menu/tháng **2 đạt**. Trình duyệt locale tiếng Anh, UI Việt/Anh, sáng/tối; kiểm tra ngày sai, năm nhuận, ISO payload, xóa thành NULL, min/max, Escape trong modal, popup tháng sáu hàng, menu không thay kích thước bảng.
- E2E lớp, tham gia, lịch và quyền sửa học sinh: **16 case đạt qua các lượt kiểm chứng**. Lỗi đổi ngày áp dụng chưa cập nhật lịch tuần ngay đã được sửa; chạy lại toàn bộ scheduling **4 đạt**, rồi **4 đạt** sau đổi menu điểm danh.
- Format, lint, typecheck, build web + API dry-run, artifacts và diff check đạt. Wrangler dry-run vẫn báo không ghi được log ngoài workspace (EPERM), nhưng bundling/dry-run kết thúc thành công. Không deploy/push hoặc thay CI/hosted gate.
- Đã xem Metis Forms, Calendar và Users live, chụp trạng thái menu Users đóng/mở; đối chiếu source mini-calendar và dropdown tại template local. Ảnh ứng dụng ở `tmp/date-ui-qa/` và `tmp/date-ui-menu-qa/` (không đưa vào production assets). Rà soát mã độc lập chỉ đọc không còn phát hiện cần sửa.
