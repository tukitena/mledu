# Mã học sinh chỉ phục vụ định danh nội bộ và Excel

Theo yêu cầu người dùng trong phiên 30/10/2026, phạm vi **STU-04, STU-01/02, CLASS-04, XLS-05, UX-01**:

- Bỏ mã khỏi trang học sinh tổng và Học sinh trong lớp, gồm bảng, chi tiết, chọn học sinh, hộp thoại thao tác và thông báo. Các thông báo xung đột vẫn nêu quy tắc trùng; không hiện mã nội bộ của học sinh liên quan.
- Tra cứu hồ sơ tổng/chọn học sinh theo tên hoặc số điện thoại; bộ lọc trong lớp theo tên, vẫn bỏ dấu/hoa thường. Lựa chọn học sinh hiển thị tên, số phụ huynh và ngày sinh nếu có để phân biệt người trùng tên.
- Bảng và hộp thoại trong lớp cũng hiển thị số phụ huynh/ngày sinh khi có, giúp phân biệt học sinh trùng tên vào cùng lớp/cùng ngày mà không cần mã.
- Giữ UUID/mã ổn định, DTO, quy tắc cấp mã, lịch sử, khôi phục và cột ẩn Excel. Không thay đổi quyền hoặc quy tắc chống trùng. Yêu cầu được bổ sung vào STU-04 trong `plans.md`.

Migration `20261030150000_student_name_phone_search.sql` chỉ thay RPC đọc `api.list_students`, bỏ nhánh khớp mã, giữ nguyên kiểm tra phiên/tài khoản, quyền danh sách lưu trữ, chuẩn hóa tên/số, đếm và phân trang. Đã kiểm tra local/test chỉ có migration này đang chờ rồi áp dụng tiến trên **mledu-test** và **mledu-dev**, không reset, không sửa/xóa dữ liệu học sinh. Chữ ký RPC và schema bảng không đổi, không cần sinh lại DB types. Chưa deploy hosted/production.

Migration bổ sung `20261030150100_class_student_display_identity.sql` thêm đúng `parentPhones` và `birthDate` vào phần student của DTO lớp; contract và UI đọc hai trường này. Giữ `canEdit`, phân quyền và ACL của helper hiện có; thông tin này vốn đã được mọi tài khoản nội bộ đọc qua hồ sơ tổng theo STU-04. Đã áp dụng tiến trên cả local/test, không đổi schema bảng/chữ ký RPC hoặc dữ liệu.

## Kiểm chứng

- `npm run test:db`: **545/545 pgTAP đạt**. Đã quan sát kiểm thử mã tìm kiếm thất bại trước migration (trả 1, kỳ vọng 0), rồi đạt sau migration; kiểm tra tên/số, chống trùng, lịch sử/khôi phục và quyền hiện có vẫn đạt.
- E2E `students.spec.ts`, `enrollments.spec.ts`, `student-edit-permissions.spec.ts`: **12/12 đạt** desktop/mobile. Bao gồm API tra mã trả rỗng; UI không lộ mã trong bảng/chi tiết/toast/lỗi trùng/hộp chọn; bộ lọc trong lớp không nhận mã; tìm tên không dấu, tạo/xóa/khôi phục, chọn học sinh, giáo viên/trợ giảng và thu hồi quyền vẫn hoạt động. Ca hai học sinh trùng tên/cùng ngày vào lớp đã thất bại vì thiếu số phân biệt trước fix, rồi đạt với từng dòng và hộp thoại đúng số phụ huynh.
- Unit frontend **8 đạt**, contracts **18 đạt**; lint, typecheck và build web/API dry-run đạt (Wrangler vẫn báo EPERM ghi log ngoài workspace nhưng dry-run kết thúc thành công). Không tuyên bố kiểm thử API unit/integration riêng hoặc CI/hosted đã đạt.
- Đã xem ảnh desktop/mobile ở `tmp/student-name-search-qa/` với dữ liệu giả, Việt/Anh, sáng/tối. Giữ kiểu bảng Metis/shared data-table đã đối chiếu trong phiên; không thêm style/dependency hoặc đưa ảnh QA vào production assets.
