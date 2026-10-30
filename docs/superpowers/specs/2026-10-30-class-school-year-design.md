# Năm học tùy chọn cho lớp — CLASS-03

Ngày: 30/10/2026.

## Yêu cầu đã xác nhận

Lớp có thể thuộc một năm học chuẩn dạng `2026–2027` hoặc không thuộc năm học.
Năm học không ràng buộc ngày mở/kết thúc lớp. Cập nhật tài liệu, database và UI;
lọc danh sách lớp theo năm học.

## Phương án

Đã cân nhắc giá trị năm chuẩn và danh mục do Admin quản lý. Người dùng chọn giá
trị chuẩn, không cần CRUD danh mục. Đề xuất kỹ thuật: lưu `school_year_start`
nullable integer, hiển thị `N–(N+1)`; phạm vi 1000–9998 để hai năm đều có bốn chữ
số. Không lưu chuỗi tự do hoặc hai cột có thể mâu thuẫn. `NULL` nghĩa là không
thuộc năm học; giữ NULL cho mọi lớp cũ, không suy diễn từ ngày lớp.

## Hành vi đề xuất

- Admin/Receptionist chọn, đổi hoặc bỏ năm học trong form tạo/sửa lớp hiện có.
- Hiển thị cột năm học trong danh sách và trường tương ứng trong chi tiết lớp.
- Bộ lọc mặc định Tất cả; có lựa chọn Không thuộc năm học và từng năm học.
  Các lựa chọn năm lấy từ các lớp người gọi được phép xem, không suy từ trang
  hiện tại. Lọc kết hợp tìm kiếm trước khi đếm/phân trang; đổi lọc về trang 1.
- API/RPC giữ nguyên kiểm tra phiên, vai trò, phân công, trạng thái xóa và
  expectedVersion. Đổi năm học giữ lịch sử nghiệp vụ và audit cùng transaction.
- Hợp đồng API dùng `schoolYearStart: number | null`; query dùng
  `schoolYear=all|none|YYYY`. Bỏ query tương đương all.
- Không thay quyền, ngày lớp, lịch, phân công, học phí hoặc cơ chế chuyển lớp.
  Không thêm thư viện, không reset database, không commit/push/deploy.
- UI dùng form/select/table hiện có, tham chiếu live Metis trước khi sửa;
  hỗ trợ Việt/Anh, sáng/tối và desktop/mobile.

## Kiểm chứng

Kiểm tra giá trị biên/sai kiểu; tạo có/không năm học; đổi/bỏ năm học; filter
all/none/một năm với tổng số và phân trang; quyền User và phiên bị thu hồi;
conflict phiên bản; rollback khi audit lỗi và lịch sử trước/sau. Chạy kiểm tra
DB/API thực, unit, E2E hai viewport, lint/typecheck/build và kiểm tra artifact
theo scripts có thật. Migration chỉ áp dụng tiến trên DB local được xác nhận.
