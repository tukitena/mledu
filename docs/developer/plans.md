# MLedu (Miss Lien Edu) — Đặc tả hệ thống

## A. Tổng quan hệ thống

### A.1. Mục tiêu và phạm vi

MLedu hỗ trợ một trung tâm dạy thêm quản lý học sinh, lớp đa môn, nhân sự, lịch học, điểm danh, học vụ, học phí và tra cứu phụ huynh.

Hệ thống quản lý danh mục nhiều địa điểm có thể mở rộng. Tòa A và Tòa B là dữ liệu hiện tại, không cố định trong mã nguồn. Các địa điểm dùng chung học sinh, tài khoản và dữ liệu; phòng học gắn địa điểm. Không tách workspace hoặc quyền theo địa điểm.

Quy mô dự kiến: **1.500 học sinh, 100 lớp, 100 người dùng**. Đây là quy mô dữ liệu, không phải giới hạn cứng hoặc số người truy cập đồng thời.

### A.2. Vai trò và workspace

| Loại tài khoản | Phạm vi chính | Giới hạn |
| --- | --- | --- |
| Admin | Quản trị trung tâm; xem tổng tài chính/audit; quản lý học vụ, học phí và tài khoản thường; có thể tham gia giảng dạy. | Không quản trị tài khoản Admin hoặc cấp quyền Admin qua ứng dụng; tuân thủ các khóa/quy tắc nghiệp vụ ở phần C. |
| Receptionist | Quản lý học sinh/lớp, phòng/địa điểm, lịch, điểm danh, xác nhận thu và khoản ngoài học phí. | Không tổng tài chính/audit, không sửa học vụ độc lập, không cấu hình mức học phí hoặc khoản điều chỉnh, không gỡ thu sai; xóa hồ sơ tại lớp là xóa mềm theo XLS-02. |
| User | Giáo viên hoặc trợ giảng theo từng lớp; tra cứu hồ sơ toàn trung tâm; sửa thông tin học sinh và lần tham gia trong phạm vi STU-04/STU-03, thao tác học vụ/điểm danh trong lớp có phân công hiệu lực. | Không tạo mới, thêm vào lớp, xóa hoặc khôi phục học sinh/hồ sơ lớp. Một người một vai trò trong cùng lớp tại cùng thời điểm. Giáo viên được quản lý lịch, công bố/hủy công bố, xóa/khôi phục bài/đợt và sửa trang lớp; trợ giảng không có các quyền đó. Cả hai không xem chi tiết tài chính hoặc in giấy báo học phí. |
| Chưa xác thực | Đăng nhập, quên mật khẩu; phụ huynh tra cứu bằng số điện thoại tại liên kết lớp. | Không truy cập chức năng nội bộ; chỉ nhận dữ liệu đúng học sinh/lớp/thời gian và trạng thái công bố. |

Admin có ba workspace Admin/Receptionist/User; giao diện hiển thị đúng bộ chức năng của workspace đang chọn. Backend vẫn xác định loại tài khoản và kiểm tra các giới hạn nghiệp vụ tương ứng, không dựa riêng vào việc ẩn nút.

### A.3. Nguyên tắc dữ liệu

- Quyền được kiểm tra tại backend; đổi User/Receptionist áp dụng quyền mới ngay trong phiên hiện tại.
- Tài khoản, hồ sơ học sinh tổng/tại lớp, lớp, danh mục và học vụ dùng xóa mềm/lưu trữ để giữ lịch sử; mỗi nghiệp vụ có tác động riêng, không xóa dây chuyền dữ liệu quá khứ. Buổi chưa bắt đầu bị gỡ do đóng/xóa lớp có bản lưu để tạo lại đúng phần tương lai.
- Không tự xóa vĩnh viễn hồ sơ, lớp, học vụ hoặc tài chính sau 60 ngày. Lịch sử nghiệp vụ/phiên bản trước thay đổi được giữ không thời hạn và đọc theo quyền của đối tượng; phụ huynh chỉ xem dữ liệu hiện hành đúng phạm vi công bố. Audit và thông báo giữ 60 ngày riêng từ lúc tạo.
- Mọi thay đổi dữ liệu nghiệp vụ thành công phải có audit; nếu không ghi được audit, hủy thao tác. Ngoại lệ tác vụ xóa audit/thông báo hết hạn theo AUD-01. Audit không lưu mật khẩu/token và không dùng thay dữ liệu nghiệp vụ để tra cứu phụ huynh.
- **Thời gian nghiệp vụ (lựa chọn cho mục tác vụ/báo cáo được giao tự quyết):** Dùng múi giờ Asia/Ho_Chi_Minh; ngày bắt đầu có hiệu lực từ 00:00, ngày kết thúc lớp/phân công được tính hết ngày đó. Ngày nghỉ học sinh là mốc loại trừ từ 00:00 theo STU-03. Thời hạn 5 phút/60 ngày tính theo thời gian thực trôi qua từ thời điểm ghi nhận, không làm tròn về đầu ngày. Quyền theo phân công và các kiểm tra thời gian phải dựa vào thời điểm yêu cầu, không đợi tác vụ cập nhật trạng thái.

## B. Các nhóm chức năng

| Nhóm | Nội dung | Đặc tả |
| --- | --- | --- |
| Tài khoản | Tạo, đăng nhập, mật khẩu, hồ sơ, vai trò, khóa/xóa/khôi phục tài khoản. | C.2 |
| Học sinh | Hồ sơ tổng, nhiều liên hệ, chống trùng, dữ liệu riêng theo lớp, xóa mềm/khôi phục. | C.3 |
| Lớp học | Lớp đa môn, phân công, nhập/chuyển/học lại, đóng/mở/xóa/khôi phục lớp. | C.4 |
| Danh mục | Môn/khối, địa điểm, phòng và điều kiện xóa. | C.5 |
| Lịch | Lịch tuần, đổi buổi, buổi nghỉ/bù, nghỉ lễ, kiểm tra trùng lịch. | C.6 |
| Chuyên cần | Đánh dấu Vắng, lưu Có mặt cho phần còn lại, sửa và tra cứu theo ngày tham gia. | C.7 |
| Bài kiểm tra | Thang số/phân số/chữ và IELTS, Vắng, thư viện template chung do Admin quản lý, cấu hình riêng theo bài và lịch sử thay đổi. | C.8 |
| Nhận xét | Văn bản thuần tối đa 1.000 ký tự, theo bài hoặc đợt riêng. | C.9 |
| Công bố | Điểm/nhận xét riêng biệt, theo học sinh/cả lớp; khóa sửa/xóa dữ liệu đã công bố. | C.10 |
| Phụ huynh | Trang lớp, tra cứu số điện thoại, giới hạn sau nghỉ, quản lý liên kết. | C.11 |
| Tài chính | Thu học phí tháng/kỳ nhiều tháng, điều chỉnh cố định chỉ Admin cấu hình, thu trước, khoản ngoài học phí và gỡ bản thu sai. | C.12 |
| Excel | Mẫu xlsx, đối chiếu, xem trước, xác nhận, chặn lỗi/xung đột/nhập lại. | C.13 |
| Audit | Chi tiết trước/sau, một audit cho lần đồng bộ, chỉ Admin tra cứu. | C.14 |
| In/dashboard | Điểm danh A4, báo học phí A5 và biên nhận; mẫu Word do Admin quản lý, tải Word/preview/in trình duyệt; dashboard theo quyền. | C.15 |
| Trải nghiệm | Điện thoại/máy tính, Việt/Anh, sáng/tối/theo hệ thống lưu local, thông báo trong ứng dụng. | C.16 |

## C. Đặc tả chức năng

### C.1. Quy ước và mục lục

Mỗi chức năng được nhận diện bằng mã ổn định; nội dung gồm quyền, dữ liệu, quy tắc, luồng xử lý và tiêu chí nghiệm thu theo phạm vi chức năng. Các quyết định D01–D08 và lựa chọn bổ sung đã được hợp nhất vào từng chức năng; phần D tóm tắt nguồn quyết định. Giữ nguyên 60 mã chức năng, không dùng tài liệu lịch sử để ghi đè yêu cầu hiện hành.

| Mục | Nhóm chức năng | Mã chức năng |
| --- | --- | --- |
| C.2 | Tài khoản, xác thực và phân quyền | AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, AUTH-07, AUTH-08 |
| C.3 | Hồ sơ học sinh và thông tin theo lớp | STU-04, STU-03, STU-01, STU-02 |
| C.4 | Lớp học, phân công và nhập học | CLASS-03, CLASS-01, CLASS-02, CLASS-04, CLASS-05 |
| C.5 | Danh mục, địa điểm và phòng học | CAT-01, SCHED-03, SCHED-02, SCHED-05 |
| C.6 | Lịch học, buổi học và nghỉ lễ | SCHED-01, SCHED-04, SCHED-06 |
| C.7 | Chuyên cần và điểm danh | ATT-01 |
| C.8 | Bài kiểm tra, thang điểm và điểm thành phần | TEST-05, TEST-01, TEST-02, TEST-03, TEST-04, TEST-06 |
| C.9 | Nhận xét và đợt nhận xét | COMMENT-01, COMMENT-02, COMMENT-03 |
| C.10 | Công bố điểm và nhận xét | ACAD-01 |
| C.11 | Trang lớp và tra cứu phụ huynh | PORTAL-01, PORTAL-02, PORTAL-03 |
| C.12 | Học phí và khoản thu | FEE-01, FEE-02, FEE-03, FEE-04, FEE-05, FEE-06, FEE-07, FEE-08, FEE-09, FEE-10, FEE-11 |
| C.13 | Đồng bộ dữ liệu Excel | XLS-01, XLS-02, XLS-03, XLS-04, XLS-05, XLS-06 |
| C.14 | Nhật ký kiểm toán | AUD-01 |
| C.15 | In ấn và dashboard | REPORT-01, DASH-01 |
| C.16 | Giao diện, thiết bị và thông báo | UX-01, NOTIF-01 |

### C.1.1. Quy ước dữ liệu và lưu lịch sử

- Các tên học sinh/phụ huynh/tài khoản/lớp/bài/đợt/kỳ/khoản thu từ 1 đến 200 ký tự khi bắt buộc; trường tùy chọn được trống. Tên được trim và không nhận chuỗi toàn khoảng trắng. Danh mục/mức chữ có giới hạn riêng tại chức năng tương ứng.
- Ghi chú/nhận xét tối đa 1.000 ký tự; mô tả và thông báo trang lớp tối đa 5.000 ký tự, văn bản thuần. Đếm ký tự Unicode sau chuẩn hóa NFC, không đếm byte; không tự cắt. Trường nhập vượt giới hạn hoặc sai kiểu bị chặn cả UI/API/Excel. Ngày sinh nếu có không ở tương lai; trường/trường học dạng văn bản tối đa 200 ký tự.
- Xóa mềm/lưu trữ, hủy tham gia, gỡ thu sai và đóng lớp có bước xem ảnh hưởng, lý do bắt buộc và xác nhận. Không có xóa vĩnh viễn dữ liệu nghiệp vụ qua UI/API hoặc tác vụ 60 ngày. Bản ghi lưu trữ giữ định danh, phiên bản, người/thời điểm/lý do để truy lịch sử đúng quyền.
- Nội bộ xem lịch sử theo quyền đọc đối tượng: Admin toàn hệ thống; Receptionist hồ sơ/lịch/tài chính trong phạm vi nghiệp vụ nhưng không học vụ độc lập/audit; giáo viên/trợ giảng có phân công hiện hành xem học vụ/chuyên cần của lớp, không tài chính. Lớp xóa mềm chỉ Admin/Receptionist truy quản lý/lịch sử phù hợp quyền; User mất quyền lớp cho tới khi lớp được khôi phục và phân công còn hiệu lực.
- Không dựng lại lịch sử chỉ từ audit đã hết hạn. Phiên bản nghiệp vụ cũ chỉ để tham khảo nội bộ, không tự trở thành dữ liệu hiện hành hoặc nội dung công bố khi khôi phục.

### C.2. Tài khoản, xác thực và phân quyền

#### AUTH-01. Đổi mật khẩu bắt buộc ở lần đăng nhập đầu tiên

- **Mục đích:** Người dùng tự đặt mật khẩu sau khi nhận tài khoản do Admin tạo.
- **Đối tượng:** Người dùng đăng nhập lần đầu bằng mật khẩu do Admin cấp.
- **Điều kiện trước:** Admin đã tạo tài khoản bằng email và mật khẩu; tài khoản được phép đăng nhập.
- **Luồng chính:**
  1. Người dùng đăng nhập bằng email và mật khẩu do Admin cấp.
  2. Hệ thống xác định tài khoản chưa hoàn tất đổi mật khẩu lần đầu và yêu cầu đổi mật khẩu.
  3. Người dùng nhập mật khẩu mới và xác nhận mật khẩu mới.
  4. Hệ thống kiểm tra dữ liệu. Khi hợp lệ, hệ thống lưu mật khẩu mới và ghi nhận đã hoàn tất đổi mật khẩu lần đầu.
  5. Người dùng được tiếp tục vào workspace theo quyền của tài khoản.
- **Quy tắc nghiệp vụ:** Người dùng phải hoàn tất đổi mật khẩu trước khi sử dụng các chức năng nghiệp vụ. Nếu thoát trước khi hoàn tất, lần đăng nhập tiếp theo vẫn phải đổi mật khẩu.
- **Xử lý lỗi:** Nếu mật khẩu mới không hợp lệ hoặc phần xác nhận không khớp, thông báo lỗi và giữ trạng thái yêu cầu đổi mật khẩu.
- **Kết quả:** Mật khẩu do Admin cấp được thay thế bằng mật khẩu mới; tài khoản hoàn tất bước đổi mật khẩu bắt buộc.
- **Tiêu chí nghiệm thu:**
  - Tài khoản mới đăng nhập thành công được chuyển đến bước đổi mật khẩu bắt buộc.
  - Không thể truy cập chức năng nghiệp vụ khi chưa hoàn tất bước này.
  - Đổi mật khẩu không thành công không làm mất yêu cầu đổi mật khẩu.
  - Sau khi đổi thành công, mật khẩu mới dùng được để đăng nhập và mật khẩu cũ không còn dùng được.
- **Chính sách mật khẩu:** Tối thiểu 8 ký tự, không yêu cầu tổ hợp hoa/thường/số/ký tự đặc biệt. Đổi mật khẩu thành công vô hiệu các phiên khác theo AUTH-08; quên mật khẩu theo AUTH-02 với link 5 phút, dùng một lần.

#### AUTH-02. Quên mật khẩu và đặt lại mật khẩu

- **Mục đích:** Giúp người dùng khôi phục quyền truy cập khi quên mật khẩu.
- **Đối tượng:** Người dùng quên mật khẩu; Admin được quyền cấp lại mật khẩu.
- **Phương thức:** Hỗ trợ cả hai cách: người dùng tự đặt lại qua liên kết gửi đến email và Admin cấp mật khẩu tạm.
- **Luồng tự đặt lại qua email:**
  1. Người dùng chọn chức năng quên mật khẩu và nhập email tài khoản.
  2. Hệ thống gửi liên kết đặt lại mật khẩu đến email tài khoản.
  3. Người dùng mở liên kết, nhập mật khẩu mới và xác nhận mật khẩu mới.
  4. Khi thông tin hợp lệ, hệ thống cập nhật mật khẩu; người dùng có thể đăng nhập bằng mật khẩu mới.
- **Luồng Admin cấp lại mật khẩu:**
  1. Người dùng liên hệ Admin để yêu cầu cấp lại mật khẩu.
  2. Admin chọn tài khoản và cấp mật khẩu tạm.
  3. Người dùng đăng nhập bằng mật khẩu tạm.
  4. Hệ thống bắt buộc người dùng đổi mật khẩu tạm trước khi sử dụng chức năng nghiệp vụ, tương tự AUTH-01.
- **Xử lý lỗi:** Nếu mật khẩu mới không hợp lệ hoặc xác nhận không khớp, thông báo lỗi và không cập nhật mật khẩu. Liên kết không hợp lệ không được phép đặt lại mật khẩu.
- **Kết quả:** Người dùng đặt được mật khẩu mới; mật khẩu trước đó không còn dùng được sau khi được thay thế.
- **Tiêu chí nghiệm thu:**
  - Người dùng có thể thực hiện quy trình đặt lại mật khẩu qua email.
  - Admin có thể cấp mật khẩu tạm cho tài khoản.
  - Người dùng chưa đổi mật khẩu tạm không thể sử dụng chức năng nghiệp vụ.
- **Link:** Có hiệu lực 5 phút từ lúc cấp, dùng đúng một lần. Hết hạn/đã dùng bị từ chối; không cập nhật mật khẩu hoặc audit thành công. Đồng thời dùng cùng link không được đặt lại hai lần.
- **Gửi lại và phiên đăng nhập:** Cấp lại link làm vô hiệu hóa link cũ của tài khoản. Đặt lại mật khẩu thành công qua link kết thúc tất cả phiên đang mở trên mọi thiết bị; người dùng phải đăng nhập lại.
- **Giao mật khẩu tạm:** Admin tự giao qua kênh sẵn có; ứng dụng chỉ cho xem/sao chép mật khẩu vừa cấp ở lần thao tác đó, không lưu bản rõ để đọc lại. Cấp mật khẩu tạm thành công vô hiệu tất cả phiên và link đặt lại cũ ngay lập tức, bắt đổi ở lần đăng nhập tiếp theo.
- **Email lỗi:** Không thay mật khẩu khi mới yêu cầu link. Ghi lỗi gửi cho Admin và cho phép yêu cầu lại; phản hồi công khai thống nhất Nếu email hợp lệ, hệ thống sẽ gửi hướng dẫn. Chỉ link thực sự được phát hành còn hiệu lực mới đặt lại được; lỗi email không bỏ qua giới hạn 5 phút hoặc tự kích hoạt tài khoản bị khóa/xóa.

#### AUTH-03. Vô hiệu hóa và kích hoạt lại tài khoản

- **Mục đích:** Admin tạm ngừng quyền truy cập của một tài khoản và có thể cho phép truy cập trở lại.
- **Người thực hiện:** Admin.
- **Điều kiện trước:** Tài khoản cần thao tác tồn tại; người thực hiện có quyền Admin.
- **Luồng vô hiệu hóa:**
  1. Admin chọn tài khoản và thực hiện vô hiệu hóa.
  2. Hệ thống chuyển tài khoản sang trạng thái bị vô hiệu hóa.
  3. Hệ thống kết thúc ngay tất cả phiên đăng nhập của tài khoản trên mọi thiết bị.
  4. Người dùng bị đăng xuất và không thể tiếp tục truy cập chức năng yêu cầu xác thực.
- **Luồng kích hoạt lại:**
  1. Admin chọn tài khoản bị vô hiệu hóa và thực hiện kích hoạt lại.
  2. Hệ thống cho phép tài khoản đăng nhập trở lại; các phiên đã bị kết thúc không được khôi phục.
- **Quy tắc nghiệp vụ:**
  - Việc chặn truy cập có hiệu lực ngay khi tài khoản bị vô hiệu hóa, bao gồm các yêu cầu gửi bằng phiên đăng nhập cũ.
  - Tài khoản bị vô hiệu hóa không được đăng nhập cho đến khi Admin kích hoạt lại.
  - Đặt lại mật khẩu không tự kích hoạt lại tài khoản bị vô hiệu hóa.
- **Xử lý lỗi:** Người không có quyền Admin không được thực hiện thao tác. Khi người dùng đăng nhập bằng tài khoản bị vô hiệu hóa, hệ thống thông báo tài khoản không được phép truy cập.
- **Kết quả:** Trạng thái tài khoản được cập nhật và quyền truy cập thay đổi tương ứng.
- **Tiêu chí nghiệm thu:**
  - Vô hiệu hóa tài khoản đang đăng nhập trên nhiều thiết bị làm mất hiệu lực mọi phiên ngay lập tức.
  - Phiên cũ không thể tiếp tục đọc hoặc thay đổi dữ liệu sau khi tài khoản bị vô hiệu hóa.
  - Tài khoản không đăng nhập được khi đang bị vô hiệu hóa.
  - Sau khi được kích hoạt lại, người dùng phải đăng nhập lại.
- **Giới hạn tài khoản Admin:** Không cho phép vô hiệu hóa hoặc kích hoạt lại tài khoản Admin qua chức năng quản lý tài khoản của hệ thống; áp dụng AUTH-06.

#### AUTH-04. Xóa mềm tài khoản

- **Mục đích:** Loại bỏ tài khoản khỏi việc sử dụng hệ thống, đồng thời giữ lịch sử và dữ liệu liên quan.
- **Người thực hiện:** Admin.
- **Điều kiện trước:** Tài khoản tồn tại, chưa bị xóa mềm và không còn phân công giảng dạy đang có hiệu lực (bao gồm vai trò giáo viên hoặc trợ giảng); người thực hiện có quyền Admin. Phân công tương lai chưa bắt đầu không chặn thao tác và sẽ được tự hủy khi xóa thành công.
- **Luồng chính:**
  1. Admin chọn tài khoản và thực hiện xóa.
  2. Hệ thống kiểm tra các phân công giảng dạy. Nếu không còn phân công đang có hiệu lực, hệ thống tự hủy các phân công tương lai chưa bắt đầu và đánh dấu tài khoản đã bị xóa mềm.
  3. Hệ thống kết thúc tất cả phiên đăng nhập của tài khoản và chặn đăng nhập tiếp theo.
  4. Hệ thống giữ lại lịch sử thao tác và các liên kết dữ liệu của tài khoản.
- **Quy tắc nghiệp vụ:**
  - Không xóa vĩnh viễn bản ghi tài khoản hoặc xóa dây chuyền dữ liệu liên quan.
  - Chỉ được xóa khi không còn phân công giảng dạy đang có hiệu lực; áp dụng cho cả vai trò giáo viên và trợ giảng. Không tự kết thúc phân công đang có hiệu lực. Các phân công tương lai chưa bắt đầu được tự hủy khi xóa thành công, giữ nguyên lịch sử.
  - Email của tài khoản đã xóa mềm vẫn được giữ cho tài khoản đó; không được dùng email này để tạo tài khoản khác hoặc cập nhật cho tài khoản khác.
  - Admin được phép khôi phục tài khoản đã xóa mềm theo AUTH-05.
  - Giữ nguyên lịch sử điểm danh, nhập điểm, nhận xét, thu học phí và các thao tác đã thực hiện.
  - Dữ liệu lịch sử vẫn xác định được người thực hiện dù tài khoản đã bị xóa mềm.
  - Tài khoản đã bị xóa mềm không được sử dụng phiên cũ hoặc đặt lại mật khẩu để truy cập hệ thống.
- **Xử lý lỗi:** Người không có quyền Admin không được xóa tài khoản. Tài khoản không tồn tại hoặc đã bị xóa mềm không được xử lý như một lần xóa mới. Nếu còn phân công giảng dạy đang có hiệu lực, từ chối xóa và hiển thị các phân công cần kết thúc; không hủy phân công tương lai khi thao tác xóa bị từ chối.
- **Kết quả:** Tài khoản không còn sử dụng được; dữ liệu nghiệp vụ và lịch sử liên quan được bảo toàn.
- **Tiêu chí nghiệm thu:**
  - Sau khi xóa mềm, tài khoản không đăng nhập được và các phiên cũ mất hiệu lực.
  - Lịch sử thao tác vẫn hiển thị đúng người thực hiện.
  - Xóa tài khoản không làm mất điểm danh, điểm số, nhận xét hoặc giao dịch học phí đã ghi nhận.
  - Từ chối xóa khi còn ít nhất một phân công giảng dạy đang có hiệu lực; dữ liệu tài khoản và phân công không thay đổi.
  - Khi chỉ còn phân công tương lai chưa bắt đầu, xóa mềm thành công và tự hủy các phân công này, giữ nguyên lịch sử.
  - Không thể dùng email của tài khoản đã xóa mềm cho tài khoản khác.
- **Giới hạn tài khoản Admin:** Không cho phép xóa mềm tài khoản Admin qua chức năng quản lý tài khoản của hệ thống; áp dụng AUTH-06.

#### AUTH-05. Khôi phục tài khoản đã xóa mềm

- **Mục đích:** Cho phép sử dụng lại tài khoản đã xóa mềm, giữ nguyên danh tính và lịch sử.
- **Người thực hiện:** Admin.
- **Điều kiện trước:** Tài khoản tồn tại và đang ở trạng thái đã xóa mềm.
- **Luồng chính:**
  1. Admin chọn tài khoản đã xóa mềm và thực hiện khôi phục.
  2. Hệ thống bỏ trạng thái xóa mềm và kích hoạt ngay tài khoản, giữ nguyên tài khoản, email và các liên kết dữ liệu lịch sử.
  3. Hệ thống thông báo khôi phục thành công.
- **Quy tắc nghiệp vụ:**
  - Khôi phục tài khoản cũ, không tạo tài khoản mới.
  - Khôi phục đồng thời kích hoạt tài khoản, kể cả khi tài khoản đã bị vô hiệu hóa trước khi xóa mềm; không cần thao tác kích hoạt riêng.
  - Không khôi phục các phiên đăng nhập đã bị kết thúc; người dùng phải đăng nhập lại khi tài khoản được phép truy cập.
  - Không tự mở lại các phân công giảng dạy đã kết thúc hoặc đã hủy, bao gồm phân công tương lai tự hủy khi xóa mềm tài khoản.
- **Xử lý lỗi:** Từ chối thao tác nếu người thực hiện không có quyền Admin, tài khoản không tồn tại hoặc tài khoản không ở trạng thái đã xóa mềm.
- **Kết quả:** Tài khoản được khôi phục và kích hoạt ngay với email và lịch sử ban đầu; người dùng có thể đăng nhập lại, tuân theo các yêu cầu xác thực và đổi mật khẩu hiện hành.
- **Tiêu chí nghiệm thu:**
  - Admin khôi phục được tài khoản đã xóa mềm.
  - Email, định danh tài khoản và lịch sử thao tác được giữ nguyên.
  - Các phiên cũ vẫn mất hiệu lực và phân công giảng dạy đã kết thúc không tự hoạt động lại.
  - Tài khoản được kích hoạt ngay sau khi khôi phục, bao gồm tài khoản đã bị vô hiệu hóa trước khi xóa mềm; không cần Admin kích hoạt riêng.

#### AUTH-06. Giới hạn thao tác quản trị đối với tài khoản Admin

- **Mục đích:** Việc quản trị tài khoản Admin được thực hiện từ bên trong, không thông qua chức năng quản lý tài khoản của ứng dụng.
- **Phạm vi:** Các thao tác quản trị nhắm đến tài khoản Admin và các thao tác cấp hoặc thay đổi quyền Admin.
- **Quy tắc nghiệp vụ:**
  - Chặn thao tác quản trị đối với tài khoản Admin, kể cả khi người thực hiện cũng là Admin; ngoại trừ các chức năng tự phục vụ được nêu bên dưới.
  - Không cho phép khóa, kích hoạt lại, xóa mềm hoặc khôi phục tài khoản Admin qua chức năng quản lý tài khoản.
  - Không cho phép thăng cấp tài khoản thường lên Admin qua chức năng quản lý tài khoản.
  - Tạo tài khoản Admin và thay đổi quyền Admin chỉ được thực hiện từ bên trong.
  - Các quy tắc AUTH-03, AUTH-04 và AUTH-05 chỉ áp dụng qua ứng dụng cho tài khoản không phải Admin.
  - Kiểm tra giới hạn tại backend; việc ẩn hoặc vô hiệu hóa thao tác trên frontend không thay thế kiểm tra quyền tại backend. Quy tắc này là ngoại lệ đối với quyền toàn hệ thống của Admin tại phần A.
- **Luồng xử lý:**
  1. Người dùng thực hiện một thao tác quản trị tài khoản.
  2. Hệ thống kiểm tra tài khoản đích và thay đổi quyền được yêu cầu.
  3. Nếu thao tác quản trị nhắm đến tài khoản Admin hoặc cấp/thay đổi quyền Admin, hệ thống từ chối và giữ nguyên dữ liệu. Các thao tác tự phục vụ hợp lệ của chính Admin được xử lý theo chức năng tương ứng.
- **Kết quả:** Chỉ các thao tác được phép đối với tài khoản không phải Admin được tiếp tục xử lý.
- **Tiêu chí nghiệm thu:**
  - Admin không khóa, xóa hoặc khôi phục được tài khoản Admin của mình hay Admin khác qua chức năng quản lý tài khoản.
  - Không thể tạo tài khoản Admin hoặc thăng cấp tài khoản thường lên Admin qua giao diện hoặc gọi trực tiếp API quản lý tài khoản.
  - Thao tác bị từ chối không làm thay đổi trạng thái, vai trò hoặc dữ liệu tài khoản.
- **Ngoại lệ tự phục vụ:** Admin được tự sửa hồ sơ, đổi mật khẩu và sử dụng chức năng quên mật khẩu. Các thao tác này không được thay đổi vai trò hoặc trạng thái quản trị của tài khoản.
- **Quản trị từ bên trong:** Dùng công cụ vận hành có kiểm soát truy cập, không cung cấp route/nút trong ứng dụng để tạo/đổi quyền Admin. Công cụ ghi người vận hành, thời điểm và thay đổi vào nguồn audit chung; không ghi mật khẩu/token. Công cụ chỉ thực hiện thay đổi tài khoản, không sửa trực tiếp học vụ/tài chính để né quy tắc.

#### AUTH-07. Vai trò mặc định và chuyển đổi User/Receptionist

- **Mục đích:** Tạo tài khoản với quyền User mặc định và cho phép Admin chuyển đổi giữa User và Receptionist khi cần.
- **Người thực hiện:** Admin.
- **Quy tắc nghiệp vụ:**
  - Tài khoản mới tạo qua chức năng quản lý tài khoản mặc định có vai trò User.
  - Admin có thể giữ nguyên vai trò User hoặc chuyển thành Receptionist; việc chuyển vai trò không bắt buộc.
  - Admin được phép đổi Receptionist trở lại User.
  - Chỉ được đổi User sang Receptionist khi tài khoản không còn phân công lớp có hiệu lực, bao gồm cả phân công giáo viên và trợ giảng. Kiểm tra trên tất cả lớp của tài khoản.
  - Không tự kết thúc phân công đang có hiệu lực khi đổi loại tài khoản. Khi đổi User sang Receptionist thành công, tự hủy các phân công tương lai chưa bắt đầu; giữ nguyên lịch sử phân công đã kết thúc hoặc đã hủy.
  - Việc chuyển đổi User/Receptionist là thay đổi loại tài khoản, không phải thay đổi vai trò giáo viên/trợ giảng trong một lớp.
  - Khi thay đổi loại tài khoản thành công, giữ nguyên các phiên đang đăng nhập; người dùng không cần đăng xuất hoặc đăng nhập lại.
  - Quyền mới có hiệu lực ngay trên tất cả phiên đang đăng nhập. Backend kiểm tra theo quyền mới đối với các yêu cầu tiếp theo; quyền cũ không tiếp tục được sử dụng.
  - Giao diện và workspace cập nhật theo loại tài khoản mới trong phiên hiện tại; trang hoặc thao tác không còn được phép phải bị chặn.
  - Không cho phép tạo hoặc chuyển tài khoản thành Admin qua chức năng này; áp dụng AUTH-06.
- **Luồng chính:**
  1. Admin tạo tài khoản bằng thông tin hợp lệ; hệ thống gán vai trò User.
  2. Admin chọn tài khoản và yêu cầu đổi User sang Receptionist hoặc Receptionist sang User.
  3. Hệ thống kiểm tra quyền thực hiện và tài khoản đích. Nếu đổi User sang Receptionist, kiểm tra tài khoản không còn phân công lớp có hiệu lực.
  4. Khi thỏa mãn điều kiện, nếu đổi User sang Receptionist, hệ thống tự hủy các phân công tương lai chưa bắt đầu; sau đó cập nhật loại tài khoản theo yêu cầu.
  5. Hệ thống áp dụng quyền mới ngay cho các phiên đang đăng nhập và cập nhật giao diện, không bắt người dùng đăng nhập lại.
- **Xử lý lỗi:** Từ chối yêu cầu thay đổi vai trò do người không có quyền Admin thực hiện hoặc yêu cầu thay đổi vai trò của tài khoản Admin. Nếu đổi User sang Receptionist khi còn phân công lớp có hiệu lực, từ chối thao tác, hiển thị các phân công cần kết thúc và giữ nguyên loại tài khoản cùng dữ liệu phân công.
- **Kết quả:** Tài khoản giữ vai trò User mặc định hoặc được Admin chuyển đổi giữa User và Receptionist theo điều kiện tại AUTH-07.
- **Tiêu chí nghiệm thu:**
  - Tài khoản vừa tạo có vai trò User nếu chưa được Admin đổi vai trò.
  - Admin đổi được User sang Receptionist khi không còn phân công lớp có hiệu lực.
  - Từ chối đổi User sang Receptionist nếu còn ít nhất một phân công lớp có hiệu lực, kể cả phân công trợ giảng; không thay đổi dữ liệu khi từ chối.
  - Admin đổi được Receptionist trở lại User.
  - Chuyển đổi loại tài khoản không làm mất lịch sử phân công lớp.
  - Phân công tương lai chưa bắt đầu không chặn đổi User sang Receptionist và được tự hủy khi đổi thành công.
  - Nếu còn phân công đang có hiệu lực, từ chối đổi vai trò và không hủy bất kỳ phân công tương lai nào.
  - Các phiên đang đăng nhập vẫn hoạt động sau khi đổi loại tài khoản, với quyền mới có hiệu lực ngay.
  - Yêu cầu tiếp theo từ phiên cũ bị từ chối nếu thao tác không còn thuộc quyền của loại tài khoản mới, kể cả gọi trực tiếp API.
  - Giao diện và workspace phản ánh quyền mới mà không yêu cầu đăng nhập lại.
  - User và Receptionist không được tự thay đổi loại tài khoản.
  - Chức năng không cho phép cấp quyền Admin.
- **Thời hạn phân công:** Áp dụng quy tắc phân công có thời hạn và cho phép kết thúc sớm tại CLASS-01.
- **Dữ liệu tạo tài khoản:** Email, họ tên và mật khẩu tạm bắt buộc; ảnh/số điện thoại/ngày sinh tùy chọn. Email được trim, chuẩn hóa chữ thường và duy nhất kể cả tài khoản xóa mềm; chỉ cấp loại User hoặc Receptionist theo luồng này. Hồ sơ cá nhân khác không làm thay đổi email đăng nhập.

#### AUTH-08. Hồ sơ cá nhân, email, mật khẩu và phiên

- **Người dùng tự phục vụ:** Tự sửa các thông tin hồ sơ của mình như ảnh, họ tên, số điện thoại, ngày sinh; không được tự đổi email đăng nhập.
- **Phạm vi:** Tự sửa hồ sơ không bao gồm vai trò, trạng thái tài khoản, phân công hoặc quyền; các dữ liệu quản trị vẫn theo AUTH-03 đến AUTH-07. Admin cũng được tự phục vụ theo ngoại lệ tại AUTH-06.
- **Mật khẩu:** Tối thiểu 8 ký tự, không yêu cầu tổ hợp hoa/thường/số/ký tự đặc biệt. Vẫn bắt đổi mật khẩu Admin cấp ở lần đầu và sau cấp lại mật khẩu tạm.
- **Phiên:** Không giới hạn số phiên hay thiết bị đăng nhập, không đặt giới hạn phiên theo yêu cầu hiện tại. Vô hiệu hóa/xóa tài khoản vẫn làm mất hiệu lực mọi phiên; quyền mới áp dụng ngay khi đổi User/Receptionist.
- **Nghiệm thu:** Không sửa email qua giao diện hoặc API tự phục vụ; sửa được hồ sơ còn lại; đăng nhập nhiều thiết bị không đẩy phiên khác ra; khóa tài khoản vẫn chặn mọi phiên.
- **Đổi mật khẩu:** Sau đổi thành công, vô hiệu các phiên khác; phiên thực hiện đổi được giữ theo luồng xác thực hiện hành. Không thay chính sách cho đăng nhập nhiều thiết bị/phiên không giới hạn khi dùng bình thường.
- **Link đặt lại:** Hết hạn sau 5 phút từ lúc cấp, dùng một lần; áp dụng AUTH-02.
- **Ảnh hồ sơ:** Tùy chọn JPG/PNG/WebP, tối đa 5.000.000 byte, kiểm tra loại ảnh tại backend; chỉ chủ tài khoản tự đổi ảnh, Admin không dùng thao tác ảnh để sửa loại tài khoản.

### C.3. Hồ sơ học sinh và thông tin theo lớp

#### STU-04. Hồ sơ tổng, liên hệ và chuẩn hóa tra cứu

- **Quyền (cập nhật 28/10/2026):** Admin/Receptionist tạo, sửa, xóa mềm, khôi phục. User là giáo viên hoặc trợ giảng có phân công đang hiệu lực được sửa các trường thông tin học sinh như Admin/Receptionist, khi học sinh có hồ sơ chưa xóa trong ít nhất một lớp chưa xóa mà User đang được phân công. User không tạo mới, xóa mềm hoặc khôi phục học sinh. Mọi tài khoản nội bộ vẫn được tra cứu hồ sơ toàn trung tâm; quyền tra cứu không tự cấp quyền sửa ngoài phạm vi trên, học vụ, ghi chú lớp hoặc tài chính ngoài phạm vi được cấp.
- **Phạm vi sửa của User:** Tên học sinh, tên phụ huynh, số phụ huynh/học sinh, ngày sinh, trường và ghi chú tổng quan theo cùng kiểm tra dữ liệu/chống trùng như Admin/Receptionist; không đổi mã/định danh hoặc trạng thái lưu trữ. Đây là hồ sơ tổng dùng chung, sửa có hiệu lực ở mọi lớp liên quan; giao diện phải nêu rõ tác động này, không tạo bản thông tin riêng của User/lớp. Không sửa hồ sơ tổng đã xóa. Backend kiểm tra lại tài khoản, phân công và quan hệ học sinh–lớp khi ghi, kể cả sau preview hoặc khi gọi trực tiếp API/Excel; thành công ghi audit cùng transaction.
- **Dữ liệu:** Chỉ tên học sinh bắt buộc. Tên phụ huynh, nhiều số phụ huynh/học sinh, ngày sinh, trường, ghi chú tổng quan đều tùy chọn. Giữ nguyên tên có dấu để hiển thị; các giá trị chuẩn hóa chỉ dùng đối chiếu/tìm kiếm.
- **Chuẩn hóa tên:** Unicode NFD, bỏ dấu kết hợp, đổi đ/Đ thành d, chuyển chữ thường, bỏ khoảng trắng đầu/cuối và gộp khoảng trắng liên tiếp thành một. Không bỏ hoặc thay dấu câu. Ví dụ `Đặng  Thị Ánh` và `dang thi anh` cùng khóa tên.
- **Chuẩn hóa số:** Bỏ khoảng trắng và ký tự phân cách `.`, `-`, `(`, `)`; đổi đầu `+84` hoặc `0084` về `0` cho số Việt Nam, giữ số 0 đầu. Chấp nhận số Việt Nam 10 hoặc 11 chữ số bắt đầu bằng 0; số nước ngoài giữ dấu `+` và 8–15 chữ số. Từ chối chuỗi không hợp lệ, không sửa ngầm chữ thành số. Loại trùng số trong cùng hồ sơ theo loại liên hệ.
- **Chống trùng:** Đối chiếu cả hồ sơ hoạt động và xóa mềm. Khi thêm học sinh có khóa tên đã tồn tại, bắt buộc có ít nhất một số phụ huynh. Nếu cùng khóa tên và tập số phụ huynh giao nhau, chặn lưu; hai hồ sơ cùng khóa tên và cùng thiếu số cũng không hợp lệ. Hai tên khác nhau được chung số phụ huynh. Không dùng số học sinh để thay điều kiện số phụ huynh.
- **Sửa hồ sơ:** Đổi tên sang khóa tên đã có áp dụng cùng điều kiện số phụ huynh. Không cho bỏ hết số phụ huynh đã có khi còn hồ sơ khác cùng khóa tên. Hồ sơ ban đầu được tạo không có số khi tên còn duy nhất vẫn được giữ và sửa trường khác; không bắt bổ sung số chỉ vì sau đó có học sinh cùng tên được thêm hợp lệ.
- **Hồ sơ đã xóa:** Trùng cả tên chuẩn hóa và số phụ huynh với hồ sơ xóa mềm thì hướng tới khôi phục; không tạo bản sao hoặc tự khôi phục qua Excel.
- **Tra cứu:** Tìm tên nội bộ không phân biệt dấu/hoa thường theo khóa chuẩn hóa; tìm số dùng số chuẩn hóa. Thêm qua Excel phải xác định duy nhất hồ sơ theo XLS-06. Phụ huynh vẫn chỉ tra bằng số tại PORTAL-02.
- **Ghi chú:** Ghi chú tổng quan thấy trong hồ sơ tổng; ghi chú lớp chỉ người có quyền lớp được xem, không trả công khai.
- **Nghiệm thu:** Tên chưa trùng được tạo không cần số; thêm tên không dấu trùng khóa phải có số phụ huynh khác; `0912 345 678` và `+84 912345678` được đối chiếu như nhau. Một lỗi trùng trên Excel chặn toàn bộ file; thao tác thành công có audit. Giáo viên và trợ giảng sửa được hồ sơ đúng phạm vi, các lớp cùng học sinh thấy cùng dữ liệu; ngoài phạm vi, phân công đã hết/thu hồi hoặc yêu cầu tạo/xóa/khôi phục của User đều bị chặn ở backend. Lỗi audit không để lại thay đổi hồ sơ.

#### STU-03. Hồ sơ học sinh tại lớp và các lần tham gia

- **Quyền (cập nhật 28/10/2026):** Admin/Receptionist quản lý. User là giáo viên hoặc trợ giảng có phân công đang hiệu lực được sửa ghi chú lần tham gia và ghi ngày nghỉ lần đầu, với cùng ràng buộc như Admin/Receptionist, trong đúng lớp được phân công. Chỉ sửa hồ sơ tổng/hồ sơ lớp chưa xóa; lớp đã xóa chỉ đọc lịch sử đúng quyền. User không thêm học sinh vào lớp, tạo lần tham gia, xóa/lưu trữ hồ sơ, hủy đăng ký hoặc khôi phục; không dùng quyền sửa để chuyển lớp/học lại theo CLASS-04. Quyền sửa hồ sơ tổng theo STU-04; quyền học vụ/điểm danh theo ATT-01, TEST-01 và COMMENT-01 vẫn độc lập.
- **Hồ sơ tại lớp:** Một học sinh có tối đa một hồ sơ học sinh–lớp chưa xóa trong một lớp. Hồ sơ có định danh riêng, chứa nhiều lần tham gia có định danh riêng; dùng chung mã học sinh tổng. Xóa mềm hồ sơ tại lớp rồi thêm lại tạo hồ sơ mới theo XLS-02, khác với học lại trong hồ sơ cũ theo CLASS-04.
- **Mỗi lần tham gia:** Ngày vào bắt buộc; ngày nghỉ tùy chọn; ghi chú lớp tùy chọn. Trạng thái hiển thị là Chưa bắt đầu, Đang học hoặc Nghỉ, tính từ thời gian thực tế, không nhập đè qua giao diện/API/Excel.
- **Mốc ngày:** Ngày vào có hiệu lực 00:00; ngày nghỉ là ngày sau ngày học cuối và loại trừ từ 00:00. Ngày vào không trước ngày mở lớp, không sau ngày kết thúc lớp; ngày nghỉ phải sau ngày vào. Không cho các lần tham gia trong cùng hồ sơ chồng thời gian. Thêm lại sau xóa hồ sơ được phép cùng ngày; mốc tham gia thực tế của hồ sơ mới không trước thời điểm xóa hồ sơ cũ, dù ngày vào cùng ngày. Không lấy giao ngày với hồ sơ lưu trữ để chặn trường hợp thêm lại này.
- **Khóa ngày (giữ nguyên theo xác nhận 28/10/2026):** Ngày vào đã lưu không đổi; ngày nghỉ chỉ ghi lần đầu và không được sửa/xóa sau đó, áp dụng như nhau cho Admin, Receptionist và User. Không ghi ngày nghỉ để mở lại lần đã kết thúc hoặc thay mốc hủy/lưu trữ. Sai ngày được Admin/Receptionist xử lý bằng hủy lần tham gia chưa bắt đầu hoặc lưu trữ hồ sơ và thêm lại, giữ bản cũ; User không tự thực hiện các thao tác này. Không sửa lịch sử để né kiểm tra.
- **Trạng thái:** Trước ngày vào là Chưa bắt đầu; từ ngày vào đến trước ngày nghỉ hoặc hết ngày kết thúc lớp là Đang học; sau mốc kết thúc là Nghỉ. Nếu lớp đóng tạm, giữ trạng thái tính từ các ngày, hiển thị thêm nhãn Lớp đóng; đóng không tự đặt ngày nghỉ. Lần bị hủy hoặc kết thúc do xóa mềm hiển thị Nghỉ kèm lý do, không sửa ngày đã khóa.
- **Kết thúc bằng sự kiện:** Xóa mềm hồ sơ tổng/hồ sơ tại lớp hoặc hủy tham gia lưu mốc thời điểm riêng. Khoảng hiệu lực kết thúc tại mốc sớm nhất giữa ngày nghỉ, hết ngày kết thúc lớp đã ghi cho lần tham gia và sự kiện kết thúc. Giữ mốc kết thúc đã xảy ra; gia hạn lớp sau đó không hồi sinh lần đã Nghỉ.
- **Hủy đăng ký chưa bắt đầu:** Admin/Receptionist chọn lần tham gia tương lai, nhập lý do và xác nhận hủy; lưu lần tham gia cùng trạng thái hủy, không xóa cứng. Hủy nghĩa vụ chưa thu chỉ phục vụ lần bị hủy nếu không còn khoảng tham gia thực tế/đăng ký hợp lệ khác cho nghĩa vụ đó, kể cả tháng hiện tại đã tạo trước ngày vào. Khoản đã thu và nợ thuộc thời gian đã thực sự tham gia giữ nguyên. Không tự hủy nghĩa vụ còn dùng cho lần tham gia khác trong cùng hồ sơ. Một lỗi dữ liệu/audit hủy cả thao tác.
- **Tra cứu lịch sử:** Ngày, ghi chú và sự kiện cũ vẫn được tra đúng quyền; không lấy trạng thái hiện tại thay khoảng tham gia khi điểm danh, phát sinh phí hoặc tra cứu phụ huynh.
- **Nghiệm thu:** Đăng ký tương lai không Đang học sớm; đóng lớp không làm mất lịch sử; đến ngày nghỉ tự Nghỉ. UI/API/Excel cùng chặn sửa ngày đã khóa, chồng khoảng và cập nhật trực tiếp trạng thái. Giáo viên/trợ giảng sửa ghi chú và ghi ngày nghỉ lần đầu trong đúng lớp; cả ba loại tài khoản đều không đổi ngày vào đã lưu hoặc sửa/xóa ngày nghỉ đã ghi. User không được sửa lần tham gia ở lớp khác dù cùng học sinh. Thu hồi/hết phân công giữa lúc xem và lưu phải chặn; tạo/thêm/xóa/hủy/khôi phục trái quyền bị chặn; lỗi audit rollback toàn bộ.

#### STU-01. Xóa mềm học sinh tại danh sách tổng

- **Quyền/phạm vi:** Admin hoặc Receptionist, trực tiếp hoặc qua XLS-01; User không được xóa, kể cả học sinh trong lớp được phân công. Xóa tổng không gọi xóa hồ sơ học sinh tại lớp tại XLS-02.
- **Thao tác:** Xem ảnh hưởng và xác nhận; ghi thời điểm/lý do xóa mềm, kết thúc các lần tham gia đang hiệu lực tại thời điểm đó, hủy đăng ký chưa bắt đầu theo STU-03. Thay đổi hồ sơ, sự kiện tham gia, nghĩa vụ tương lai và audit cùng thành công/thất bại.
- **Lịch sử:** Giữ mã học sinh, hồ sơ, liên hệ, các lần tham gia, điểm, nhận xét, chuyên cần và tài chính. Không sửa các ngày đã khóa; sự kiện kết thúc được lưu riêng. Không có tác vụ tự xóa vĩnh viễn hồ sơ hoặc lịch sử sau 60 ngày.
- **Công nợ:** Cho xóa mềm dù còn nợ vì dữ liệu được giữ. Khoản đã thu và khoản chưa thu đã phát sinh trước mốc kết thúc vẫn có hiệu lực, tiếp tục thu/gỡ thu đúng quyền tại danh sách tài chính có hồ sơ lưu trữ. Chỉ hủy nghĩa vụ chưa thu có ngày áp dụng sau mốc kết thúc và không còn khoảng tham gia phù hợp. Không coi nghĩa vụ thiếu cấu hình/lỗi tác vụ là đã thu; vẫn chạy bù phần lịch sử đủ điều kiện theo FEE-07.
- **Phụ huynh:** Vẫn tra cứu lịch sử thuộc khoảng tham gia trước mốc kết thúc, theo PORTAL-02; không hiện như học sinh đang tham gia.
- **Khôi phục:** Theo STU-02, không tự mở lại đăng ký hoặc lần tham gia đã kết thúc.
- **Nghiệm thu:** Xóa mềm học sinh có nhiều lớp không mất học vụ hoặc tiền, không chặn thu khoản nợ còn hiệu lực; các đăng ký tương lai được hủy và có lịch sử. Lỗi một bước/audit không để lại xóa một phần.

#### STU-02. Khôi phục hồ sơ học sinh đã xóa mềm

- **Quyền:** Admin/Receptionist, chỉ qua giao diện; User không được thực hiện. Excel không hỗ trợ Thao tác = Khôi phục.
- **Luồng:** Chọn hồ sơ lưu trữ, xác nhận khôi phục; kiểm tra chống trùng theo STU-04, giữ mã, dữ liệu và toàn bộ lịch sử. Nếu xung đột thông tin thì sửa thông tin hợp lệ trong cùng thao tác khôi phục, không gộp hồ sơ tự động.
- **Tham gia lớp:** Không tự khôi phục lớp hoặc lần tham gia cũ. Học lại trong hồ sơ học sinh–lớp còn lưu dùng CLASS-04; thêm lại sau khi hồ sơ tại lớp đã xóa mềm tạo hồ sơ mới theo XLS-02.
- **Nghiệm thu:** Khôi phục không tạo học sinh/mã mới, không nhân đôi học vụ hoặc khoản cũ; giữ sự kiện kết thúc và trạng thái hủy đăng ký. Không có thời hạn tự hết quyền khôi phục.

### C.4. Lớp học, phân công và nhập học

#### CLASS-03. Thông tin lớp và lớp đa môn

- **Quyền:** Admin/Receptionist tạo, sửa thông tin lớp. Mô tả/thông báo công khai chỉ Admin hoặc giáo viên đang có phân công hiệu lực sửa theo PORTAL-01.
- **Thông tin bắt buộc:** Tên lớp, một môn, một khối, ngày mở và ngày kết thúc; ngày kết thúc không trước ngày mở. Ghi chú tùy chọn. Chuyên môn phụ trách của nhân sự lưu tùy chọn trên phân công, không bắt buộc trùng môn lớp.
- **Năm học (bổ sung được duyệt 30/10/2026):** Tùy chọn, dạng chuẩn hai năm liên tiếp `2026–2027`. Lưu năm bắt đầu là số nguyên 1000–9998; để trống (`NULL`) nghĩa là lớp không thuộc biên chế năm học. Không suy diễn năm học từ ngày lớp và không ràng buộc ngày mở/kết thúc theo năm học. Admin/Receptionist được gán, đổi hoặc bỏ năm học khi tạo/sửa lớp theo quyền hiện có; mọi thay đổi giữ lịch sử và audit nguyên khối. Lớp có sẵn giữ `NULL` khi thêm trường.
- **Hiển thị/lọc năm học:** Danh sách có cột Năm học; form tạo/sửa và chi tiết lớp hiển thị cùng giá trị. Bộ lọc mặc định **Tất cả năm học**, cho chọn một năm học cụ thể hoặc **Không thuộc năm học**, kết hợp với tìm tên lớp trước khi đếm/phân trang; đổi bộ lọc quay về trang 1. Danh sách năm học lấy từ toàn bộ lớp trong phạm vi người gọi được phép đọc (cùng trạng thái xóa), không giới hạn bởi trang/tên/năm đang lọc và không tiết lộ năm từ lớp ngoài quyền. User chỉ lọc trong lớp có phân công hiệu lực; bộ lọc không cấp thêm quyền.
- **Sắp xếp và bộ lọc danh sách (bổ sung theo yêu cầu 30/10/2026):** Mặc định tên ngắn hơn đứng trước; cùng số ký tự thì so từ điển theo khóa tên chuẩn hóa, rồi tên hiển thị/ID để ổn định phân trang. Kết hợp tìm tên, năm học, khối, môn, trạng thái và nhân sự trước khi đếm/phân trang; đổi bộ lọc về trang 1. Trạng thái cho chọn Mở/Đóng hoặc Chưa mở/Đang diễn ra/Đã kết thúc theo ngày nghiệp vụ. Nhân sự gồm giáo viên/trợ giảng có phân công đang hiệu lực. Lựa chọn khối/môn/nhân sự lấy từ toàn bộ lớp được đọc cùng trạng thái xóa, độc lập bộ lọc/trang, giữ danh mục lưu trữ còn được lớp tham chiếu; không mở rộng quyền hoặc lộ lựa chọn từ lớp ngoài quyền. Nghiệm thu trên desktop/mobile, Việt/Anh, cả kết quả rỗng và phân công/phiên bị thu hồi.
- **Đa môn:** Lớp có nhiều giáo viên/trợ giảng; không bắt buộc mọi lớp có ba giáo viên. Mỗi lớp có nhiều lịch/phòng/địa điểm khác nhau.
- **Sửa ngày:** Trước khi lớp bắt đầu và chưa có lịch sử tham gia/buổi đã bắt đầu, được sửa ngày nếu vẫn bao phủ mọi ngày vào đã lưu. Khi đã có hoạt động, khóa ngày mở; ngày kết thúc chỉ được thay từ hôm nay trở đi, không hồi tố để cắt lịch sử. Rút ngắn ngày kết thúc phải xem trước và xử lý buổi chưa bắt đầu nằm ngoài phạm vi trong cùng giao dịch; không thay ngày vào/nghỉ đã khóa.
- **Gia hạn:** Giữ lịch sử kết thúc đã xảy ra của học sinh/phân công. Người đã kết thúc muốn học/dạy tiếp phải có lần tham gia/phân công mới; các khoảng chưa kết thúc được kéo dài phạm vi lớp nhưng không vượt ngày nghỉ/kết thúc riêng đã lưu. Kỳ thu đã cấu hình không tự đổi theo ngày lớp mới, theo FEE-02.
- **Nghiệm thu:** Bộ trường hợp lệ tạo được lớp; môn khác chuyên môn không chặn phân công; sửa/gia hạn không hồi sinh khoảng đã kết thúc hoặc viết lại dữ liệu quá khứ; mọi thay đổi có audit.
- **Nghiệm thu năm học:** Tạo được lớp có/không năm học; sửa/đổi/bỏ năm học giữ lịch sử và kiểm tra phiên bản; lỗi audit rollback toàn bộ. Từ chối năm sai định dạng/ngoài phạm vi. Lọc Tất cả/Không thuộc năm học/một năm cho đúng bản ghi, tổng số và phân trang; không mở rộng quyền hoặc bỏ qua phiên/phân công bị thu hồi. UI Việt/Anh và desktop/mobile đều thao tác được; ngày lớp có thể nằm ngoài năm học đã gán.
- **Trạng thái quản trị:** Lớp mới mặc định Mở; ngày mở/kết thúc vẫn giới hạn thời gian tham gia/lịch/thu trước. Lớp Mở chưa tới ngày mở không làm học sinh Đang học sớm; lớp hết ngày kết thúc không phát sinh buổi mới.

#### CLASS-01. Thời hạn phân công giáo viên/trợ giảng

- **Mục đích:** Xác định khoảng thời gian người dùng được phân công làm giáo viên hoặc trợ giảng của một lớp.
- **Người thực hiện:** Admin hoặc Receptionist.
- **Dữ liệu phân công:** Lớp học, người được phân công, vai trò giáo viên/trợ giảng, ngày bắt đầu và ngày kết thúc.
- **Quy tắc nghiệp vụ:**
  - Phân công có thời hạn, gồm ngày bắt đầu và ngày kết thúc.
  - Phân công tự hết hiệu lực khi hết thời hạn, không yêu cầu người quản lý kết thúc thủ công.
  - Admin hoặc Receptionist được tạo, sửa, gia hạn hoặc kết thúc phân công sớm; mọi thay đổi đều kiểm tra hiệu lực và audit.
  - Kết thúc sớm không xóa lịch sử phân công hoặc dữ liệu học vụ đã phát sinh.
  - Quyền giáo viên/trợ giảng của User đối với lớp được áp dụng theo thời hạn phân công; phân công đã kết thúc không tiếp tục cấp quyền này.
  - Quy tắc chặn xóa tài khoản tại AUTH-04 và đổi User sang Receptionist tại AUTH-07 sử dụng trạng thái đang có hiệu lực của phân công.
  - Phân công tương lai chưa bắt đầu không chặn hai thao tác trên; được tự hủy khi thao tác thành công và vẫn được lưu trong lịch sử.
  - Nếu thao tác xóa tài khoản hoặc đổi vai trò bị từ chối hay thất bại, không hủy các phân công tương lai.
  - Khôi phục tài khoản hoặc đổi Receptionist trở lại User không tự khôi phục phân công đã hủy.
- **Luồng chính:**
  1. Người quản lý chọn lớp, người dùng, vai trò và thời hạn phân công.
  2. Hệ thống kiểm tra dữ liệu, gồm ngày kết thúc không trước ngày bắt đầu, và lưu phân công hợp lệ.
  3. Phân công có hiệu lực trong thời hạn đã thiết lập và tự hết hiệu lực khi hết thời hạn.
- **Luồng kết thúc sớm:**
  1. Admin hoặc Receptionist chọn phân công và yêu cầu kết thúc sớm.
  2. Hệ thống ghi nhận việc kết thúc sớm và giữ lại lịch sử phân công.
  3. Phân công không tiếp tục cấp quyền sau thời điểm kết thúc sớm.
- **Xử lý lỗi:** Từ chối thao tác của người không có quyền quản lý phân công hoặc dữ liệu thời hạn không hợp lệ; không thay đổi phân công khi thao tác thất bại.
- **Kết quả:** Phân công có thời hạn được lưu và có thể kết thúc sớm; quyền đối với lớp phản ánh hiệu lực phân công.
- **Tiêu chí nghiệm thu:**
  - Tạo được phân công có ngày bắt đầu và ngày kết thúc hợp lệ.
  - Phân công chưa đến ngày bắt đầu không cấp quyền giảng dạy cho User.
  - Phân công tự hết hiệu lực khi hết thời hạn.
  - Admin và Receptionist có thể kết thúc sớm phân công; lịch sử và dữ liệu học vụ được giữ nguyên.
- **Điều kiện phân công:** Chỉ tài khoản User/Admin đang hoạt động, chưa xóa mềm; thời hạn nằm trong ngày mở/kết thúc lớp tại lúc tạo. Môn phụ trách là ghi chú văn bản tùy chọn tối đa 200 ký tự, không khóa theo môn lớp. Không đặt giới hạn số giáo viên/trợ giảng; chặn các phân công chồng thời hạn cho cùng người/lớp kể cả cùng vai trò, xét cả sự kiện kết thúc sớm.
- **Lớp đóng/xóa:** Đóng giữ thời hạn phân công; lớp xóa mềm chặn quyền User dù phân công còn ngày. Khôi phục không tự gia hạn hoặc tạo lại phân công đã hết hạn/hủy; quyền lịch sử chỉ cấp theo tài khoản và phân công hiện hành.

#### CLASS-02. Nhiều giáo viên và trợ giảng trong một lớp

- **Mục đích:** Cho phép phân công đồng thời nhiều giáo viên và nhiều trợ giảng cho cùng một lớp.
- **Người thực hiện:** Admin hoặc Receptionist.
- **Điều kiện trước:** Lớp và tài khoản được phân công tồn tại; tài khoản đủ điều kiện được phân công theo loại tài khoản (User hoặc Admin).
- **Quy tắc nghiệp vụ:**
  - Một lớp được có nhiều giáo viên cùng có phân công đang hiệu lực.
  - Một lớp được có nhiều trợ giảng cùng có phân công đang hiệu lực.
  - Không giới hạn lớp ở mô hình một giáo viên chính duy nhất.
  - Thời hạn của từng phân công được quản lý độc lập theo CLASS-01.
  - Phân công thêm người không tự kết thúc hoặc thay thế phân công của người khác trong lớp.
  - Trợ giảng được chỉnh sửa điểm và nhận xét theo phạm vi lớp nhưng không được công bố hoặc hủy công bố; quyền này thuộc giáo viên và Admin theo phần A–B.
- **Luồng chính:**
  1. Người quản lý chọn lớp và thêm từng giáo viên hoặc trợ giảng cùng thời hạn phân công.
  2. Hệ thống kiểm tra điều kiện của từng phân công và lưu các phân công hợp lệ.
  3. Danh sách nhân sự lớp hiển thị các giáo viên và trợ giảng cùng thời hạn, trạng thái phân công tương ứng.
- **Kết quả:** Lớp có danh sách nhiều giáo viên và nhiều trợ giảng được quản lý độc lập.
- **Tiêu chí nghiệm thu:**
  - Tạo được ít nhất hai phân công giáo viên và hai phân công trợ giảng cho những người khác nhau trong cùng một lớp với thời hạn chồng nhau.
  - Thêm nhân sự mới không làm thay đổi phân công đang tồn tại.
  - Kết thúc phân công của một người không kết thúc phân công của người khác.
- **Quyền công bố:** Mọi giáo viên đang được phân công có hiệu lực đều được công bố/hủy công bố toàn bộ điểm và nhận xét trong lớp, không phụ thuộc người tạo; không yêu cầu chỉ định một giáo viên duyệt riêng. Admin vẫn có quyền này theo phần A–B.
- **Quy tắc vai trò:** Một người chỉ có một vai trò trong cùng lớp tại cùng thời điểm; chặn phân công giáo viên và trợ giảng có thời hạn chồng nhau cho cùng người/lớp. Vai trò tại các lớp khác có thể khác nhau.

#### CLASS-04. Chuyển lớp và học lại

- **Quyền:** Admin/Receptionist. User không chuyển lớp, học lại hoặc thêm lại; quyền sửa hồ sơ/lần tham gia tại STU-04/STU-03 không cấp quyền tạo hồ sơ hoặc lần tham gia mới.
- **Chuyển lớp:** Ghi ngày nghỉ lần đầu ở nguồn hoặc dùng ngày đã lưu; thêm lần tham gia ở đích với ngày vào hợp lệ. Nguồn và đích cùng thành công/thất bại; không chuyển tiền, điểm hoặc nhận xét sang lớp đích.
- **Học lại thông thường:** Nếu hồ sơ học sinh–lớp chưa xóa, tạo lần tham gia mới trong hồ sơ đó; không chồng thời gian, không sửa ngày cũ và không phát sinh trùng học phí cùng hồ sơ/tháng hoặc kỳ.
- **Thêm lại sau xóa hồ sơ tại lớp:** Tạo hồ sơ mới và khoản phải thu mới theo XLS-02/FEE-07, kể cả cùng tháng/kỳ đã thu ở hồ sơ cũ. Giữ các khoản và lần thu của hồ sơ cũ riêng; không tự coi khoản mới là đã thu hoặc chuyển tiền cũ sang.
- **Học vụ:** Kết quả duy nhất theo học sinh/bài kiểm tra; nhận xét duy nhất theo học sinh/bài hoặc học sinh/đợt. Không sao chép/nhân đôi kết quả khi đổi lần tham gia hoặc thêm lại hồ sơ lớp.
- **Lịch sử/tra cứu:** Lịch sử lớp nguồn và các hồ sơ/lần tham gia cũ vẫn được giữ, đọc đúng quyền. Phụ huynh xem hợp các khoảng đã tham gia theo PORTAL-02 khi học sinh còn được tra cứu trong lớp.
- **Nghiệm thu:** Chuyển lớp không mất dữ liệu nguồn, một lỗi hủy cả chuyển. Nghỉ rồi học lại trong hồ sơ cũ không thu trùng; xóa hồ sơ rồi thêm lại có khoản mới và vẫn truy vết được lịch sử cũ.

#### CLASS-05. Đóng, mở lại, xóa mềm và khôi phục lớp

- **Quyền:** Chỉ Admin/Receptionist; giáo viên/trợ giảng không quản trị vòng đời lớp.
- **Đóng đột xuất:** Lưu thời điểm đóng, chặn nhập học, thêm buổi và phát sinh nghĩa vụ cho thời gian đóng. Xóa khỏi lịch sử dụng toàn bộ buổi chưa bắt đầu tại lúc xác nhận, kể cả buổi đổi lịch/bù; lưu bản ghi buổi với lý do Đóng lớp và cấu hình cần tạo lại. Buổi đã bắt đầu, điểm danh, học vụ và khoản đã phát sinh giữ nguyên.
- **Mở lại:** Xem trước các buổi tương lai từ thời điểm mở tới ngày kết thúc lớp, dựa trên lịch tuần và các ngoại lệ/đổi lịch/buổi bù đã lưu. Khôi phục hoặc tạo lại đúng một buổi cho mỗi lịch thực tế; bỏ các buổi đã qua trong thời gian đóng. Buổi nghỉ thủ công hoặc nghỉ lễ không tự thành buổi học. Không nhân đôi buổi đã có.
- **Xung đột khi mở:** Kiểm tra toàn bộ phòng và ngày lễ; trùng phòng chặn mở, cho Admin/Receptionist sửa phương án buổi tương lai ở bước xem trước rồi xác nhận lại. Trùng giờ nhân sự chỉ cảnh báo. Kiểm tra và cập nhật cùng audit là nguyên khối; lỗi giữ lớp Đóng và không tạo lịch dở dang.
- **Học sinh/phân công:** Đóng không tự ghi ngày nghỉ hoặc kết thúc phân công. Mốc ngày tiếp tục có hiệu lực; khoảng đã hết hạn không tự sống lại khi mở/gia hạn, theo STU-03/CLASS-03. Người có quyền hiện hành vẫn sửa lịch sử của lớp đóng đúng các khóa nghiệp vụ.
- **Tài chính:** Không đổi khoản đã phát sinh/đã thu vì đóng/mở. Khi mở, tạo khoản tháng/kỳ hiện tại nếu giao với khoảng đang tham gia và còn thiếu; không tạo khoản cho tháng/kỳ nằm trọn trong khoảng đóng. Không tự tính theo số buổi/ngày; khoản điều chỉnh do Admin cấu hình theo FEE-04.
- **Xóa lớp:** Xóa mềm sau bước xem ảnh hưởng/xác nhận, ghi thời điểm/lý do. Gỡ buổi chưa bắt đầu như khi đóng; lưu toàn bộ dữ liệu quá khứ và tài chính. Chặn tra cứu phụ huynh, quyền thao tác của User và phát sinh buổi/khoản mới cho thời gian lớp lưu trữ. Không xóa dây chuyền học sinh, nhân sự hoặc kết quả học vụ; không tự xóa vĩnh viễn lớp sau 60 ngày.
- **Đăng ký/công nợ khi xóa:** Hủy các đăng ký chưa bắt đầu bằng sự kiện lưu trữ; kết thúc khoảng đang hiệu lực tại thời điểm xóa, giữ ngày đã khóa. Khoản nợ đã phát sinh tiếp tục được Admin/Receptionist xem/thu từ tài chính; không chặn xóa mềm chỉ vì có nợ. Nghĩa vụ tương lai chưa thu không còn đối tượng áp dụng được đánh dấu hủy, giữ bản ghi; khoản đã thu vẫn có hiệu lực.
- **Khôi phục:** Không giới hạn 60 ngày; dùng lớp gốc, đưa về Đóng để người quản lý xem trước và Mở lại. Giữ các khoảng kết thúc/hủy do xóa; học sinh muốn tham gia tiếp cần lần tham gia mới. Phân công còn hạn chỉ cấp quyền lại khi lớp không còn xóa; không gia hạn phân công hết hạn. Liên kết giữ định danh và lựa chọn bật/tắt trước khi xóa, chỉ dùng lại sau Mở lại; không tự reroll.
- **Nghiệm thu:** Đóng/xóa giữa ngày giữ nguyên buổi đã bắt đầu và toàn bộ quá khứ; buổi tương lai không chiếm phòng. Mở lại khôi phục đúng phần tương lai sau kiểm tra, không tạo bù thời gian đóng/xóa. Hồ sơ lớp, học vụ và tài chính vẫn còn sau 60 ngày; chỉ audit/thông báo chịu thời hạn riêng.
- **Điều kiện mở lại:** Ngày kết thúc chưa qua; nếu đã qua, Admin/Receptionist phải gia hạn hợp lệ trước. Không mở bằng cách đổi lùi ngày hoặc tạo lại các buổi đã qua.

### C.5. Danh mục, địa điểm và phòng học

#### CAT-01. Danh mục môn và khối

- **Quyền:** Chỉ Admin tạo/sửa/xóa mềm/khôi phục; Receptionist chọn khi quản lý lớp. User chỉ đọc theo chức năng liên quan.
- **Dữ liệu:** Tên bắt buộc, tối đa 100 ký tự; tên chuẩn hóa theo STU-04 phải duy nhất trong từng loại môn hoặc khối, kể cả bản lưu trữ. Trùng bản đã xóa thì khôi phục thay vì tạo mới.
- **Sắp xếp mặc định (bổ sung theo yêu cầu 30/10/2026):** So số ký tự của tên hiển thị, tên ngắn hơn đứng trước; nếu bằng nhau, so từ điển theo khóa tên chuẩn hóa, rồi tên hiển thị/ID để ổn định. Áp dụng cả danh mục môn, khối, địa điểm và phòng; phòng so tên trước, không nhóm địa điểm trước. Ví dụ: Lớp 6 → Lớp 7 → Lớp 10 → Lớp 11.
- **Xóa:** Xóa mềm dù đã có lớp sử dụng; ẩn khỏi lựa chọn mới, giữ tham chiếu và tên lịch sử của lớp cũ. Không xóa lớp hoặc học vụ. Khôi phục dùng lại định danh cũ.
- **Nghiệm thu:** Chỉ Admin ghi được; lớp dùng môn/khối đã lưu trữ vẫn xem lịch sử đúng tên; tạo lớp mới không chọn được bản lưu trữ. Mọi thay đổi có audit.

#### SCHED-03. Danh mục địa điểm có thể mở rộng

- **Mục đích:** Quản lý nhiều địa điểm của cùng trung tâm mà không cố định Tòa A/Tòa B trong thiết kế.
- **Quyền quản lý:** Admin và Receptionist được thêm/sửa/xóa địa điểm khi thỏa điều kiện nghiệp vụ. Giáo viên và trợ giảng không có quyền quản lý danh mục địa điểm; backend kiểm tra quyền kể cả với yêu cầu gọi trực tiếp API.
- **Quy tắc nghiệp vụ:**
  - Địa điểm là dữ liệu danh mục, có định danh riêng; mỗi phòng tham chiếu địa điểm, không lưu vị trí bằng một bộ giá trị cố định trong mã nguồn.
  - Tòa A và Tòa B là hai bản ghi ban đầu; có thể bổ sung địa điểm khác mà không thay đổi mã nguồn hoặc cấu trúc dữ liệu.
  - Danh sách chọn địa điểm của phòng và bộ lọc lịch được lấy từ danh mục, không giới hạn hai tòa.
  - Kiểm tra trùng phòng dựa vào định danh phòng tại địa điểm; cùng tên phòng ở các địa điểm khác nhau không bị coi là cùng phòng.
  - Các địa điểm dùng chung dữ liệu quản lý và phân quyền theo A.2; không tách quyền theo địa điểm.
- **Tiêu chí nghiệm thu:** Bổ sung được địa điểm thứ ba, tạo phòng thuộc địa điểm đó và sử dụng trong lịch; không cần sửa mã nguồn, vẫn kiểm tra trùng phòng đúng.
- **Tiêu chí nghiệm thu phân quyền:** Admin và Receptionist thực hiện được các thao tác quản lý địa điểm; giáo viên và trợ giảng bị từ chối trên giao diện và API. Thay đổi thành công được audit theo AUD-01.
- **Quy tắc xóa:** Xóa mềm/ngừng sử dụng khi không còn buổi đang diễn ra hoặc lịch tương lai theo SCHED-05; giữ lịch sử phòng/địa điểm.
- **Thông tin địa điểm:** Tên và địa chỉ; không hard-code Tòa A/B. Admin và Receptionist quản lý theo quyền tại SCHED-03.

#### SCHED-02. Phòng học và kiểm tra trùng phòng

- **Mục đích:** Gắn phòng học với lịch lớp và phát hiện việc nhiều lớp sử dụng cùng phòng trong thời gian chồng nhau.
- **Phạm vi:** Quản lý phòng học, chọn phòng cho lịch học và kiểm tra trùng phòng giữa các lớp.
- **Quyền quản lý danh mục phòng:** Admin và Receptionist được tạo/sửa/xóa phòng học. Giáo viên và trợ giảng không được tạo/sửa/xóa danh mục phòng. Giáo viên đủ quyền vẫn được chọn phòng khi quản lý lịch lớp theo SCHED-01.
- **Thông tin phòng:**

  | Trường | Nội dung |
  | --- | --- |
  | Tên phòng | Tên hiển thị của phòng học. |
  | Địa điểm | Tham chiếu một địa điểm trong danh mục cấu hình, xác định phòng thuộc cơ sở nào; không dùng danh sách tên cố định trong mã nguồn. |

  Chỉ quản lý hai trường trên; không bổ sung sức chứa hoặc ghi chú phòng.
- **Quy tắc nghiệp vụ:**
  - Khi chọn hoặc hiển thị phòng trong lịch, thể hiện cả tên phòng và địa điểm để phân biệt phòng giữa các địa điểm.
  - Kiểm tra trùng theo đúng phòng tại đúng địa điểm; phòng cùng tên ở Tòa A và Tòa B là hai phòng khác nhau, không bị coi là trùng chỉ vì trùng tên.
  - Mỗi buổi học sử dụng thông tin phòng, giờ bắt đầu và giờ kết thúc để kiểm tra trùng với các buổi khác trong cùng ngày.
  - Kiểm tra theo các buổi thực tế trong thời gian hoạt động của lớp, bao gồm lịch định kỳ, buổi đổi lịch và buổi bù; không chỉ so sánh tên thứ trong tuần.
  - Đổi ngày/giờ/phòng một buổi hoặc thay đổi lịch tuần phải kiểm tra lại trùng phòng.
  - Khi phát hiện trùng phòng, chặn lưu và chỉ rõ lớp, buổi, phòng cùng khoảng thời gian bị trùng; người dùng phải đổi phòng hoặc thời gian để tiếp tục.
  - Không có lựa chọn bỏ qua cảnh báo để lưu, kể cả với Admin. Backend kiểm tra trước khi lưu; hai yêu cầu đặt phòng đồng thời không được tạo lịch trùng.
  - Yêu cầu bị chặn giữ nguyên lịch hiện có và không tạo audit thay đổi dữ liệu thành công.
  - Buổi đã ghi nghỉ không chiếm phòng trong khoảng thời gian đó.
  - Thay đổi phòng hoặc lịch thành công được audit theo AUD-01.
- **Tiêu chí nghiệm thu:**
  - Tạo/sửa được phòng với tên và một địa điểm hợp lệ từ danh mục; không yêu cầu sức chứa hay ghi chú. Thêm địa điểm mới không cần sửa mã nguồn hoặc cấu trúc dữ liệu.
  - Chọn và hiển thị được tên phòng kèm địa điểm trong lịch tuần và từng buổi cụ thể.
  - Hai phòng cùng tên ở hai tòa không gây báo trùng; cùng một phòng ở cùng tòa với thời gian chồng nhau vẫn bị chặn.
  - Phát hiện hai lớp đặt cùng phòng với khoảng giờ chồng nhau trong cùng ngày.
  - Phát hiện trùng khi đổi lịch hoặc thêm buổi bù và từ chối lưu; lịch cũ giữ nguyên.
  - Admin, Receptionist và giáo viên đều không thể bỏ qua kiểm tra trùng phòng, kể cả gọi trực tiếp API.
  - Không báo trùng chỉ vì cùng thứ/giờ nếu thời gian hoạt động của hai lớp không giao nhau.
  - Admin và Receptionist tạo/sửa/xóa được phòng khi thỏa điều kiện nghiệp vụ; giáo viên và trợ giảng bị từ chối thao tác quản lý danh mục phòng trên giao diện và API.
- **Quy tắc nghiệp vụ:** Tên phòng duy nhất trong cùng địa điểm; khác địa điểm được trùng tên. Lịch cho phép không chọn phòng, trường hợp đó không kiểm tra trùng phòng nhưng vẫn cảnh báo trùng giờ nhân sự.
- **Tên phòng:** Bắt buộc, tối đa 200 ký tự; áp cùng chuẩn hóa tên khi kiểm tra duy nhất trong địa điểm. Đổi tên/phòng/địa điểm giữ phiên bản tên hiển thị lịch sử của buổi đã bắt đầu, không viết lại vị trí quá khứ.

#### SCHED-05. Xóa mềm hoặc ngừng sử dụng phòng và địa điểm

- **Quyền:** Admin/Receptionist. Tên và địa chỉ địa điểm bắt buộc; tên tối đa 200, địa chỉ tối đa 500 ký tự. Tên địa điểm chuẩn hóa duy nhất; tên phòng chuẩn hóa duy nhất trong địa điểm, kể cả bản lưu trữ.
- **Điều kiện:** Chỉ ngừng sử dụng/xóa mềm khi không còn buổi đang diễn ra hoặc chưa bắt đầu sử dụng phòng/địa điểm đó. Kiểm tra cả lịch thực tế, ngoại lệ/bù và lịch tuần còn sinh buổi tương lai; chỉ rõ các buổi/lịch cần đổi trước, không tự hủy/chuyển để vượt điều kiện.
- **Địa điểm có phòng:** Chỉ xóa mềm địa điểm sau khi mọi phòng không có buổi/lịch tương lai hoặc đang diễn ra; đánh dấu lưu trữ các phòng trong cùng thao tác, giữ định danh và lịch sử. Không cho tạo phòng mới thuộc địa điểm lưu trữ.
- **Sau thao tác:** Không chọn mục ngừng sử dụng/lưu trữ cho lịch mới; buổi quá khứ vẫn đúng thông tin phòng/địa điểm tại lúc học. Khôi phục dùng định danh cũ, không tự dựng lại lịch đã hủy.
- **Trùng giờ:** Các buổi chiếm phòng dùng khoảng [bắt đầu, kết thúc); hai buổi liền giờ được phép. Buổi nghỉ, bị gỡ do đóng/xóa lớp không chiếm phòng. Chặn trùng tại backend và khi hai yêu cầu đồng thời; Admin không được bỏ qua.
- **Nghiệm thu:** Không xóa/ngừng phòng đang có buổi hoặc địa điểm còn lịch tương lai; không xóa dây chuyền buổi cũ/điểm danh; khôi phục không tạo lịch trùng, mọi thay đổi có audit.

### C.6. Lịch học, buổi học và nghỉ lễ

#### SCHED-01. Lịch cố định hằng tuần và ngoại lệ từng buổi

- **Mục đích:** Quản lý lịch học định kỳ của lớp và các thay đổi thực tế cho từng buổi.
- **Người được thực hiện:** Admin, Receptionist hoặc giáo viên có phân công đang hiệu lực trong lớp được tạo/sửa lịch, đổi từng buổi, ghi nghỉ và thêm buổi học bù. Trợ giảng và User không có phân công giáo viên đang hiệu lực trong lớp không được quản lý lịch.
- **Phạm vi:**
  - Lớp có lịch cố định theo thứ và giờ hằng tuần.
  - Cho phép đổi lịch từng buổi, ghi nhận buổi nghỉ và tổ chức học bù.
- **Dữ liệu nghiệp vụ:** Lịch tuần của lớp gồm thứ, giờ bắt đầu, giờ kết thúc và phòng học; ngày mở/kết thúc lớp; các buổi học cụ thể với ngày, giờ và phòng tương ứng; các thay đổi lịch từng buổi.
- **Quy tắc nghiệp vụ:**
  - Buổi học cụ thể được xác định theo lịch tuần trong thời gian hoạt động của lớp.
  - Đổi lịch một buổi chỉ tác động buổi được chọn, không tự đổi toàn bộ lịch tuần.
  - Ghi nhận buổi nghỉ riêng với trạng thái vắng của học sinh; nghỉ cả buổi không đồng nghĩa mọi học sinh đều vắng.
  - Buổi học bù có ngày/giờ/phòng cụ thể để theo dõi, điểm danh; không bắt buộc liên kết một buổi nghỉ.
  - Lịch buổi học được sử dụng cho điểm danh và mẫu in điểm danh tháng đã nêu tại phần B.
  - Tạo/sửa lịch, đổi buổi, ghi nghỉ và thêm buổi bù thành công được audit; nếu không ghi được audit thì không hoàn tất thay đổi.
- **Tiêu chí nghiệm thu:**
  - Lưu được lịch theo thứ/giờ hằng tuần và xác định được các buổi học tương ứng.
  - Đổi được một buổi mà không làm thay đổi lịch tuần hoặc các buổi khác.
  - Ghi nhận được buổi nghỉ và buổi học bù, phân biệt với việc học sinh vắng một buổi.
  - Điểm danh và mẫu in sử dụng lịch buổi đã điều chỉnh.
  - Admin và Receptionist quản lý được lịch các lớp; giáo viên chỉ quản lý lịch của lớp đang có phân công giáo viên có hiệu lực.
  - Trợ giảng hoặc User không có phân công giáo viên đang hiệu lực trong lớp bị từ chối thao tác quản lý lịch trên giao diện và API.
- **Lịch:** Cho nhiều buổi/tuần và nhiều buổi/ngày; phòng được để trống. Điều chỉnh lịch tuần có hiệu lực từ chính ngày áp dụng, không hồi tố ngày đã qua hoặc viết lại lịch trước mốc đó. Ngày nghỉ lễ chung theo SCHED-06.
- **Điểm danh:** Chỉ sau giờ bắt đầu buổi theo ATT-01; không có điểm danh buổi tương lai.
- **Mốc áp dụng:** Từ chính ngày được chọn, không cho ngày áp dụng đã qua; giữ nguyên các buổi trước ngày áp dụng. Không được tạo lại lịch sử đã điểm danh qua việc sửa lịch tuần.
- **Buổi đã bắt đầu:** Không được đổi giờ, đổi phòng hoặc hủy buổi đã bắt đầu, kể cả qua sửa lịch tuần hoặc áp dụng nghỉ lễ; kiểm tra tại backend và giữ nguyên buổi nếu bị chặn.
- **Học bù và học phí:** Không cho tạo hoặc chuyển buổi bù vào ngày nghỉ lễ. Chuyên cần, buổi nghỉ, nghỉ lễ và buổi bù không tự động thay đổi học phí; điều chỉnh tiền thực hiện thủ công theo FEE-04.
- **Giờ/ngày hợp lệ:** Buổi nằm trong ngày mở/kết thúc lớp, bắt đầu và kết thúc cùng ngày, giờ kết thúc lớn hơn bắt đầu. Không tạo/khôi phục/chuyển buổi vào thời điểm đã bắt đầu hoặc đã qua; áp dụng cả ngày hôm nay với giờ đã qua. Đổi lịch tuần giữ các buổi đã bắt đầu và mọi ngoại lệ không thuộc phạm vi thay đổi; lớp Đóng/xóa mềm không nhận buổi mới.
- **Đóng/mở:** Các buổi tương lai bị gỡ do đóng/xóa lớp có bản lưu nghiệp vụ, không chỉ trong audit; Mở lại tạo/khôi phục đúng các buổi còn ở tương lai theo CLASS-05. Buổi quá khứ không bị viết lại bởi thao tác vòng đời lớp.

#### SCHED-04. Cảnh báo trùng giờ giáo viên/trợ giảng

- **Mục đích:** Phát hiện nhân sự được phân công ở nhiều lớp có buổi học chồng giờ.
- **Quy tắc nghiệp vụ:**
  - Kiểm tra cả giáo viên và trợ giảng theo các phân công có hiệu lực vào thời gian buổi học; áp dụng giữa các lớp và giữa các địa điểm.
  - Khi trùng giờ, hiển thị cảnh báo nêu nhân sự, lớp, buổi và thời gian bị trùng; vẫn cho phép lưu nếu các điều kiện khác hợp lệ.
  - Đây là cảnh báo, không áp dụng quy tắc chặn lưu của trùng phòng. Nếu đồng thời trùng phòng thì vẫn chặn theo SCHED-02.
  - Kiểm tra khi tạo/sửa lịch tuần, đổi buổi, thêm buổi bù hoặc thay đổi phân công có ảnh hưởng đến lịch.
  - Sử dụng lịch buổi thực tế sau điều chỉnh; buổi nghỉ không tạo xung đột nhân sự.
  - Thao tác lưu thành công vẫn ghi audit theo quy tắc chung.
- **Tiêu chí nghiệm thu:** Trùng giờ giáo viên hoặc trợ giảng tạo cảnh báo và vẫn lưu được; trùng phòng vẫn bị chặn; nhân sự ở các lớp không chồng giờ không bị cảnh báo trùng.
- **Khoảng đệm:** Không áp thời gian di chuyển tự động giữa địa điểm; hai buổi liền giờ không trùng. Chỉ cảnh báo giao thời gian thực tế, không suy diễn khoảng cách hoặc bắt buộc buổi nghỉ giữa hai nơi.

#### SCHED-06. Nghỉ lễ chung và ngày áp dụng lịch tuần

- **Nghỉ lễ:** Chỉ Admin quản lý ngày nghỉ lễ chung. Khi áp dụng, hệ thống tự đánh dấu nghỉ/hủy các buổi học rơi vào ngày lễ, không đánh dấu mọi học sinh là Vắng.
- **Buổi bù:** Được tạo độc lập, không bắt buộc liên kết buổi nghỉ; vẫn kiểm tra phòng và cảnh báo nhân sự theo lịch thực tế.
- **Giới hạn:** Không tổ chức buổi bù vào ngày nghỉ lễ. Áp dụng hoặc thay đổi nghỉ lễ không được hủy/đổi buổi đã bắt đầu; nếu có buổi như vậy bị tác động, chặn lưu và thông báo các buổi cần kiểm tra.
- **Đổi lịch tuần:** Mỗi điều chỉnh có ngày áp dụng; thay lịch từ chính ngày áp dụng, không được hồi tố ngày đã qua; giữ lịch trước ngày đó để tra cứu. Không tự hủy toàn bộ lịch sử để sinh lại.
- **Điểm danh:** Không phát sinh trước giờ bắt đầu. Không xóa điểm danh đã có bằng cách áp dụng nghỉ lễ cho buổi đã bắt đầu.
- **Audit:** Ngày lễ, thay đổi lịch và các buổi chịu tác động phải truy vết được; không hoàn tất thay đổi nghiệp vụ nếu không ghi được audit.
- **Nghiệm thu:** Ngày lễ áp dụng tới các lớp; buổi nghỉ không chiếm phòng; lịch mới không viết lại lịch cũ; buổi bù không cần buổi nguồn.
- **Luồng xác nhận:** Admin xem các buổi bị tác động → xác nhận hoặc hủy → hệ thống kiểm tra lại giờ bắt đầu, đánh dấu nghỉ/hủy các buổi hợp lệ và ghi audit. Nếu bất kỳ buổi bị tác động nào đã bắt đầu, chặn toàn bộ thao tác; hủy hoặc lỗi cập nhật/audit không để lại thay đổi dở dang.
- **Nghiệm thu:** Không thể dùng nghỉ lễ để hủy buổi đã bắt đầu hoặc xóa điểm danh đã có. Nghỉ lễ không tự thay đổi điểm, bài kiểm tra hoặc học phí.
- **Bỏ ngày lễ:** Cho khôi phục buổi sau khi người có quyền xác nhận và hệ thống kiểm tra lại trùng phòng. Trùng phòng thì chặn lưu; trùng giờ nhân sự vẫn chỉ cảnh báo. Không tự lấy dữ liệu từ audit để tạo kết quả điểm danh.
- **Nghiệm thu khôi phục:** Bỏ lễ không tự phục hồi âm thầm; buổi được khôi phục đúng lịch sau xác nhận và kiểm tra. Lỗi kiểm tra/cập nhật/audit không để lại thay đổi dở dang.
- **Bỏ ngày lễ đã qua:** Giữ các buổi nghỉ trong quá khứ, không khôi phục buổi đã tới giờ bắt đầu để nhập lịch sử mới. Bỏ ngày lễ chỉ cho tạo/khôi phục các buổi còn ở tương lai sau xác nhận và kiểm tra; không tự phục hồi điểm danh từ audit.

### C.7. Chuyên cần và điểm danh

#### ATT-01. Trạng thái điểm danh theo buổi

- **Mục đích:** Ghi nhận học sinh có mặt hoặc vắng trong từng buổi học của lớp.
- **Người thực hiện:** Admin, Receptionist và User có phân công đang hiệu lực trong lớp (giáo viên hoặc trợ giảng), theo quyền điểm danh đã nêu tại phần B.
- **Giá trị:**

  | Giá trị | Ý nghĩa |
  | --- | --- |
  | Có mặt | Học sinh có tham gia buổi học. |
  | Vắng | Học sinh không tham gia buổi học. |
  | `null` | Chưa điểm danh; không phải một loại kết quả điểm danh. |

- **Quy tắc nghiệp vụ:**
  - Mỗi kết quả gắn đúng học sinh, lớp và buổi học thực tế theo lịch đã điều chỉnh.
  - Chỉ cho điểm danh sau giờ bắt đầu thực tế của buổi; backend chặn trước mốc này, không chỉ khóa giao diện. Trước lần lưu đầu, kết quả vẫn `null`; sau lưu chỉ có Có mặt/Vắng. Không hỗ trợ đặt kết quả đã lưu về `null`.
  - Không sử dụng các trạng thái riêng Đi muộn, Vắng có phép hoặc Vắng không phép.
  - Thống kê phải phân biệt Vắng và chưa điểm danh; không cộng `null` vào số lượt Vắng.
  - Trạng thái Vắng điểm danh chỉ thuộc buổi học; không tự đồng nhất với Vắng của bài kiểm tra hoặc trạng thái Nghỉ tham gia lớp.
  - Mẫu in điểm danh tháng hiển thị kết quả đã lưu tại thời điểm in; ô có giá trị `null` để trống.
  - Thay đổi điểm danh thành công được audit; không ghi được audit thì không hoàn tất thay đổi.
- **Tiêu chí nghiệm thu:**
  - Ghi nhận được Có mặt hoặc Vắng; dữ liệu chưa điểm danh giữ `null`.
  - Giá trị `null` không bị tự chuyển thành Vắng trên giao diện, thống kê hoặc bản in; chỉ được ghi nhận Có mặt/Vắng khi lưu điểm danh theo luồng tại ATT-01.
  - Điểm danh của một buổi không tự đổi kết quả bài kiểm tra hay trạng thái tham gia lớp.
- **Luồng điểm danh:**
  1. Người có quyền mở buổi học và danh sách học sinh cần điểm danh.
  2. Người dùng đánh dấu các học sinh Vắng; không cần đánh dấu riêng từng học sinh Có mặt.
  3. Khi người dùng lưu điểm danh, hệ thống ghi Vắng cho học sinh đã đánh dấu và Có mặt cho các học sinh còn lại trong danh sách điểm danh của buổi.
  4. Nếu không có học sinh vắng, người dùng vẫn lưu để xác nhận tất cả Có mặt; việc chỉ mở màn hình không tự ghi nhận điểm danh.
  5. Sau khi lưu, người có quyền có thể mở lại, điều chỉnh danh sách Vắng và lưu lại. Học sinh được bỏ đánh dấu Vắng chuyển thành Có mặt; học sinh mới đánh dấu chuyển thành Vắng.
  6. Lưu thành công ghi audit; lỗi ghi dữ liệu hoặc audit giữ nguyên kết quả trước lần lưu đó.
- **Quy tắc phạm vi lưu:** Chỉ áp dụng cho danh sách học sinh thuộc buổi đang điểm danh; không tự đổi kết quả các buổi khác hoặc các học sinh ngoài danh sách đó.
- **Tiêu chí nghiệm thu luồng:** Trước lần lưu đầu vẫn là `null`; lưu danh sách Vắng sẽ ghi Có mặt cho các học sinh còn lại; lưu danh sách không có học sinh Vắng ghi tất cả Có mặt; cho phép điều chỉnh sau khi lưu và audit ghi đúng trước/sau.
- **Danh sách học sinh điểm danh:**
  - Xác định theo ngày diễn ra thực tế của buổi học, bao gồm ngày mới nếu buổi đã đổi lịch hoặc buổi bù.
  - Chỉ gồm học sinh đã vào lớp và chưa nghỉ tại ngày đó; không đưa học sinh chưa đến ngày vào lớp hoặc đã nghỉ trước buổi vào danh sách.
  - Khi xem hoặc sửa điểm danh buổi cũ, đối chiếu thời gian tham gia tại ngày của buổi, không chỉ lấy danh sách học sinh đang học hiện tại.
  - Không ghi Có mặt hoặc Vắng cho học sinh ngoài danh sách đủ điều kiện của buổi; việc không đủ điều kiện không được tính là Vắng.
  - Hồ sơ tại lớp xóa mềm tuân theo XLS-02; hồ sơ tổng xóa mềm theo STU-01. Giữ kết quả điểm danh đã có và xét mốc sự kiện kết thúc khi đọc lịch sử.
- **Tiêu chí nghiệm thu danh sách:** Học sinh vào lớp sau buổi hoặc đã nghỉ trước buổi không xuất hiện trong danh sách; buổi cũ vẫn xét đúng thời gian tham gia dù trạng thái hiện tại đã đổi; lưu điểm danh không tác động học sinh ngoài phạm vi.
- **Thời gian và sửa:** Chỉ điểm danh sau giờ bắt đầu; sau khi lưu không giới hạn thời gian sửa nhưng người thao tác vẫn phải có quyền hiện hành. Không hỗ trợ đặt lại `null`.
- **Ngày nghỉ:** Học sinh chỉ đủ điều kiện khi ngày vào lớp ≤ ngày buổi học < ngày nghỉ, hoặc chưa có ngày nghỉ; ngày nghỉ là ngày sau ngày học cuối.
- **Khóa kết quả:** Một kết quả theo học sinh/buổi học, không tạo bản sao do đổi hồ sơ hoặc lần tham gia. Khi đối chiếu thời gian, dùng khoảng thực tế đã cắt bởi sự kiện xóa mềm; buổi đã bắt đầu trước sự kiện vẫn giữ điểm danh.
- **Ghi chú:** Tùy chọn, văn bản thuần tối đa 1.000 ký tự theo học sinh/buổi. Sửa cùng kết quả điểm danh và lưu phiên bản lịch sử; không hiển thị ghi chú nội bộ cho phụ huynh.

### C.8. Bài kiểm tra, thang điểm và điểm thành phần

#### TEST-05. Thông tin bài kiểm tra

- **Mục đích:** Lưu thông tin nhận diện và cấu hình đánh giá của từng bài kiểm tra trong lớp.
- **Người thực hiện:** Admin hoặc giáo viên/trợ giảng có phân công đang hiệu lực trong lớp theo quyền học vụ. Receptionist không tạo/sửa bài kiểm tra.
- **Các trường:**

  | Trường | Nội dung |
  | --- | --- |
  | Tên bài | Bắt buộc. Tên hiển thị của bài kiểm tra. |
  | Ngày kiểm tra | Bắt buộc. Ngày thực hiện bài kiểm tra. |
  | Mô tả | Tùy chọn. Nội dung mô tả bài kiểm tra; cho phép để trống. |
  | Loại đánh giá | Bắt buộc. Số, phân số, chữ hoặc IELTS theo TEST-01. |
  | Cấu hình đánh giá | Bắt buộc theo loại và chế độ nhập. Cấu hình riêng hoặc khởi tạo từ template TEST-02 rồi chỉnh riêng cho bài; gồm điểm tối đa, số câu, bộ mức chữ, các phần hoặc kỹ năng IELTS và chế độ nhập tương ứng. |

- **Quy tắc nghiệp vụ:**
  - Bài kiểm tra thuộc một lớp; thông tin bài dùng chung cho các kết quả học sinh của bài đó.
  - Nhập và kiểm tra kết quả theo cấu hình của bài, không dùng cấu hình của bài khác.
  - Chọn template là tùy chọn, không phải điều kiện để tạo bài. Cấu hình riêng hoặc sửa bản sao từ template không tạo/sửa template trong thư viện. Thay đổi cấu hình sau khi có kết quả tuân theo TEST-03; sửa template không tự thay đổi bài cũ.
  - Tạo/sửa thông tin bài thành công được ghi audit theo AUD-01.
- **Tiêu chí nghiệm thu:** Tạo được bài với mô tả để trống khi các thông tin bắt buộc hợp lệ; thiếu tên, ngày kiểm tra, loại đánh giá hoặc cấu hình bắt buộc thì từ chối tạo và chỉ rõ thông tin thiếu. Hỗ trợ số/phân số/chữ và IELTS, tạo không dùng template hoặc chỉnh bản sao từ template; nhập kết quả theo đúng cấu hình đã lưu của bài.
- **Quyền sửa thông tin:** Cho phép sửa tên, ngày kiểm tra và mô tả khi đã có kết quả công bố; không làm thay đổi trạng thái công bố hoặc kết quả. Thay đổi cấu hình đánh giá vẫn theo TEST-03.
- **Khóa/mốc:** Mỗi học sinh có tối đa một kết quả và một nhận xét cho một bài, không phụ thuộc hồ sơ/lần tham gia. Nhập cho học sinh có ngày bài giao với ít nhất một khoảng tham gia trong lớp, kể cả lịch sử; không lấy danh sách Đang học hiện tại để thay điều kiện theo ngày.
- **Ngày bài:** Nằm trong thời gian lớp đã có hiệu lực tại ngày bài; được sửa tên/ngày/mô tả khi đã công bố nhưng không cho chuyển ngày ra ngoài hợp khoảng tham gia của bất kỳ học sinh đang có kết quả/nhận xét. Chặn cả thay đổi và chỉ rõ học sinh bị ảnh hưởng, không tự xóa hoặc hủy công bố.
- **Tên:** Cho trùng tên bài/đợt trong cùng lớp, luôn dùng định danh và ngày để phân biệt; không dùng tên làm khóa Excel. Học sinh Vắng cũng có kết quả theo cùng khóa học sinh/bài.

#### TEST-01. Cấu hình thang điểm theo từng bài kiểm tra

- **Mục đích:** Hỗ trợ cách đánh giá khác nhau cho từng bài kiểm tra.
- **Quyền thao tác:** Admin và giáo viên/trợ giảng có phân công đang hiệu lực được cấu hình bài và nhập kết quả theo TEST-05 và ACAD-01. Chỉ Admin quản lý thư viện template theo TEST-02; quyền sửa cấu hình một bài không cấp quyền lưu template.
- **Cấu hình:** Mỗi bài kiểm tra có cấu hình đánh giá riêng, hỗ trợ các loại:

  | Loại | Cấu trúc kết quả | Cấu hình theo bài |
  | --- | --- | --- |
  | Số | Điểm số học sinh đạt được. | Điểm tối đa riêng, ví dụ 10, 20 hoặc 100; không cố định thang 10. |
  | Phân số | Số câu đúng / tổng số câu. | Tổng số câu của bài kiểm tra. |
  | Chữ | Một mức đánh giá trong danh sách của bài. | Bộ mức cấu hình riêng hoặc sao chép từ template chung theo TEST-02. |
  | IELTS | Điểm band theo các kỹ năng được chọn; Overall khi đủ bốn kỹ năng. | L/R/W/S tùy chọn, chế độ nhập riêng từng kỹ năng nhưng thống nhất cho cả bài; quy tắc IELTS bên dưới. |

- **Trạng thái Vắng:**
  - Có trạng thái riêng Vắng, nghĩa là học sinh không thực hiện bài kiểm tra đó.
  - Vắng không phải điểm 0, phân số 0/tổng số câu hoặc mức Chưa đạt; không quy đổi tự động thành các giá trị này.
  - Trạng thái Vắng độc lập với loại đánh giá, áp dụng cả số/phân số/chữ và IELTS. Vắng của cả bài không được chuyển thành band 0 hoặc các điểm thành phần giả.
  - Vắng không đồng nghĩa chưa nhập kết quả. Được công bố Vắng như một kết quả xác định của học sinh trong bài kiểm tra, theo quyền và phạm vi công bố điểm tại ACAD-01.
  - Khi đã công bố, trang phụ huynh hiển thị “Vắng – Không thực hiện bài kiểm tra”; khi chưa công bố hoặc đã hủy công bố, ẩn kết quả Vắng như các kết quả chưa công bố khác.
  - Vắng không yêu cầu có điểm tổng hoặc đủ điểm thành phần để được công bố; không tạo điểm 0 hoặc các điểm thành phần giả để hoàn tất dữ liệu.
  - Khi công bố điểm cả lớp, học sinh Vắng được tính là đã có kết quả hợp lệ và có thể được công bố; không nằm trong danh sách thiếu điểm chỉ vì không có giá trị điểm.
  - Nếu Vắng đang công bố, phải chủ động hủy công bố trước khi sửa hoặc xóa kết quả, tương tự các kết quả khác.
- **Quy tắc áp dụng:**
  - Các bài kiểm tra trong cùng lớp có thể sử dụng loại thang điểm hoặc điểm tối đa khác nhau.
  - Nhập kết quả và đồng bộ Excel phải kiểm tra theo đúng loại thang điểm của bài; không tự quy đổi sang loại khác.
  - Với thang số, cho phép tối đa hai chữ số thập phân, ví dụ 8,25; áp dụng cho điểm tổng nhập trực tiếp và điểm thành phần. Chấp nhận số nguyên hoặc một chữ số thập phân, không bắt buộc người dùng nhập đủ hai chữ số.
  - Giá trị thang số có nhiều hơn hai chữ số thập phân được báo lỗi, không tự làm tròn khi nhập; áp dụng thống nhất trên giao diện, API và Excel.
  - Điểm thang số phải nằm trong khoảng từ 0 đến mức tối đa, bao gồm hai đầu mút. Với nhập trực tiếp, kiểm tra theo điểm tối đa của bài; với điểm thành phần, kiểm tra theo mức tối đa của từng phần.
  - Không cho nhập điểm âm hoặc điểm vượt tối đa để tính điểm thưởng; không tự cắt giá trị về giới hạn. Giao diện/API báo lỗi; Excel có giá trị ngoài giới hạn chặn toàn bộ lần đồng bộ.
  - Khi cộng các điểm thành phần hợp lệ, điểm tổng giữ độ chính xác tới hai chữ số thập phân, không phát sinh sai số hiển thị do phép cộng.
  - Với phân số, tổng số câu phải là số nguyên dương; số câu đúng là số nguyên từ 0 đến tổng số câu.
  - Với thang chữ, chỉ chấp nhận giá trị thuộc danh sách mức đánh giá của bài.
  - Kết quả đã công bố vẫn tuân theo ACAD-01: phải chủ động hủy công bố trước khi sửa/xóa, kể cả đổi kết quả sang Vắng hoặc ngược lại.
  - Thay đổi dữ liệu thành công được audit theo AUD-01.
- **Tiêu chí nghiệm thu:**
  - Tạo và nhập được kết quả cho bài thang số, phân số và chữ trong cùng lớp.
  - Thang số lưu đúng các giá trị như 8,25, 8,5 hoặc 8; từ chối giá trị có hơn hai chữ số thập phân, kể cả qua Excel.
  - Tổng các phần 1,25 và 2,10 cho kết quả 3,35.
  - Bài tối đa 10 chấp nhận 0 và 10, từ chối điểm âm hoặc lớn hơn 10. Phần tối đa 3 từ chối điểm lớn hơn 3, dù tổng điểm bài chưa vượt tối đa.
  - Lưu được Vắng như trạng thái riêng; không thay thành điểm 0 hoặc mức Chưa đạt.
  - Công bố được Vắng, kể cả bài có điểm thành phần nhưng học sinh không có điểm các phần; phụ huynh thấy đúng thông báo khi công bố và không thấy kết quả này sau khi hủy công bố.
  - Excel hỗ trợ đúng loại kết quả và Vắng; dữ liệu không hợp lệ chặn toàn bộ lần đồng bộ.
- **Đã làm rõ:** Excel dùng mẫu của từng chức năng theo XLS-06; thay thang hoặc điểm tối đa/tổng số câu phải hủy công bố, nhập lại điểm, công bố lại theo TEST-03; Vắng giữ nguyên. Các quy tắc cộng phần của thang số/phân số không áp dụng thay công thức IELTS.

**IELTS — mở rộng được người dùng chốt ngày 28/10/2026:**

- **Kỹ năng:** Bài IELTS chọn một hoặc nhiều kỹ năng Listening (L), Reading (R), Writing (W), Speaking (S), không bắt buộc đủ bốn. Kỹ năng không được chọn là Không áp dụng, không phải thiếu điểm hoặc Vắng. Không tạo bài IELTS rỗng.
- **Chế độ nhập:** Cấu hình riêng từng kỹ năng là nhập band trực tiếp hoặc nhập chi tiết; chế độ đó thống nhất cho mọi học sinh trong bài, không chọn khác nhau theo học sinh. Được lưu dữ liệu chưa đầy đủ nhưng không tự điền 0 hoặc tự chuyển chế độ để hoàn tất. Chuyển chế độ sau khi có kết quả theo TEST-03.
- **L/R:** Chế độ chi tiết lưu số câu đúng và band do người dùng nhập; cấu hình số câu tối đa nguyên dương theo bài. Số câu đúng là số nguyên từ 0 đến tối đa. Hệ thống không quy đổi số câu đúng sang band, không suy ngược số câu từ band. Chế độ trực tiếp chỉ cần band, không bắt nhập số câu đúng.
- **Writing:** Chế độ chi tiết có Task 1 và Task 2, mỗi Task gồm bốn tiêu chí trọng số bằng nhau: Task Achievement (Task 1) / Task Response (Task 2), Coherence and Cohesion, Lexical Resource, Grammatical Range and Accuracy. Mỗi Task cần đủ bốn tiêu chí để có điểm; Writing cần đủ hai Task. Chế độ trực tiếp chỉ nhập band Writing, không bắt có điểm Task/tiêu chí.
- **Công thức Writing:** `Task1 = roundBand((TA + CC1 + LR1 + GRA1) / 4)`; `Task2 = roundBand((TR + CC2 + LR2 + GRA2) / 4)`; `Writing = roundBand((Task1 + 2 × Task2) / 3)`. Làm tròn từng Task trước khi tính trọng số, đúng thứ tự người dùng yêu cầu; không thay ngầm bằng cách chỉ làm tròn ở bước cuối.
- **Speaking:** Chế độ chi tiết gồm bốn tiêu chí trọng số bằng nhau: Fluency and Coherence, Lexical Resource, Grammatical Range and Accuracy, Pronunciation. Khi đủ bốn tiêu chí, `Speaking = roundBand(tổng bốn tiêu chí / 4)`; chế độ trực tiếp chỉ nhập band Speaking. Không cho ghi đè band tự tính trong chế độ chi tiết.
- **Miền điểm/làm tròn:** Band nhập trực tiếp và điểm tiêu chí từ 0 đến 9, bước 0,5; giá trị ngoài miền hoặc sai bước bị từ chối, không tự sửa đầu vào. Với giá trị tính toán không âm, `roundBand(x) = floor(2 × x + 0,5) / 2`: phần lẻ nhỏ hơn 0,25 về số nguyên dưới; từ 0,25 đến dưới 0,75 về nửa band; từ 0,75 lên số nguyên tiếp theo. Không làm tròn trung bình về hai số lẻ trước khi áp dụng công thức. Đây là quy tắc chấm nội bộ MLedu; riêng thứ tự làm tròn Task rồi Writing được chốt theo yêu cầu người dùng, không tuyên bố đã kiểm chứng là toàn bộ quy trình chấm thi IELTS chính thức.
- **Overall:** Chỉ tính khi bài có đủ L/R/W/S và học sinh có band hợp lệ của cả bốn: `Overall = roundBand((L + R + W + S) / 4)`. Nếu bài chỉ chọn một đến ba kỹ năng thì không có Overall và không tự lấy trung bình các kỹ năng đó làm Overall. Nếu bài chọn đủ bốn nhưng thiếu band thì Overall để trống; không quy thiếu thành 0. Overall do backend tính, không nhập/ghi đè.
- **Hoàn tất/công bố:** Kết quả không Vắng hoàn tất khi tất cả kỹ năng được chọn đủ dữ liệu theo chế độ; L/R chi tiết cần cả số câu đúng và band, W/S chi tiết cần đủ tiêu chí. Bài chỉ có một đến ba kỹ năng vẫn được công bố khi đủ dữ liệu đã chọn, dù không có Overall. Bài chọn đủ bốn nhưng thiếu kỹ năng không được công bố. Vắng cả bài vẫn là kết quả hợp lệ theo quy tắc chung. Công bố theo học sinh/bài, không tạo công bố độc lập từng kỹ năng/Task/tiêu chí.
- **Hiển thị:** Khi đã công bố, phụ huynh thấy band từng kỹ năng đã chọn và Overall nếu có. Số câu đúng L/R, điểm Task và tiêu chí W/S là chi tiết chịu tùy chọn hiện/ẩn toàn bài theo TEST-04; ẩn chi tiết phải loại chúng khỏi phản hồi API. Chưa công bố thì ẩn toàn bộ kết quả; không ảnh hưởng trạng thái nhận xét.
- **Lịch sử/Excel:** Lưu điểm đầu vào, cấu hình và phiên bản công thức với kết quả; backend tính lại, không tin band tự tính/Overall do client hoặc Excel gửi. L/R vẫn dùng band do người dùng nhập. Đổi tập kỹ năng, chế độ, số câu tối đa hoặc cấu hình chấm theo TEST-03; không tính lại bài cũ chỉ vì sửa template/công thức mặc định.
- **Nghiệm thu:** Bài chỉ L/R công bố được khi đủ dữ liệu và không có Overall; bài đủ bốn thiếu S không công bố. `6,125 → 6,0`, `6,25 → 6,5`, `6,75 → 7,0`. Task 1 có `6; 6; 6; 6,5` cho 6,0; Task 2 có `6; 6; 6,5; 6,5` cho 6,5; Writing là 6,5 theo thứ tự làm tròn đã chốt. L/R nhập 30 câu đúng và band 6,5 phải giữ đúng band 6,5, không tự quy đổi. Thiếu tiêu chí khác 0; chế độ chi tiết không được ghi đè điểm tự tính; UI/API/Excel cho cùng kết quả.

#### TEST-02. Thư viện template bài kiểm tra dùng chung

- **Quyết định thay thế ngày 28/10/2026:** Gộp mẫu thang chữ vào template bài kiểm tra; bỏ chức năng thư viện mẫu thang chữ riêng theo lớp và quyền giáo viên/trợ giảng quản lý mẫu chung trước đây. Giữ nguyên mã TEST-02.
- **Quyền quản lý:** Chỉ Admin được tạo, lưu, sửa, xóa mềm/khôi phục template. Giáo viên/trợ giảng chỉ chọn dùng template khi có quyền tạo/cấu hình bài trong lớp; không lưu cấu hình bài thành template. Receptionist không được quản lý template hoặc tạo/sửa bài kiểm tra; quyền sử dụng template không mở rộng quyền học vụ.
- **Phạm vi:** Một thư viện chung toàn trung tâm, dùng cho nhiều lớp; không có quyền theo cơ sở. Template chứa tên/mô tả và cấu hình đánh giá số/phân số/chữ/IELTS, chế độ nhập, các phần/kỹ năng/tiêu chí và tùy chọn hiện chi tiết phù hợp loại bài. Không chứa ngày kiểm tra thực tế, danh sách học sinh, kết quả, nhận xét hoặc trạng thái công bố; không phải ngân hàng câu hỏi/đáp án hoặc mẫu đề thi.
- **Dùng mẫu:** Người có quyền có thể tạo bài từ đầu hoặc chọn template rồi chỉnh riêng. Mỗi bài lưu bản sao cấu hình đầy đủ, định danh/phiên bản nguồn nếu có; template chỉ là nguồn tham khảo, không liên kết cập nhật tự động. Tên/ngày thực tế của bài do người tạo nhập theo TEST-05.
- **Thang chữ:** Chọn template có bộ mức chữ hoặc cấu hình riêng bộ mức của bài; không có bước chọn mẫu thang chữ độc lập. Bộ mặc định Chưa đạt, Đạt, Tốt, Xuất sắc được cung cấp trong template chữ. Mỗi bộ có 1–20 mức, tên 1–100 ký tự và duy nhất theo chuẩn hóa tên; cho thêm/xóa/đổi tên/sắp xếp trong cấu hình được phép, không lưu bộ rỗng.
- **Phiên bản:** Sửa template tạo phiên bản mới, không đổi bất kỳ bài đã sao chép, kể cả chưa có kết quả; xóa mềm ngừng lựa chọn cho bài mới nhưng giữ lịch sử và bản sao trong bài cũ. Muốn áp dụng lại template cho một bài phải chủ động chọn lại; khi đã có kết quả áp dụng TEST-03.
- **Nguyên khối:** Quản lý template kiểm tra quyền hiện hành, phiên bản và audit trong một transaction. Lỗi audit không tạo phiên bản hoặc thay mẫu; không xóa vĩnh viễn cấu hình/lịch sử.
- **Nghiệm thu:** Chỉ Admin quản lý qua UI/API; giáo viên/trợ giảng sửa cấu hình riêng của bài mà template không đổi; cùng template dùng được ở hai lớp. Sửa/xóa template không đổi bài cũ hoặc kết quả đã công bố. Bài chọn template trước/sau lần sửa giữ được hai cấu hình khác nhau; Excel luôn đối chiếu cấu hình của bài.

#### TEST-03. Đổi cấu hình đánh giá hoặc chọn lại template khi bài đã có kết quả

- **Mục đích:** Cho phép thay đổi cách đánh giá của bài kiểm tra đã có kết quả, với yêu cầu hủy công bố và nhập lại toàn bộ kết quả.
- **Người thực hiện:** Admin hoặc giáo viên/trợ giảng có phân công đang hiệu lực trong lớp, theo quyền cấu hình và chỉnh sửa học vụ. Trợ giảng không được hủy công bố; phải chờ Admin hoặc giáo viên thực hiện nếu bài đang có điểm công bố.
- **Điều kiện trước:** Điểm của tất cả học sinh trong bài kiểm tra đã được chủ động hủy công bố hoặc chưa từng công bố; không còn điểm đang công bố trong bài.
- **Luồng chính:**
  1. Nếu bài còn điểm đang công bố, Admin hoặc giáo viên chủ động hủy công bố điểm cho toàn bộ phạm vi cần thiết.
  2. Người có quyền đổi cấu hình đánh giá hoặc chủ động chọn lại template cho bài (kể cả template chữ/IELTS).
  3. Hệ thống áp dụng thang mới; các kết quả cũ không được tiếp tục sử dụng như kết quả hợp lệ của thang mới.
  4. Người có quyền nhập lại toàn bộ kết quả theo thang mới.
  5. Admin hoặc giáo viên kiểm tra và chủ động công bố lại khi phù hợp.
- **Quy tắc nghiệp vụ:**
  - Không tự quy đổi kết quả cũ sang thang mới, kể cả đổi giữa số và phân số hoặc chọn mẫu chữ có một số mức giống mẫu cũ.
  - Nhập lại toàn bộ kết quả có điểm; giữ nguyên trạng thái Vắng vì trạng thái này không phụ thuộc thang điểm, không yêu cầu nhập lại Vắng.
  - Thao tác đổi thang/chọn lại mẫu không tự công bố kết quả.
  - Không tự sửa hoặc hủy công bố nhận xét gắn bài kiểm tra, vì nhận xét có trạng thái công bố độc lập; thao tác riêng đối với nhận xét vẫn tuân theo ACAD-01.
  - Sửa template chung không ảnh hưởng bài cũ theo TEST-02; chỉ khi chủ động áp dụng cấu hình khác/chọn lại template cho bài mới áp dụng quy trình này. Đổi tập kỹ năng, chế độ nhập hoặc số câu tối đa L/R của bài IELTS cũng là đổi cấu hình; không tự bảo lưu điểm cũ thành điểm hiện hành của cấu hình mới. Công thức IELTS tại TEST-01 là cố định, không phải trường tùy chỉnh của template/bài; phiên bản công thức chỉ để bảo toàn lịch sử. Muốn thay công thức phải có quyết định cập nhật đặc tả riêng, không cấp quyền tự đổi công thức cho người cấu hình bài.
  - Thay đổi thành công được audit với chi tiết trước/sau; lỗi ghi audit hủy toàn bộ thay đổi.
- **Xử lý lỗi:** Chặn đổi thang/chọn lại mẫu nếu còn bất kỳ điểm đang công bố trong bài hoặc người thực hiện không có quyền; không tự hủy công bố để tiếp tục.
- **Tiêu chí nghiệm thu:**
  - Cho đổi thang/chọn lại mẫu sau khi bài không còn điểm đang công bố.
  - Điểm cũ không tự trở thành kết quả theo thang mới; phải nhập lại toàn bộ điểm. Các học sinh Vắng vẫn giữ trạng thái Vắng.
  - Đổi cấu hình không tự công bố dữ liệu hoặc thay đổi trạng thái công bố nhận xét.
- **Thay đổi cấu hình:** Đổi điểm tối đa, tổng số câu hoặc cấu trúc điểm thành phần cũng áp dụng cùng quy trình: chủ động hủy công bố, nhập lại toàn bộ điểm, chủ động công bố lại; Vắng giữ nguyên.
- **Đã chốt:** Đổi chế độ tổng trực tiếp/theo phần cùng quy trình hủy công bố, nhập lại điểm, công bố lại; Vắng giữ nguyên. Điểm/cấu hình cũ được giữ thành phiên bản nghiệp vụ không thời hạn, độc lập với audit 60 ngày; không tự dùng phiên bản cũ làm kết quả hiện hành.
- **Nghiệm thu bổ sung:** Sau đổi không dùng điểm cũ tính tổng hoặc hiển thị phụ huynh; audit vẫn có dữ liệu trước thay đổi trong thời hạn lưu.

#### TEST-04. Điểm thành phần cho thang số và phân số

- **Mục đích:** Nhập kết quả theo từng phần của bài kiểm tra và kiểm soát việc công bố chi tiết điểm thành phần.
- **Phạm vi:** Quy tắc cộng tổng phần bên dưới áp dụng cho bài thang số hoặc phân số; không áp dụng cho thang chữ. IELTS có cấu trúc và công thức riêng tại TEST-01, dùng chung quyền/khóa và tùy chọn hiện/ẩn chi tiết ở mục này.
- **Chế độ nhập số/phân số:**
  - Điểm thành phần không bắt buộc. Mỗi bài thang số/phân số chọn một trong hai chế độ: nhập điểm tổng trực tiếp hoặc nhập theo các phần.
  - Chế độ nhập trực tiếp: nhập một kết quả tổng theo thang của bài, không yêu cầu tạo hoặc nhập điểm thành phần; tùy chọn hiện/ẩn thành phần không áp dụng.
  - Chế độ theo phần: cấu hình các phần và tự tính tổng theo TEST-04; không nhập hoặc ghi đè tổng độc lập.
  - Chế độ nhập được áp dụng thống nhất cho toàn bài; giao diện và Excel kiểm tra theo chế độ đã chọn.
- **Dữ liệu:** Bài kiểm tra có tổng điểm/kết quả chung và các phần; mỗi phần có tên, mức tối đa hoặc tổng số câu và kết quả của học sinh.
- **Ví dụ thang số:** Tổng tối đa 10 điểm; Phần 1 tối đa 3, Phần 2 tối đa 4, Phần 3 tối đa 3.
- **Ví dụ thang phân số:** Kết quả chung 80/90; Phần 1 đạt 20/30, Phần 2 đạt 30/30, Phần 3 đạt 30/30.
- **Quy tắc nghiệp vụ:**
  - Người có quyền nhập điểm của lớp được nhập điểm thành phần theo cấu hình từng bài.
  - Khi bài có cấu hình điểm thành phần, điểm tổng được tự tính từ các phần, không nhập hoặc ghi đè điểm tổng độc lập.
  - Thang số: cộng điểm đạt được của các phần để ra điểm tổng; tổng điểm tối đa bằng tổng mức tối đa của các phần.
  - Thang phân số: cộng số câu đúng của các phần làm tử số và cộng tổng số câu của các phần làm mẫu số; không cộng tỷ lệ phần trăm hay trung bình các phân số.
  - Giữ nguyên ý nghĩa câu đúng/tổng số câu, không rút gọn phân số; ví dụ 20/30 + 30/30 + 30/30 hiển thị tổng 80/90.
  - Khi sửa điểm thành phần hợp lệ, hệ thống tính lại điểm tổng; chỉ được sửa khi điểm tổng tương ứng chưa công bố hoặc đã chủ động hủy công bố.
  - Excel cũng tính tổng theo điểm thành phần, không dùng ô tổng làm nguồn cập nhật độc lập.
  - Cho phép lưu điểm thành phần chưa đầy đủ, áp dụng cả giao diện và Excel; thiếu phần được xem là dữ liệu chưa hoàn tất, không tự coi là lỗi đồng bộ nếu các dữ liệu đã nhập đều hợp lệ.
  - Khi chưa đủ các phần, tính tổng tạm từ các phần đã nhập và thể hiện rõ trạng thái chưa hoàn tất trong giao diện nội bộ.
  - Phần chưa nhập vẫn là thiếu dữ liệu, không tự lưu thành điểm 0; điểm 0 được nhập chủ động là một giá trị hợp lệ và được tính là đã nhập.
  - Với phân số, tổng tạm hiển thị số câu đúng đã nhập trên tổng số câu của toàn bài theo cấu hình; không rút mẫu số xuống chỉ còn các phần đã nhập. Quy tắc nghiệp vụ: bài có ba phần, mỗi phần 30 câu, mới nhập phần đầu 20/30 thì hiển thị tổng tạm 20/90 kèm nhãn chưa hoàn tất; không coi các phần chưa nhập là đã chấm 0.
  - Không được công bố điểm tổng của học sinh còn thiếu bất kỳ phần nào. Khi công bố cả lớp, chỉ áp dụng cho học sinh đủ các phần và thông báo các học sinh còn thiếu, theo ACAD-01.
  - Điểm tổng tạm và các phần chưa hoàn tất không được trả về trang phụ huynh.
  - Khi bổ sung đủ các phần, tính lại tổng đầy đủ; không tự công bố, vẫn cần Admin hoặc giáo viên chủ động công bố.
  - Mỗi bài kiểm tra có một tùy chọn hiện/ẩn toàn bộ chi tiết điểm thành phần, áp dụng chung cho cả bài và mọi học sinh; không có tùy chọn riêng theo học sinh hoặc từng phần.
  - Điểm thành phần không có trạng thái công bố độc lập. Công bố/hủy công bố vẫn theo điểm tổng của từng học sinh trong bài, hoặc cả lớp theo ACAD-01.
  - Khi điểm tổng của học sinh đã công bố: nếu tùy chọn của bài là hiện, phụ huynh thấy toàn bộ chi tiết các phần của học sinh đó; nếu là ẩn, chỉ thấy điểm tổng.
  - Nếu điểm tổng chưa công bố hoặc đã bị hủy công bố, không hiển thị cả điểm tổng lẫn điểm thành phần, bất kể tùy chọn hiện/ẩn của bài.
  - Tùy chọn hiển thị không ảnh hưởng việc lưu và tính tổng điểm thành phần nội bộ; khóa sửa/xóa điểm vẫn theo trạng thái công bố điểm tổng.
  - Được đổi tùy chọn hiện/ẩn khi bài đã có điểm công bố, không yêu cầu hủy công bố trước. Đây là thay đổi cách hiển thị toàn bài, không phải thay đổi kết quả học sinh.
  - Thay đổi tùy chọn không làm thay đổi trạng thái công bố điểm hoặc nhận xét của bất kỳ học sinh nào; trang phụ huynh áp dụng tùy chọn mới trong lần tra cứu tiếp theo.
  - Thay đổi tùy chọn thành công được audit trước/sau; nếu ghi audit thất bại, giữ nguyên tùy chọn cũ theo AUD-01.
  - Quyền công bố/hủy công bố vẫn thuộc Admin hoặc giáo viên có phân công đang hiệu lực; trợ giảng được nhập điểm nhưng không được công bố/hủy công bố.
  - Khi điểm tổng của học sinh đang công bố, các điểm thành phần của học sinh đó bị khóa sửa/xóa, kể cả khi đang ẩn với phụ huynh; phải chủ động hủy công bố điểm tổng tương ứng trước khi sửa/xóa theo ACAD-01.
  - Thang phân số của từng phần kiểm tra số câu đúng là số nguyên từ 0 tới tổng số câu của phần; tổng số câu của phần là số nguyên dương.
  - Trạng thái Vắng của học sinh đối với cả bài vẫn là trạng thái riêng, không tự đổi thành điểm 0 ở các phần.
  - Đồng bộ Excel và audit hỗ trợ dữ liệu thành phần theo XLS-06; giữ phiên bản trước thay đổi độc lập audit.
- **Tiêu chí nghiệm thu:**
  - Tạo được bài thang số/phân số nhập tổng trực tiếp mà không cần cấu hình phần.
  - Cấu hình và nhập được nhiều phần cho bài thang số hoặc phân số, bao gồm các ví dụ trên.
  - Tổng thang số bằng tổng điểm các phần; tổng thang phân số cộng đúng số câu đạt và tổng số câu, không rút gọn.
  - Không ghi đè tổng bằng giao diện hoặc Excel khi bài dùng điểm thành phần.
  - Lưu được một phần điểm thành phần và tổng tạm; không công bố được học sinh chưa đủ các phần, kể cả qua API.
  - Bài 90 câu mới nhập 20 câu đúng ở phần đầu 30 câu hiển thị tổng tạm 20/90, kèm nhãn chưa hoàn tất; hai phần còn lại vẫn là chưa nhập.
  - Công bố cả lớp bỏ qua học sinh chưa đủ phần và thông báo danh sách; nhập bổ sung đủ không tự công bố.
  - Tùy chọn hiện/ẩn điểm thành phần áp dụng chung toàn bài kiểm tra, nhất quán cho mọi học sinh đã công bố điểm tổng.
  - Đổi được tùy chọn khi bài đã có điểm công bố mà không cần hủy công bố; kết quả và trạng thái công bố giữ nguyên.
  - Tùy chọn hiện không làm lộ điểm thành phần của học sinh chưa công bố điểm tổng.
  - Khi tùy chọn ẩn hoặc điểm tổng chưa công bố, API tra cứu phụ huynh không trả chi tiết điểm thành phần; thay đổi thành công được ghi audit.
- **Thay đổi cấu trúc:** Đổi cấu trúc phần/điểm tối đa/tổng số câu phải hủy công bố, nhập lại, công bố lại theo TEST-03.
- **Đã chốt:** Chuyển chế độ trực tiếp/theo phần sau khi có kết quả áp dụng TEST-03; điểm/cấu hình cũ giữ trong lịch sử phiên bản độc lập audit, Vắng giữ nguyên.
- **Giới hạn cấu hình:** Từ 1 đến 50 phần nếu chọn theo phần, mỗi tên tối đa 200 ký tự, duy nhất trong bài; điểm tối đa mỗi phần là số dương tối đa hai số lẻ, tổng số câu phần là số nguyên dương. Tổng tối đa bài phải đúng tổng tối đa các phần, không lưu cấu hình mâu thuẫn.
- **Đổi hiện/ẩn:** Chỉ Admin hoặc giáo viên có phân công hiệu lực được đổi tùy chọn hiện/ẩn thành phần khi đã có điểm công bố; trợ giảng chỉ nhập/sửa điểm chưa công bố, không đổi tùy chọn này. Thay tùy chọn không sửa điểm hoặc trạng thái công bố.

#### TEST-06. Xóa mềm và khôi phục bài kiểm tra

- **Quyền:** Admin hoặc giáo viên có phân công hiệu lực trong lớp; trợ giảng/Receptionist không được xóa hoặc khôi phục cả bài, kể cả bài chưa có điểm.
- **Xóa:** Xem số kết quả/nhận xét bị ảnh hưởng rồi xác nhận. Lưu trữ bài và dữ liệu liên quan, tự ngừng công bố toàn bộ điểm/nhận xét gắn bài; không yêu cầu hủy công bố thủ công. Giữ điểm tổng, thành phần, Vắng, nhận xét, trạng thái trước xóa và phiên bản lịch sử; không xóa vật lý sau 60 ngày.
- **Phạm vi:** Không thay bài khác hoặc nhận xét đợt độc lập; xóa cả bài là ngoại lệ riêng của khóa sửa tại ACAD-01. Sửa/xóa một kết quả đang công bố vẫn phải hủy công bố chủ động trước.
- **Khôi phục:** Dùng bài và kết quả cũ, mọi nội dung về Chưa công bố; không tự công bố lại, không tạo bản sao hoặc đổi khóa học sinh/bài. Người đủ quyền kiểm tra rồi chủ động công bố.
- **Nghiệm thu:** Một lỗi lưu/audit hủy toàn bộ thao tác; trang phụ huynh không thấy bài đã xóa, lịch sử nội bộ còn đọc được theo quyền. Trợ giảng/Receptionist bị chặn xóa/khôi phục qua API.

### C.9. Nhận xét và đợt nhận xét

#### COMMENT-01. Nhận xét văn bản tự do theo học sinh

- **Mục đích:** Ghi nội dung đánh giá cho từng học sinh trong bài kiểm tra hoặc đợt nhận xét độc lập.
- **Người được nhập/sửa:** Admin hoặc giáo viên/trợ giảng có phân công đang hiệu lực trong lớp, tuân theo khóa công bố tại ACAD-01. Receptionist không có quyền nhập/sửa nhận xét.
- **Cấu trúc:** Mỗi học sinh có một ô văn bản tự do trong từng bài kiểm tra hoặc đợt nhận xét; không chia thành các trường tiêu chí riêng.
- **Quy tắc nghiệp vụ:**
  - Nội dung riêng cho từng học sinh và từng bài/đợt, không dùng chung một nội dung cho cả lớp.
  - Nhận xét gắn bài kiểm tra và nhận xét theo đợt riêng đều sử dụng cấu trúc văn bản tự do này.
  - Chỉ Admin hoặc giáo viên đang được phân công được công bố/hủy công bố; trợ giảng được nhập/sửa nhưng không được công bố.
  - Phải chủ động hủy công bố trước khi sửa/xóa riêng nhận xét đang công bố.
  - Đồng bộ Excel hỗ trợ thêm/sửa/xóa nội dung theo đúng học sinh và bài/đợt, theo XLS-03 và XLS-04.
  - Nhận xét chỉ hiển thị cho phụ huynh khi đã công bố; thay đổi thành công được audit.
- **Tiêu chí nghiệm thu:** Nhập và lưu được văn bản riêng cho từng học sinh trong từng bài/đợt; không bắt nhập tiêu chí riêng; quyền chỉnh sửa, công bố và đồng bộ nhất quán với ACAD-01 và XLS-03/XLS-04.
- **Định dạng:** Văn bản thuần, tối đa 1.000 ký tự; UI quyết định cách trình bày.
- **Giới hạn:** Tối đa **1.000 ký tự**, văn bản thuần; cách trình bày theo UI, không có mức đánh giá chữ trong nội dung nhận xét. Kiểm tra độ dài cả giao diện/API/Excel; vượt giới hạn báo lỗi, không tự cắt; file lỗi chặn cả lần đồng bộ.
- **Phạm vi đã làm rõ:** Nhận xét dùng văn bản, không có mức chữ/tiêu chí đánh giá riêng. Thang điểm chữ của bài kiểm tra vẫn được giữ theo TEST-01/02; không gộp hai chức năng này.
- **Nghiệm thu:** Chấp nhận 1.000 ký tự, từ chối 1.001; không cho rich text/HTML trở thành định dạng nhận xét; ô trống Excel giữ nguyên theo XLS-06.

#### COMMENT-02. Đợt nhận xét độc lập

- **Mục đích:** Tổ chức nhận xét học sinh trong lớp theo các đợt độc lập với bài kiểm tra.
- **Người được tạo/sửa:** Admin hoặc giáo viên/trợ giảng có phân công đang hiệu lực trong lớp theo quyền học vụ; Receptionist không có quyền này.
- **Thông tin:** Chỉ có tên đợt, là trường bắt buộc. Không yêu cầu hoặc bổ sung trường ngày bắt đầu, ngày kết thúc, mô tả cho đợt.
- **Quy tắc nghiệp vụ:**
  - Đợt thuộc một lớp, không bắt buộc liên kết bài kiểm tra.
  - Mỗi học sinh có một ô nhận xét văn bản tự do trong đợt theo COMMENT-01.
  - Công bố/hủy công bố theo từng học sinh hoặc cả lớp trong đợt, độc lập với các đợt khác và điểm kiểm tra, theo ACAD-01.
  - Chỉ Admin hoặc giáo viên đang được phân công có quyền công bố/hủy công bố.
  - Thao tác tạo/sửa thành công được audit theo AUD-01.
- **Tiêu chí nghiệm thu:** Tạo được đợt chỉ bằng tên hợp lệ; tên trống bị từ chối; lưu nhận xét theo từng học sinh và áp dụng đúng quyền công bố của đợt.
- **Quyền sửa tên:** Cho sửa tên đợt ngay cả khi đã có nhận xét công bố; giữ nguyên nội dung và trạng thái công bố nhận xét.
- **Khóa nhận xét:** Duy nhất theo học sinh/đợt; không sao chép theo lần tham gia. Thời điểm tạo nhận xét mỗi học sinh là dữ liệu hệ thống để lọc lịch sử, không thêm trường ngày vào thông tin đợt chỉ có tên. Sửa nội dung giữ mốc tạo; xóa giá trị/đợt giữ phiên bản lịch sử.

#### COMMENT-03. Xóa mềm và khôi phục đợt nhận xét

- **Quyền:** Admin hoặc giáo viên có phân công đang hiệu lực; trợ giảng/Receptionist không được xóa/khôi phục cả đợt.
- **Xóa:** Xem ảnh hưởng, xác nhận rồi lưu trữ đợt và nhận xét theo học sinh, tự ngừng công bố; giữ văn bản, trạng thái trước xóa và phiên bản lịch sử độc lập với audit. Không cần hủy công bố thủ công khi xóa cả đợt; không tác động nhận xét gắn bài hoặc đợt khác.
- **Khôi phục:** Dùng lại định danh và nội dung, về Chưa công bố; không tự công bố hoặc nhân đôi khóa học sinh/đợt.
- **Nghiệm thu:** Xóa/khôi phục cùng audit nguyên khối; hủy hoặc lỗi không đổi dữ liệu/trạng thái. Phụ huynh không nhận đợt lưu trữ; quyền sửa/xóa nhận xét riêng vẫn theo ACAD-01.

### C.10. Công bố điểm và nhận xét

#### ACAD-01. Công bố độc lập và khóa sửa dữ liệu đã công bố

- **Mục đích:** Kiểm soát nội dung học tập hiển thị cho phụ huynh và tránh thay đổi dữ liệu đang công bố khi chưa được duyệt lại.
- **Quyền công bố/hủy công bố:** Admin và mọi giáo viên có phân công đang hiệu lực trong lớp, không phụ thuộc người tạo. Trợ giảng và Receptionist không có quyền này.
- **Đối tượng và phạm vi:**
  - Điểm và nhận xét có trạng thái công bố riêng, không gộp thành một trạng thái chung.
  - Nhận xét hỗ trợ hai loại: nhận xét gắn với từng bài kiểm tra và nhận xét theo đợt riêng (ví dụ tuần/tháng), độc lập với bài kiểm tra.
  - Nhận xét gắn bài kiểm tra vẫn có trạng thái công bố độc lập với điểm của bài đó; công bố/hủy công bố điểm không tự thay đổi trạng thái nhận xét và ngược lại.
  - Nhận xét theo đợt riêng có thể tồn tại mà không cần bài kiểm tra tương ứng.
  - Với nhận xét, chọn từng bài kiểm tra hoặc từng đợt nhận xét, rồi công bố/hủy công bố cho một học sinh hoặc cả lớp trong phạm vi đã chọn.
  - Trạng thái công bố nhận xét được quản lý theo từng học sinh trong từng bài kiểm tra/đợt; thao tác không làm thay đổi nhận xét của bài kiểm tra hoặc đợt khác.
  - Với điểm, đơn vị công bố là điểm của từng học sinh trong từng bài kiểm tra. Khi công bố/hủy công bố, chọn một bài kiểm tra và phạm vi một học sinh hoặc cả lớp cho bài đó.
  - Với IELTS, đơn vị vẫn là kết quả học sinh/bài: kiểm tra hoàn tất theo những kỹ năng đã chọn tại TEST-01. Không đòi Overall cho bài chỉ có một đến ba kỹ năng; không công bố riêng từng kỹ năng hoặc từng Task.
  - Công bố/hủy công bố điểm của một bài kiểm tra không thay đổi trạng thái công bố điểm của các bài kiểm tra khác.
  - Cho phép công bố/hủy công bố theo từng học sinh trong lớp hoặc theo cả lớp.
  - Thao tác đối với điểm không tự công bố/hủy công bố nhận xét, và ngược lại.
- **Quy tắc sửa/xóa:**
  - Không cho phép sửa hoặc xóa trực tiếp điểm/nhận xét đang được công bố, áp dụng cả trên giao diện và qua Excel; backend cũng phải kiểm tra trạng thái.
  - Không tự hủy công bố khi người dùng yêu cầu sửa/xóa hoặc tải Excel lên.
  - Admin hoặc giáo viên có quyền phải chủ động hủy công bố nội dung tương ứng trước; sau đó người có quyền thao tác mới được sửa/xóa.
  - Hủy công bố điểm chỉ mở khóa sửa điểm tương ứng; nhận xét đang công bố vẫn bị khóa sửa, và ngược lại.
  - Sau khi sửa, nội dung vẫn chưa công bố cho tới khi Admin hoặc giáo viên chủ động công bố lại.
  - Nếu Excel có dòng yêu cầu sửa/xóa trực tiếp điểm hoặc nhận xét đang công bố, báo lỗi và chặn toàn bộ lần đồng bộ theo XLS-04.
  - Xóa cả đợt nhận xét là ngoại lệ: tự hủy công bố toàn bộ nhận xét trong đợt trước khi xóa theo COMMENT-03; chỉ Admin/giáo viên đủ quyền được thực hiện.
  - Xóa cả bài kiểm tra là ngoại lệ: tự hủy công bố toàn bộ điểm/nhận xét gắn bài trước khi xóa theo TEST-06; không yêu cầu hủy công bố thủ công.
  - Xóa mềm hồ sơ học sinh khỏi lớp theo XLS-02 giữ điểm/nhận xét và trạng thái lịch sử, chỉ chặn tra cứu theo PORTAL-02; không cấp cho Receptionist quyền sửa/xóa học vụ độc lập. Xóa mềm cả bài/đợt là thao tác riêng tại TEST-06/COMMENT-03.
  - Khi công bố cả lớp mà một số học sinh chưa có dữ liệu tương ứng, chỉ công bố cho các học sinh đã có dữ liệu và thông báo danh sách còn thiếu; không chặn toàn bộ thao tác vì thiếu dữ liệu.
  - Với điểm, kiểm tra dữ liệu trong bài kiểm tra đã chọn; với nhận xét, kiểm tra dữ liệu trong bài kiểm tra hoặc đợt nhận xét đã chọn, độc lập với điểm.
  - Không tự tạo điểm, không quy điểm thiếu thành 0 và không tạo nhận xét thay thế cho học sinh thiếu dữ liệu.
  - Học sinh thiếu dữ liệu không được tự công bố khi được nhập bổ sung sau đó; người có quyền phải chủ động công bố.
  - Công bố, hủy công bố và sửa/xóa dữ liệu thành công đều được audit theo AUD-01.
- **Luồng sửa dữ liệu đã công bố:**
  1. Admin hoặc giáo viên chọn điểm hoặc nhận xét, chọn học sinh hoặc cả lớp và chủ động hủy công bố.
  2. Hệ thống hủy công bố đúng loại nội dung và phạm vi được chọn.
  3. Người có quyền chỉnh sửa thực hiện cập nhật trên giao diện hoặc qua Excel.
  4. Admin hoặc giáo viên kiểm tra và chủ động công bố lại khi phù hợp.
- **Xử lý lỗi:** Từ chối sửa/xóa trực tiếp điểm hoặc nhận xét đang công bố; từ chối công bố/hủy công bố nếu người dùng không có quyền hoặc không còn phân công có hiệu lực. Thao tác thất bại không thay đổi dữ liệu và không ghi audit thành công.
- **Kết quả:** Điểm và nhận xét được công bố độc lập, theo phạm vi học sinh hoặc lớp; chỉ nội dung đã chủ động hủy công bố mới được sửa.
- **Tiêu chí nghiệm thu:**
  - Công bố điểm của một học sinh không làm thay đổi trạng thái công bố nhận xét của học sinh đó hoặc nội dung của học sinh khác.
  - Công bố/hủy công bố theo cả lớp áp dụng đúng loại nội dung được chọn; với điểm chỉ áp dụng bài kiểm tra đã chọn.
  - Trong cùng một bài kiểm tra, có thể công bố điểm cho một học sinh trong khi điểm của học sinh khác vẫn chưa công bố; bài kiểm tra khác không bị ảnh hưởng.
  - Không sửa/xóa trực tiếp được điểm hoặc nhận xét đang công bố qua giao diện hoặc API/Excel, kể cả khi người thực hiện là Admin; phải chủ động hủy công bố trước.
  - Dòng Excel xóa điểm/nhận xét đang công bố chặn toàn bộ lần đồng bộ. Lưu trữ hồ sơ học sinh tại lớp không xóa học vụ; không dùng XLS-02 để vượt khóa sửa điểm/nhận xét.
  - Trợ giảng chỉ sửa được nội dung chưa công bố và không tự hủy công bố để vượt khóa sửa.
  - Sửa sau khi hủy công bố không tự công bố lại.
  - Tạo được nhận xét gắn bài kiểm tra và nhận xét theo đợt độc lập; cả hai đều tuân theo quyền chỉnh sửa, khóa sửa khi đã công bố và audit.
  - Công bố điểm không tự công bố nhận xét gắn cùng bài kiểm tra.
  - Công bố nhận xét của một học sinh trong bài kiểm tra/đợt đã chọn không tự công bố nhận xét của học sinh khác hoặc các bài kiểm tra/đợt khác.
  - Công bố nhận xét cả lớp chỉ tác động tới bài kiểm tra hoặc đợt nhận xét đã chọn.
  - Công bố cả lớp có dữ liệu thiếu vẫn thành công cho những học sinh đã có dữ liệu, thông báo danh sách thiếu và không tạo dữ liệu thay thế.
  - Nhập bổ sung dữ liệu còn thiếu không tự công bố.
- **Hiển thị cho phụ huynh:**
  - Ẩn hoàn toàn nội dung chưa công bố hoặc đã bị hủy công bố; không hiển thị mục tương ứng hoặc nhãn Chưa công bố.
  - Kiểm tra trạng thái công bố theo từng học sinh và từng bài kiểm tra/đợt nhận xét; chỉ trả dữ liệu đã công bố của đúng học sinh trong phạm vi tra cứu.
  - Điểm và nhận xét được lọc độc lập: nếu chỉ điểm đã công bố thì chỉ hiển thị điểm, không kèm nhận xét chưa công bố; áp dụng tương tự theo chiều ngược lại.
  - Nếu một bài kiểm tra không có điểm hay nhận xét nào đã công bố cho học sinh đang tra cứu, không hiển thị mục bài kiểm tra đó. Đợt nhận xét chưa công bố cũng không hiển thị.
  - Backend không trả nội dung chưa công bố hoặc đã hủy công bố trong phản hồi tra cứu công khai; không chỉ ẩn bằng giao diện.
- **Tiêu chí nghiệm thu hiển thị:** Phụ huynh không thấy mục hoặc dữ liệu chưa công bố; hủy công bố làm nội dung không còn được trả về và hiển thị ở lần tra cứu tiếp theo; trạng thái công bố của học sinh khác không làm lộ dữ liệu của học sinh đang tra cứu.
- **Không có dữ liệu hợp lệ:** Nếu công bố cả lớp mà không có học sinh nào đủ kết quả/nội dung, báo Không có dữ liệu đủ điều kiện, không đổi trạng thái hoặc tạo audit thay đổi. Có một phần dữ liệu hợp lệ thì chỉ công bố phần đó và liệt kê phần thiếu như quy tắc trên.

### C.11. Trang lớp và tra cứu phụ huynh

#### PORTAL-01. Trang lớp làm mẫu tra cứu

- **Nội dung công khai:** Tên lớp, môn học, danh sách giáo viên và số điện thoại, danh sách trợ giảng và số điện thoại, mô tả, thông báo. Không hiển thị email hoặc thông tin liên hệ khác ngoài số điện thoại của nhân sự.
- **Nội dung nội bộ:** Admin, User và Receptionist có quyền với lớp thấy thêm liên kết tra cứu để sao chép/chia sẻ; không để bộ điều khiển nội bộ xuất hiện trong trang công khai.
- **Quyền sửa nội dung:** Admin hoặc giáo viên có phân công đang hiệu lực trong lớp; quyền User/Receptionist được thấy trang không tự cấp quyền sửa mô tả/thông báo cho trợ giảng/lễ tân.
- **Luồng:** Mở trang lớp, hiển thị nội dung mẫu; phụ huynh dùng liên kết lớp để nhập số điện thoại và tra thông tin của con theo PORTAL-02.
- **Chia sẻ:** Chỉ cung cấp trang/liên kết; không tích hợp tự gửi email/SMS/Zalo cho phụ huynh trong phạm vi này. Email đặt lại mật khẩu vẫn là chức năng tài khoản riêng.
- **Nghiệm thu:** Trang công khai không lộ email nhân sự hoặc liên kết quản trị; trang nội bộ hiện liên kết đúng quyền.
- **Quyền sửa chốt:** Chỉ Admin/giáo viên có phân công hiện hành được sửa mô tả/thông báo; Receptionist và trợ giảng chỉ xem/sao chép liên kết theo quyền, không sửa nội dung công khai.
- **Nhân sự công khai:** Chỉ hiển thị giáo viên/trợ giảng có phân công hiệu lực hiện tại, còn tài khoản hoạt động; tên và số điện thoại nếu có, không email. Lớp đóng không làm mất danh sách nếu phân công vẫn hiệu lực; lớp xóa không có trang công khai.

#### PORTAL-02. Tra cứu bằng số điện thoại và phạm vi lịch sử

- **Người dùng:** Phụ huynh không đăng nhập, nhập số phụ huynh/học sinh được chuẩn hóa như STU-04; không OTP, không tìm bằng tên. Tên không dấu dùng cho tra cứu nội bộ/đối chiếu Excel, không thay hình thức tra cứu công khai.
- **Phạm vi:** Đúng lớp của link đang bật; một số có nhiều con thì trả đúng các con thuộc lớp, không trả danh sách lớp hoặc lớp khác. Không khớp thì báo Không tìm thấy học sinh phù hợp và không trả gợi ý hồ sơ khác.
- **Lớp/hồ sơ:** Lớp Đóng vẫn cho tra lịch sử bằng link đã bật; lớp xóa mềm hoặc link tắt/đã reroll thì chặn toàn bộ tra cứu. Hồ sơ tổng xóa mềm vẫn giữ quyền xem quá khứ; nếu học sinh đã bị xóa mềm khỏi riêng lớp và chưa thêm lại hồ sơ lớp, không trả học sinh đó qua link lớp.
- **Học vụ/chuyên cần:** Theo hợp các khoảng đã tham gia của học sinh trong lớp, kể cả hồ sơ lưu trữ khi đã có hồ sơ lớp mới hợp lệ. Buổi theo thời điểm bắt đầu thực tế; bài kiểm tra theo ngày bài, ngày đó phải giao với khoảng tham gia. Kết quả gắn học sinh/bài nên không sao chép theo mỗi lần tham gia. Nhận xét theo đợt dùng thời điểm tạo nhận xét từng học sinh, không dùng ngày sửa/công bố hoặc tên đợt.
- **Mốc kết thúc:** Ngày nghỉ loại trừ từ 00:00; xóa mềm/kết thúc bằng sự kiện dùng thời điểm thực tế. Buổi đã bắt đầu trước sự kiện vẫn thuộc lịch sử, không xóa điểm danh. Bài chỉ có ngày được xem thuộc lịch sử nếu ngày đó có giao khoảng tham gia; giữ kết quả cũ khi kết thúc giữa ngày.
- **Tài chính:** Hiển thị các khoản/lần thu của đúng hồ sơ học sinh–lớp được tra, kể cả thu trước ngày vào hoặc thu nợ sau ngày nghỉ, với tháng/kỳ/ngày áp dụng và ngày thu riêng. Khoản tương lai đã hủy nghĩa vụ chỉ nằm trong lịch sử có nhãn, không hiện như tiền cần đóng. Không lọc mất tiền đã thu chỉ vì ngày tạo/thu nằm ngoài khoảng tham gia. Khi thêm lại, phân biệt các khoản của hồ sơ cũ/mới, không gộp thành một nghĩa vụ.
- **Công bố:** Chỉ trả phiên bản học vụ hiện hành đã công bố của đúng học sinh; điểm/nhận xét lọc độc lập, thành phần theo tùy chọn bài và trạng thái điểm. Không trả bài/đợt đã xóa mềm, kết quả cũ bị thay thế, ghi chú nội bộ, audit hoặc dữ liệu tài chính của người khác.
- **Nghiệm thu:** Số khác cách ghi nhưng cùng chuẩn hóa tra cùng hồ sơ; nhiều con đúng lớp trả đủ. Thu trước và trả nợ sau nghỉ vẫn thấy đúng khoản; sửa ngày bài không làm lộ kết quả ngoài khoảng tham gia. Xóa/đóng lớp không làm mất dữ liệu quá khứ, nhưng lớp xóa không tra được công khai.

#### PORTAL-03. Quản lý và tạo lại liên kết tra cứu

- **Chức năng:** Có cơ chế quản lý liên kết và reroll (tạo lại liên kết) riêng theo lớp; giao diện nội bộ cho người có quyền với lớp xem/sao chép liên kết.
- **Hành vi:** Khi tạo lại thành công, cấp liên kết mới và vô hiệu liên kết cũ; không thay lớp hoặc xóa dữ liệu học sinh. Nếu thất bại thì giữ liên kết cũ. Thay đổi thành công ghi audit.
- **Luồng:** Người được cấp quyền mở quản lý liên kết, yêu cầu tạo lại, hệ thống cập nhật và trả liên kết mới để chia sẻ.
- **Nghiệm thu:** Link mới tra đúng lớp, link cũ không tiếp tục tra cứu; người chỉ xem link không tự có quyền tạo lại.
- **Quyền:** Admin và giáo viên có phân công đang hiệu lực được reroll, bật/tắt liên kết. Receptionist và trợ giảng chỉ xem/sao chép theo quyền lớp, không được đổi liên kết. Liên kết không tự hết hạn; reroll vô hiệu liên kết cũ.
- **Nghiệm thu bổ sung:** Link tắt không tra cứu được; giáo viên hết phân công không quản lý link; chỉ xem link không đủ quyền tạo lại qua API.
- **Xác nhận:** Bật/tắt/reroll đều có xác nhận; reroll báo link cũ sẽ vô hiệu. Lớp xóa mềm giữ cấu hình link nhưng chặn sử dụng; khôi phục lớp về Đóng, link chỉ dùng lại sau Mở lại theo trạng thái bật/tắt đã lưu. Không khôi phục link cũ đã bị reroll.

### C.12. Học phí và khoản thu

Tài chính gồm thu học phí theo tháng/kỳ nhiều tháng, khoản điều chỉnh học phí tùy chọn và khoản ngoài học phí. Mỗi khoản phải thu thuộc một hồ sơ học sinh–lớp; mỗi lần thu cho một học sinh trong một lớp và có chi tiết riêng cho từng khoản.

- **Số phải thu học phí:** Mức gốc đã lưu + điều chỉnh cố định của Admin, không âm; khoản ngoài học phí dùng số tiền riêng theo FEE-11.
- **Trạng thái thanh toán:** Chưa thu, Đã thu, Không phải thu (số phải thu bằng 0). Cờ Hiệu lực/Đã hủy nghĩa vụ là vòng đời của khoản; hủy nghĩa vụ không xóa bản ghi hoặc lần thu cũ. Không có thanh toán từng phần hoặc quá hạn.
- **Lịch sử:** Giữ các khoản, phiên bản cấu hình/điều chỉnh và lần thu/hủy độc lập với audit 60 ngày. Khoản của hồ sơ lưu trữ vẫn được thu nếu còn nghĩa vụ có hiệu lực; không tự gộp tiền của hồ sơ cũ với hồ sơ mới.

#### FEE-01. Hình thức và mức học phí theo lớp

- **Quyền:** Chỉ Admin cấu hình hình thức thu, mức học phí và khoản điều chỉnh; Admin/Receptionist theo dõi, xác nhận thu. User không được xem chi tiết tiền, thu, cấu hình hoặc xem/tải/in giấy báo học phí, biên nhận qua giao diện/API/Excel.
- **Theo tháng:** Cấu hình mức cho từng tháng/năm của lớp, có thể khác giữa các tháng; chọn một hoặc nhiều tháng để thu cùng lúc.
- **Theo kỳ nhiều tháng:** Cấu hình tên kỳ, ngày bắt đầu/kết thúc và tổng tiền cả kỳ; một khoản cho cả kỳ, không đồng thời sinh học phí tháng trong cùng lớp. Hình thức của lớp không đổi sau khi thiết lập.
- **Giá trị:** VND nguyên đồng, mức gốc không âm; không nhận số thập phân, không tự tính theo buổi/ngày. Mức bằng 0 hoặc sau điều chỉnh bằng 0 mang trạng thái Không phải thu, không ghi nhận tiền thực nhận.
- **Quy tắc:** Một khoản học phí thuộc đúng hồ sơ học sinh–lớp và tháng/kỳ; lưu mức gốc tại lúc tạo. Không cập nhật trạng thái tùy ý; trạng thái do số phải thu và chi tiết thu có hiệu lực quyết định. Thiếu cấu hình chặn tạo/thu khoản đó và báo Admin, không mượn mức tháng khác.
- **Nghiệm thu:** Lớp tháng và lớp kỳ cùng tồn tại; mức từng lớp/tháng độc lập; Receptionist không đổi mức hoặc khoản điều chỉnh. Thay đổi thành công có audit.

#### FEE-02. Kỳ thu nhiều tháng

- **Quyền:** Chỉ Admin.
- **Dữ liệu:** Tên kỳ bắt buộc, ngày bắt đầu, ngày kết thúc và mức gốc; ngày kết thúc không trước ngày bắt đầu, phải trải qua ít nhất hai tháng lịch và nằm trong thời gian lớp khi cấu hình.
- **Mặc định theo lớp:** Khi lớp dài nhiều tháng có thể lấy ngày mở/kết thúc lúc tạo kỳ; đây là bản chụp ban đầu, không liên kết tự thay đổi theo ngày lớp. Lớp ngắn một tháng dùng thu tháng.
- **Không chồng kỳ:** Nhiều kỳ trong cùng lớp không giao ngày, tính cả hai đầu. Ví dụ kỳ tháng 9–11 là một khoản, khác ba khoản tháng 9/10/11 được thu cùng lúc.
- **Đổi kỳ:** Kỳ chưa phát sinh nghĩa vụ được sửa/xóa mềm. Khi đã có khoản phát sinh, khóa tên và khoảng thời gian kỳ để giữ nhận diện lịch sử; mức gốc mới chỉ áp dụng cho khoản tạo sau theo FEE-09. Gia hạn lớp tạo kỳ mới cho thời gian thêm, không kéo dài khoản kỳ cũ; kết thúc lớp sớm không cắt kỳ/tiền cũ.
- **Nghiệm thu:** Không tạo trùng kỳ hoặc làm đổi kỳ đã phát sinh khi sửa ngày lớp; kỳ mới đúng quyền và được audit.

#### FEE-03. Thu một hoặc nhiều tháng và thu trước

- **Quyền:** Admin/Receptionist, cho một học sinh trong một lớp.
- **Chọn khoản:** Lớp tháng được chọn bất kỳ một hoặc nhiều tháng chưa thu, không bắt buộc theo quý/nhóm cố định. Lớp kỳ chọn một hoặc nhiều khoản kỳ riêng biệt; không tách khoản kỳ thành các tháng để đóng một phần.
- **Thu trước:** Cho chọn tháng/kỳ tương lai giao với khoảng tham gia đã đăng ký và thuộc thời gian lớp, khi lớp không Đóng/xóa mềm. Nếu chưa có khoản, tạo và ghi thu trong cùng giao dịch. Khoản đã có dùng mức đã lưu cộng điều chỉnh có hiệu lực; khoản mới dùng cấu hình đúng kỳ tại lúc tạo.
- **Tổng tiền:** Cộng số phải thu từng khoản; giữ chi tiết mức gốc/điều chỉnh/số thu theo từng khoản. Khoản Không phải thu không được chọn để tạo chi tiết thu tiền.
- **Nguyên khối/chống trùng:** Tất cả khoản được chọn cùng thành công/thất bại; thiếu cấu hình, khoản đã thu/hủy nghĩa vụ, lỗi phiên bản hoặc audit chặn cả lần. Hai yêu cầu đồng thời không ghi thu hai lần cùng khoản. Đến đầu tháng/kỳ không tạo lại khoản đã thu trước.
- **Luồng:** Chọn học sinh/lớp và các khoản → xem chi tiết/tổng → chọn phương thức/ghi chú → xác nhận theo FEE-05. Có thể kèm khoản ngoài học phí theo FEE-11.
- **Nghiệm thu:** Thu trước tháng 8–9–10 giữ ba chi tiết, mức tháng khác nhau cộng đúng; thu trước kỳ 9–11 giữ một chi tiết kỳ. Một lỗi không để lại khoản hoặc lần thu mới một phần.

#### FEE-04. Khoản điều chỉnh học phí theo tháng hoặc kỳ

- **Mục đích:** Admin cấu hình khoản cộng/trừ cố định, tùy chọn, cho học phí của từng học sinh trong một lớp và một tháng/kỳ. Cấu hình có hiệu lực ngay sau khi Admin lưu hợp lệ; chỉ nhập số tiền cố định.
- **Quyền:** Chỉ Admin tạo/sửa/gỡ khoản điều chỉnh. Receptionist chỉ xem số tiền đang có hiệu lực để thu/in; giáo viên/trợ giảng không có quyền xem hoặc cấu hình.
- **Dữ liệu:** Hồ sơ học sinh–lớp, tháng hoặc kỳ, số tiền điều chỉnh nguyên VND có dấu và lý do bắt buộc. Chọn nhiều học sinh khi cấu hình sẽ tạo các điều chỉnh riêng có cùng giá trị; không tạo mức điều chỉnh chung tự lan sang học sinh khác hoặc tháng/kỳ khác.
- **Cách tính:** Số phải thu = mức gốc đã lưu của khoản học phí + điều chỉnh hiện hành. Số dương cộng thêm, số âm trừ bớt; kết quả không được âm. Ví dụ gốc 1.000.000 và điều chỉnh -100.000 thì phải thu 900.000; điều chỉnh +100.000 thì 1.100.000.
- **Một giá trị hiệu lực:** Mỗi khoản học phí có tối đa một điều chỉnh hiện hành. Sửa là thay giá trị đó, không cộng dồn với phiên bản cũ. Gỡ điều chỉnh đưa về mức gốc; giữ mọi phiên bản và lý do trong lịch sử nghiệp vụ, độc lập với audit 60 ngày.
- **Tháng/kỳ tương lai:** Admin được cấu hình khi đã có mức gốc và khoảng tham gia hợp lệ; tạo khoản học phí chưa thu nếu cần để gắn điều chỉnh. Tác vụ sau đó không tạo trùng. Thiếu cấu hình hoặc chưa có hồ sơ tham gia hợp lệ thì chặn cả thao tác.
- **Khóa sau thu:** Không đổi điều chỉnh của khoản đang Đã thu. Nếu bản thu sai, Admin gỡ thu theo FEE-06 trước rồi mới sửa khoản chưa thu; không sửa lịch sử lần thu cũ. Chỉ thay khoản chưa thu hoặc Không phải thu còn hiệu lực, kể cả trong hồ sơ lưu trữ. Cấu hình nhiều học sinh phải cùng thành công/thất bại.
- **Không phải thu:** Tổng bằng 0 chuyển khoản sang Không phải thu; không tạo lần thu hoặc cộng Tổng thu. Đổi điều chỉnh để tổng dương đưa về Chưa thu. Hủy nghĩa vụ là cờ hiệu lực riêng, không thay bằng điều chỉnh để xóa lịch sử.
- **Phạm vi:** Điều chỉnh gắn học phí; khoản ngoài học phí quản lý số tiền theo FEE-11. Mọi sửa/gỡ kiểm tra lại phiên bản và ghi audit trước/sau.
- **Nghiệm thu:** Chỉ Admin cấu hình được; cộng/trừ đúng VND, chặn tổng âm và khoản đã thu. Gỡ điều chỉnh giữ phiên bản cũ, không thay mức của khoản khác; thay đổi chỉ áp dụng bởi Admin và có hiệu lực ngay.
- **Giới hạn vòng đời:** Không tạo khoản học phí mới cho tháng/kỳ tương lai khi lớp Đóng/lưu trữ hoặc chưa có đăng ký phù hợp. Khoản đã phát sinh hợp lệ vẫn được Admin sửa điều chỉnh nếu chưa thu, kể cả để xử lý nợ trong hồ sơ lưu trữ.

#### FEE-05. Xác nhận thu đủ trong một lần

- **Quyền:** Admin/Receptionist. Mỗi lần thu thuộc một học sinh và một lớp; có thể chọn học phí, khoản ngoài học phí hoặc cả hai.
- **Thông tin thu:** Ngày/thời điểm do hệ thống ghi khi nhấn xác nhận, không nhập lùi; người thu là tài khoản đăng nhập; phương thức bắt buộc Tiền mặt hoặc Chuyển khoản; ghi chú tùy chọn.
- **Số tiền:** Mỗi khoản được chọn thu đủ số phải thu đang có hiệu lực, không nhập một phần, không chia một khoản thành nhiều lần đóng và không có trạng thái Đã thu một phần. Khoản học phí bao gồm điều chỉnh gắn kèm, không được chọn bỏ riêng dòng điều chỉnh.
- **Kiểm tra:** Khoản còn hiệu lực, số phải thu lớn hơn 0, chưa có chi tiết thu hiệu lực; kiểm tra quyền và phiên bản cả số tiền/điều chỉnh lúc xác nhận. Một lần thu không chứa nhiều học sinh hoặc nhiều lớp, không nhận khoản đã hủy nghĩa vụ hoặc Không phải thu.
- **Lưu:** Ghi lần thu và chi tiết từng khoản (mức gốc, điều chỉnh nếu có, số tiền thực thu), cập nhật Đã thu và audit trong cùng giao dịch. Lỗi một khoản hủy toàn bộ lựa chọn, kể cả tạo khoản khi thu trước.
- **Biên nhận:** Trong cùng transaction thu thành công, cấp mã biên nhận duy nhất gắn một lần thu và giữ bản chụp thông tin giao dịch để in lại theo REPORT-01. Gửi lại cùng lệnh không sinh mã/lần thu mới. Tạo/tải/in file là bước sau commit; lỗi dựng file không hủy hoặc ghi thu lần hai. Thiếu mẫu in không được biến lần thu đã thành công thành thất bại tài chính.
- **Lịch sử:** Không sửa/xóa trực tiếp lần thu hoặc số tiền từng thu. Sửa bản thu sai bằng FEE-06; thu lại lập lần mới, liên kết đúng khoản và giữ lần cũ.
- **Nghiệm thu:** Thu riêng/chung đúng chi tiết và tổng; khoản trả đủ chuyển Đã thu, không thu trùng khi nhấn lại hoặc gửi đồng thời. Lỗi dữ liệu/audit không có thu một phần; thông tin người/ngày/phương thức truy vết được.

#### FEE-06. Admin gỡ bản ghi thu sai

- **Quyền:** Chỉ Admin; Receptionist/User bị chặn qua giao diện/API. Áp dụng học phí tháng, kỳ nhiều tháng và khoản ngoài học phí, kể cả bản thuộc hồ sơ/lớp lưu trữ.
- **Lựa chọn:** Gỡ một hoặc nhiều chi tiết trong một lần thu, hoặc toàn bộ chi tiết còn hiệu lực. Một kỳ là một chi tiết, không gỡ một phần tháng bên trong kỳ. Chi tiết đã hủy không được xử lý lần hai.
- **Luồng:** Xem các khoản, tổng tiền loại khỏi Tổng thu và tác động trạng thái; nhập lý do bắt buộc → xác nhận → kiểm tra lại quyền, hiệu lực và phiên bản → hủy hiệu lực các chi tiết được chọn, ghi người/thời điểm/lý do cùng audit.
- **Tác động:** Khoản còn nghĩa vụ trở về Chưa thu với mức gốc và điều chỉnh hiện hành giữ nguyên; có thể thu lại bằng lần mới. Nếu tháng/kỳ/ngày áp dụng không còn giao khoảng tham gia thực tế hoặc đăng ký còn hiệu lực của đúng hồ sơ, đánh dấu hủy nghĩa vụ thay vì tạo nợ mới. Khoản đã hủy nghĩa vụ giữ cờ hủy, không tự khôi phục công nợ. Không tạo hồ sơ, khoản mới hoặc dữ liệu học vụ chỉ vì gỡ thu.
- **Lịch sử/Tổng thu:** Giữ nguyên nội dung lần thu cũ, thêm sự kiện hủy. Chi tiết bị gỡ mang nhãn Đã hủy, loại khỏi Tổng thu của ngày thu gốc; chi tiết không chọn giữ nguyên. Lần thu thể hiện còn hiệu lực toàn bộ/đã hủy một số khoản/đã hủy toàn bộ theo chi tiết. Thời điểm hủy không được ghi lùi.
- **Biên nhận sau gỡ:** Trạng thái biên nhận theo chi tiết thu có hiệu lực, cập nhật cùng transaction gỡ. Gỡ một phần phải hiện các khoản bị hủy và nhãn biên nhận gốc không còn hiệu lực nguyên trạng; không coi những khoản còn lại đã bị gỡ. Gỡ toàn bộ thể hiện Không còn hiệu lực. Mọi lần preview/tải/in lại kiểm tra trạng thái hiện hành; giữ thông tin giao dịch gốc và sự kiện hủy, không tái sử dụng mã cũ cho lần thu lại.
- **Nguyên khối:** Toàn bộ lựa chọn cùng thành công/thất bại; một chi tiết đã hủy, xung đột hoặc lỗi audit chặn cả thao tác. Gỡ lần cũ không tác động chi tiết của lần thu lại.
- **Nghiệm thu:** Gỡ riêng tháng hoặc tiền tài liệu không đổi khoản khác; gỡ cả lần cộng đúng số bị loại. Gỡ trên hồ sơ lưu trữ vẫn giữ lịch sử và không mở lại quyền tra cứu phụ huynh. Sau 60 ngày vẫn xem được sự kiện hủy từ lịch sử thu độc lập với audit.

#### FEE-07. Tự động tạo và giữ hiệu lực khoản phải thu

- **Thời điểm:** Đầu tháng đối với học phí tháng, đầu kỳ đối với học phí kỳ; học sinh vào giữa tháng/kỳ tạo ngay khi tới ngày vào. Thu/cấu hình điều chỉnh trước tạo khoản theo FEE-03/FEE-04.
- **Đủ điều kiện:** Giao của tháng/kỳ, khoảng tham gia có hiệu lực và khoảng lớp Mở phải có ít nhất một thời điểm chung; không chỉ kiểm tra từng cặp giao nhau riêng rẽ. Không tạo khoản cho khoảng tương lai đã hủy, sau kết thúc tham gia hoặc tháng/kỳ nằm trọn trong khoảng lớp đóng/xóa mềm. Có giao một phần vẫn áp mức đầy đủ; điều chỉnh do Admin nhập.
- **Định danh chống trùng:** Trong một hồ sơ học sinh–lớp, mỗi tháng hoặc kỳ chỉ có một nghĩa vụ học phí hiện hành; các lần nghỉ/học lại trong hồ sơ đó không tạo khoản trùng. Nếu nghĩa vụ của đúng tháng/kỳ đã bị hủy do kết thúc tham gia rồi nay có lần tham gia mới hợp lệ trong cùng hồ sơ, kích hoạt lại đúng khoản cũ với mức đã lưu, không tạo bản sao; việc khôi phục này có audit riêng và chỉ xảy ra khi xác nhận lần tham gia mới. Khoản ngoài học phí có khóa cấu hình khoản + hồ sơ học sinh–lớp + lần phát sinh/ngày áp dụng. Chạy lại/đồng thời không tạo bản sao.
- **Sau xóa hồ sơ rồi thêm lại:** Hồ sơ mới có định danh mới, được tạo nghĩa vụ mới cùng tháng/kỳ theo D07. Lịch sử khoản/thu của hồ sơ cũ còn nguyên, không chuyển trạng thái hoặc tiền sang hồ sơ mới.
- **Mức/số tiền:** Lưu mức cấu hình tại lúc thực sự tạo, cộng điều chỉnh của đúng khoản nếu có. Thiếu cấu hình lưu lỗi chờ Admin, không đặt số tiền 0 để bỏ qua. Số phải thu dương là Chưa thu; bằng 0 là Không phải thu.
- **Chạy bù lịch sử:** Sau lỗi/tạm ngừng hệ thống, chỉ tạo phần nghĩa vụ còn thiếu của khoảng đã tham gia khi lớp mở, kể cả hồ sơ/lớp nay đã lưu trữ. Dùng lịch sử thời gian mở/đóng/xóa, ngày vào/nghỉ và sự kiện kết thúc để xác định; không lấy trạng thái hiện tại xóa bỏ nợ cũ. Ghi ngày tạo thực tế, ngày áp dụng riêng và mức tại lúc tạo theo FEE-09.
- **Hủy nghĩa vụ tương lai:** Khi hủy đăng ký hoặc kết thúc do xóa mềm, khoản chưa thu có ngày áp dụng sau mốc kết thúc và không còn lần tham gia liên quan được đánh dấu Đã hủy nghĩa vụ, giữ dữ liệu; không xóa cứng hoặc tự sinh lại từ tác vụ. Khoản đã thu và khoản đã phát sinh trước mốc vẫn giữ hiệu lực. Khôi phục hồ sơ/lớp không tự hồi sinh nghĩa vụ đã hủy. Với đăng ký chưa bắt đầu bị hủy, hủy cả khoản chưa thu của tháng/kỳ hiện tại đã tạo trước ngày vào nếu không còn bất kỳ khoảng tham gia thực tế/đăng ký hiệu lực nào dùng khoản đó; không lấy ngày đầu kỳ đã qua để coi đó là nợ học thực tế.
- **Ngày áp dụng:** Học phí tháng dùng ngày đầu tháng; học phí kỳ dùng ngày đầu kỳ; khoản ngoài học phí dùng ngày áp dụng đã cấu hình. Ngày áp dụng không phải hạn thanh toán; không thêm hạn thanh toán hoặc trạng thái quá hạn.
- **Nghiệm thu:** Chạy bù không tạo khoản cho khoảng đóng/xóa hoặc nhân đôi thu trước; xóa mềm có nợ vẫn truy được khoản và thu tiếp. Một nghĩa vụ cùng audit là nguyên khối; lỗi một nghĩa vụ không hủy nghĩa vụ khác đã thành công.

#### FEE-08. Học phí khi vào giữa tháng hoặc kỳ

- **Mặc định:** Thu đầy đủ mức gốc của tháng/kỳ giao với ngày vào, không chia theo ngày/buổi còn lại, điểm danh hoặc số buổi đã nghỉ.
- **Khoản điều chỉnh:** Nếu cần khác mức gốc, chỉ Admin cấu hình số cộng/trừ cố định cho khoản đó theo FEE-04. Số tiền có hiệu lực ngay sau khi Admin lưu hợp lệ.
- **Khoản đầu:** Tạo khi tới ngày vào nếu đang trong tháng/kỳ; không sinh nghĩa vụ cho kỳ đã kết thúc trước ngày vào. Thu trước dùng khoảng đã đăng ký và cấu hình hợp lệ.
- **Nghiệm thu:** Vào giữa kỳ tạo một khoản đủ mức, thêm điều chỉnh tính đúng tổng; học lại trong cùng hồ sơ/tháng không tạo trùng, còn thêm lại sau xóa hồ sơ tạo khoản mới theo FEE-07.

#### FEE-09. Thay đổi mức học phí cấu hình

- **Quyền:** Chỉ Admin.
- **Khoản đã có:** Giữ mức gốc, điều chỉnh và số phải thu đã lưu dù khoản Chưa thu, Không phải thu, Đã thu hoặc đã gỡ thu để thu lại. Đổi mức chung không tự tính lại, phát sinh chênh lệch hoặc sửa lần thu cũ.
- **Khoản mới:** Dùng mức của đúng tháng/kỳ tại thời điểm thực sự tạo, gồm thu trước và chạy bù; giữ ngày tạo thực tế cùng ngày áp dụng. Lưu phiên bản cấu hình đã dùng để truy vết.
- **Thay riêng:** Muốn thay số phải thu của khoản chưa thu thì Admin cấu hình khoản điều chỉnh tại FEE-04, không sửa mức gốc đã chụp. Khoản đã thu khóa thay đổi cho tới khi gỡ bản thu sai hợp lệ.
- **Nghiệm thu:** Đổi mức chỉ ảnh hưởng khoản tạo sau; không nhân đôi nghĩa vụ hoặc lịch sử thu. Mọi thay đổi cấu hình có audit và lịch sử phiên bản.

#### FEE-10. Nghỉ học và bảo toàn nghĩa vụ đã phát sinh

- **Nguyên tắc:** Nghỉ giữa tháng/kỳ giữ nguyên khoản đã phát sinh và tiền đã thu; không tự tính tỷ lệ theo số buổi/ngày, không tự xóa nợ hoặc chuyển tiền sang lớp khác.
- **Sau nghỉ:** Không tạo nghĩa vụ cho thời gian không còn tham gia. Khoản chưa thu có ngày áp dụng sau mốc nghỉ và không còn khoảng tham gia tương ứng được đánh dấu hủy nghĩa vụ, giữ bản ghi theo FEE-07; khoản đã thu trước giữ nguyên hiệu lực và lịch sử.
- **Khác số phải thu:** Admin dùng FEE-04 cho học phí chưa thu. Hủy bản thu sai chỉ theo FEE-06; không sửa tiền của lần thu đã có.
- **Nghiệm thu:** Nghỉ/chuyển lớp/xóa mềm không làm mất nợ của tháng/kỳ đã bắt đầu; không phát sinh khoản trong khoảng nghỉ. Học lại thông thường không thu trùng khoản đã có, thêm lại sau xóa hồ sơ tuân theo D07.

#### FEE-11. Khoản thu ngoài học phí theo lớp

- **Quyền:** Admin/Receptionist cấu hình tên, số tiền, ngày áp dụng, đối tượng và nhịp phát sinh; User không được cấu hình hoặc xem tài chính. Quyền này không cho Receptionist sửa học phí gốc hoặc khoản điều chỉnh FEE-04.
- **Cấu hình:** Khoản một lần hoặc định kỳ tháng/kỳ, áp dụng cả lớp hoặc chọn học sinh. Số tiền nguyên VND lớn hơn 0; cấu hình hợp lệ có hiệu lực ngay. Định kỳ theo kỳ dùng các kỳ học phí có sẵn; lớp thu tháng muốn thu khoản trải nhiều tháng phải cấu hình ngày áp dụng một lần, không tạo hệ kỳ tài chính thứ hai.
- **Ngày áp dụng/đối tượng:** Khoản một lần phát sinh nếu học sinh có khoảng tham gia vào ngày áp dụng. Không tự thu lại tiền tài liệu của ngày đã qua khi học sinh vào muộn. Định kỳ phát sinh một lần cho mỗi tháng/kỳ giao khoảng tham gia và khoảng lớp mở; vào giữa kỳ thu đủ, nghỉ/học lại trong cùng hồ sơ và kỳ không tạo trùng.
- **Cấu hình mới:** Ngày áp dụng sớm nhất là hôm nay; không tự sinh thêm khoản cho các kỳ quá khứ. Với định kỳ bắt đầu hôm nay ở giữa tháng/kỳ, tạo khoản hiện tại cho học sinh đang tham gia, giữ ngày áp dụng thực tế không lùi về đầu kỳ. Học sinh được chọn thêm sau đó chỉ chịu các lần phát sinh từ lúc được chọn nếu còn tham gia.
- **Sửa/xóa cấu hình:** Chỉ ảnh hưởng lần phát sinh từ thời điểm thay đổi trở đi, không sửa các khoản đã tạo. Xóa mềm cấu hình ngừng phát sinh mới, giữ khoản đã phát sinh và lịch sử; tác vụ không tự tạo lại khoản đã chủ động hủy.
- **Sửa khoản đã tạo:** Admin/Receptionist được sửa tên/số tiền hoặc hủy nghĩa vụ của khoản ngoài học phí chưa thu, bắt buộc lý do, lưu phiên bản. Khoản đã thu phải được Admin gỡ bản thu sai trước theo FEE-06; lịch sử thu cũ không đổi. Không tạo lại cùng lần phát sinh sau hủy; muốn thu một khoản khác phải cấu hình lần phát sinh mới.
- **Thu riêng/chung:** Được thu riêng khi học phí chưa đóng hoặc chọn chung với học phí trong cùng lần thu cho một học sinh/một lớp. Giữ chi tiết riêng và số tiền từng khoản; cả lựa chọn cùng thành công/thất bại theo FEE-05.
- **Sau lưu trữ hồ sơ:** Khoản đã phát sinh vẫn giữ nợ/tiền và truy đúng hồ sơ cũ. Thêm lại hồ sơ mới áp dụng các lần phát sinh còn phù hợp từ ngày vào mới; khoản một lần đã qua không tự lặp, định kỳ tháng/kỳ hiện tại tạo khoản mới theo D07.
- **Nghiệm thu:** Thu riêng/chung đúng tổng và quyền; chạy lại, nghỉ rồi học lại không tạo trùng trong cùng hồ sơ; thay cấu hình không đổi khoản đã có. Một lớp không tự nhận khoản của lớp khác.
- **Giới hạn lớp:** Ngày áp dụng nằm trong ngày mở/kết thúc lớp tại lúc cấu hình; không phát sinh khoản hiện tại chỉ vì vừa cấu hình nếu lớp Đóng/lưu trữ. Khi Mở lại chỉ tạo lần phát sinh còn đủ điều kiện, không bù tháng/kỳ nằm trọn trong khoảng đóng.

### C.13. Đồng bộ dữ liệu Excel

#### XLS-01. Đồng bộ học sinh tại danh sách tổng

- **Mục đích:** Thêm, xóa, sửa thông tin học sinh hàng loạt bằng Excel tại trang danh sách tổng.
- **Người thực hiện:** Admin/Receptionist được thêm/sửa/xóa; User chỉ sửa hồ sơ hiện có trong phạm vi STU-04, không thêm/xóa/khôi phục.
- **Phạm vi dữ liệu:** Hồ sơ học sinh trong danh sách tổng; các trường và kiểm tra trùng theo STU-04.
- **Luồng nghiệp vụ:** Người có quyền cung cấp dữ liệu Excel; hệ thống kiểm tra quyền, đối chiếu bản ghi và thực hiện các thao tác thêm/xóa/sửa theo quy tắc đồng bộ được thống nhất.
- **Kết quả:** Danh sách tổng được cập nhật theo các thao tác hợp lệ.
- **Tiêu chí nghiệm thu:** Admin và Receptionist thực hiện được cả ba thao tác bằng Excel; User chỉ sửa đúng phạm vi STU-04. File của User có dòng thêm, xóa hoặc sửa học sinh ngoài phạm vi phải bị từ chối toàn bộ ở preview/apply; phân công bị thu hồi sau preview phải chặn apply. Không coi dòng thiếu mã là yêu cầu tạo mới được phép cho User.
- **Khóa nhận diện:** Dùng mã học sinh duy nhất theo XLS-05; cột mã trong file xuất được ẩn mặc định.
- **Quy tắc xóa:** Xóa mềm và tự đưa học sinh khỏi mọi lớp, giữ toàn bộ lịch sử theo STU-01. Áp dụng cả khi xóa qua Excel tại danh sách tổng.
- **Kiểm tra hồ sơ:** Chỉ tên học sinh bắt buộc; trường khác được trống; kiểm tra trùng theo STU-04.

#### XLS-02. Đồng bộ học sinh tại lớp học

- **Quyền:** Admin/Receptionist thêm/sửa/xóa theo nghiệp vụ; User có phân công đang hiệu lực chỉ sửa lần tham gia theo STU-03 trong đúng lớp, không thêm/xóa/hủy/khôi phục. Lớp phải không xóa mềm; lớp Đóng chỉ cho sửa ghi chú, ghi nghỉ hoặc lưu trữ hồ sơ theo quyền từng vai trò, không nhập học mới.
- **Thêm:** Chỉ liên kết học sinh tổng chưa xóa mềm; có mã thì đối chiếu mã, mã sai không rơi về tra tên. Không có mã thì dùng tên chuẩn hóa, bổ sung số phụ huynh nếu tên trùng theo STU-04/XLS-06. Không tự tạo hoặc khôi phục hồ sơ tổng từ file lớp.
- **Hồ sơ/lần tham gia:** Nếu còn hồ sơ tại lớp chưa xóa, thêm lần tham gia mới không chồng thời gian. Nếu mọi hồ sơ cũ tại lớp đã xóa mềm, tạo hồ sơ mới và lần tham gia mới; sinh khoản mới theo FEE-07, không tự lấy khoản đã đóng của hồ sơ cũ.
- **Sửa:** Chỉ ghi chú lớp và ngày nghỉ lần đầu; ngày vào đã lưu hoặc ngày nghỉ đã có không đổi/xóa; trạng thái tự tính. Dòng sửa phải có mã học sinh, mã hồ sơ lớp, mã lần tham gia và phiên bản đúng. Không sửa tên/liên hệ/ngày sinh/trường/ghi chú tổng quan qua file lớp.
- **Xóa khỏi lớp:** Trên giao diện và cột Thao tác = Xóa đều là xóa mềm hồ sơ học sinh–lớp đang chọn cùng việc kết thúc/hủy các lần tham gia hiện hành. Giữ toàn bộ điểm, nhận xét, điểm danh và tài chính; không có xóa dây chuyền học vụ. Receptionist không được sửa/xóa học vụ độc lập. Những hồ sơ lưu trữ trước đó giữ nguyên.
- **Công nợ:** Không chặn xóa mềm vì có nợ, không xóa nợ hoặc thu cũ. Ngừng nghĩa vụ tương lai không còn đối tượng áp dụng theo FEE-07; tài chính đã phát sinh tiếp tục xem/thu đúng quyền. Giữ lịch sử nguồn để chạy bù lỗi còn thiếu, không xem xóa mềm là đã thanh toán.
- **Sau xóa:** Ẩn học sinh khỏi danh sách hoạt động và tra cứu phụ huynh ở lớp nếu không còn hồ sơ chưa xóa. Admin/Receptionist truy hồ sơ lưu trữ; User có phân công hiện hành chỉ đọc học vụ/chuyên cần lịch sử của lớp, không đọc tài chính. Hồ sơ tổng/lớp khác không thay đổi.
- **Thêm lại:** Không khôi phục hồ sơ lớp cũ; tạo hồ sơ mới theo CLASS-04/D07. Cần giữ tên/lịch sử hồ sơ cũ để đối chiếu. Phụ huynh được tra hợp các khoảng tham gia cũ/mới khi đã có hồ sơ lớp mới hợp lệ theo PORTAL-02.
- **Excel:** Xem trước, chặn cả file khi lỗi/xung đột; một thao tác xóa cùng học sinh/hồ sơ không được lặp trong file. Không hỗ trợ Thao tác = Khôi phục; lỗi audit hủy cả lần áp dụng.
- **Nghiệm thu:** Xóa có nợ vẫn giữ nợ và toàn bộ học vụ; sau thêm lại cùng tháng có khoản mới, khoản cũ/thu cũ còn nguyên. Không cập nhật hồ sơ tổng từ file lớp, không nhận mã hoặc khoảng ngày không hợp lệ. User sửa được đúng lớp/phạm vi/trường theo STU-03; một dòng thêm/xóa hoặc ngoài quyền chặn toàn bộ file, kể cả khi quyền thay đổi giữa preview và apply.

#### XLS-03. Đồng bộ điểm và nhận xét trong lớp

- **Mục đích:** Thêm, xóa, sửa điểm và nhận xét hàng loạt bằng Excel.
- **Người thực hiện:** Admin; giáo viên hoặc trợ giảng có phân công đang hiệu lực trong lớp.
- **Phân quyền:** Receptionist không được thay đổi điểm hoặc nhận xét qua Excel. Trợ giảng không được dùng Excel để công bố/hủy công bố dữ liệu.
- **Luồng nghiệp vụ:** Người có quyền chọn lớp và phạm vi điểm/nhận xét, cung cấp dữ liệu Excel; hệ thống đối chiếu học sinh và các bản ghi học vụ, kiểm tra dữ liệu rồi áp dụng các thao tác hợp lệ.
- **Kết quả:** Điểm và nhận xét được cập nhật trong lớp theo phạm vi quyền của người thực hiện.
- **Tiêu chí nghiệm thu:**
  - Admin, giáo viên và trợ giảng đủ quyền thực hiện được thêm/xóa/sửa điểm và nhận xét bằng Excel.
  - Receptionist và người không có quyền với lớp không thực hiện được các thay đổi này.
  - Đồng bộ không cấp thêm quyền công bố cho trợ giảng.
- **Quy tắc mẫu:** Phải tạo bài kiểm tra/đợt nhận xét trên giao diện trước rồi tải mẫu của đúng chức năng. Không tạo bài/đợt bằng Excel; nhập điểm, điểm thành phần hoặc nhận xét theo mẫu tương ứng tại XLS-06.
- **Đã chốt:** Ô trống giữ nguyên khi sửa; xóa giá trị phải chỉ định riêng và vẫn tuân theo khóa công bố.
- **Học vụ lịch sử:** Mẫu xuất theo ngày bài và khoảng tham gia, gồm dữ liệu học sinh/hồ sơ lớp đã lưu trữ nếu có lịch sử phù hợp. Được sửa lịch sử đúng quyền khi lớp không lưu trữ; nhập file không tự khôi phục hồ sơ hoặc tạo bản sao kết quả theo lần tham gia.

#### XLS-04. Quy tắc đồng bộ chung

- Quyền được kiểm tra ở backend như khi thao tác trực tiếp, bao gồm quyền mới nhất và hiệu lực phân công lớp.
- **Cơ chế:** Đồng bộ bằng tải file Excel lên để cập nhật; hỗ trợ tải dữ liệu từ hệ thống xuống, sửa bằng Excel rồi tải lên lại. Không kết nối đồng bộ liên tục với file Excel trực tuyến.
- **Luồng sử dụng:**
  1. Người dùng chọn phạm vi dữ liệu được phép thao tác: học sinh tổng, học sinh của lớp, điểm hoặc nhận xét trong lớp.
  2. Người dùng tải dữ liệu tương ứng xuống file Excel và chỉnh sửa trên file.
  3. Người dùng tải file lên đúng phạm vi cần cập nhật.
  4. Hệ thống kiểm tra quyền hiện tại, cấu trúc file và dữ liệu; đối chiếu bản ghi để xử lý thêm/sửa/xóa theo XLS-04 đến XLS-06 và quy tắc của nghiệp vụ tương ứng.
  5. Hệ thống hiển thị bản xem trước các thay đổi Thêm/Sửa/Xóa và các lỗi; chưa cập nhật dữ liệu nghiệp vụ.
  6. Người dùng kiểm tra và xác nhận áp dụng hoặc hủy.
  7. Chỉ sau khi xác nhận, hệ thống kiểm tra lại điều kiện áp dụng, cập nhật dữ liệu theo chính sách chặn toàn bộ khi có lỗi của XLS-04 và thông báo kết quả.
- **Tiêu chí nghiệm thu đã xác định:** Tải được dữ liệu trong phạm vi được phép xuống Excel và tải file đã chỉnh sửa lên để cập nhật. Quyền thao tác được kiểm tra lại khi tải lên; có file tải xuống không đồng nghĩa có quyền cập nhật dữ liệu.
- **Định dạng:** Chỉ nhận `.xlsx` theo mẫu hệ thống; file thao tác trong một lớp và một bài kiểm tra/đợt nhận xét tương ứng khi nhập học vụ. Không tạo bài/đợt qua file. Cấu trúc cột, giới hạn file và kiểm tra dữ liệu theo XLS-06.
- **Định danh:** Bản ghi có sẵn dùng mã học sinh cột ẩn theo XLS-05; thêm vào lớp không có mã dùng tra cứu tên/số phụ huynh theo XLS-06. Mẫu nhập học vụ gắn đúng bài/đợt đã tạo trước, không đối chiếu bằng tên bài tùy ý.
- **Xóa giá trị ô:** Khi cập nhật, ô trống giữ nguyên dữ liệu cũ; nhập đúng ký hiệu `XÓA` để yêu cầu xóa giá trị. Chỉ xóa khi trường và nghiệp vụ cho phép, vẫn tuân theo trường bắt buộc và khóa công bố. Ký hiệu trong ô dữ liệu không thay thao tác xóa cả bản ghi tại cột Thao tác.
- **Lỗi định danh:** Trùng khóa của đối tượng, mất cột mã học sinh hoặc không xác định được hồ sơ/lần tham gia khi sửa thông tin tham gia lớp đều chặn toàn bộ file, không bỏ riêng dòng lỗi. Thông báo nguyên nhân và yêu cầu người dùng tải file mới từ hệ thống, chỉnh sửa rồi tải lên lại. Việc để trống mã cho dòng thêm mới hợp lệ vẫn theo XLS-05/XLS-06.
- **Cách xác định thao tác:**
  - Dòng không đánh dấu xóa: đối chiếu với bản ghi trong hệ thống; nếu xác định là bản ghi đã tồn tại thì cập nhật, nếu là bản ghi mới thì thêm. Không yêu cầu người dùng khai báo Thêm/Sửa trong cột “Thao tác”.
  - Dòng đánh dấu Xóa tại cột “Thao tác”: thực hiện xóa bản ghi đích sau khi đối chiếu và kiểm tra quyền, điều kiện xóa của nghiệp vụ tương ứng; không xử lý dòng này như yêu cầu thêm hoặc sửa.
  - Bản ghi không xuất hiện trong file được giữ nguyên, không tự xóa.
  - Không hỗ trợ khôi phục hồ sơ học sinh qua Excel. File hồ sơ tổng/lớp tham chiếu hồ sơ đã xóa mềm không tự khôi phục hoặc sửa như đang hoạt động; báo lỗi và yêu cầu khôi phục hồ sơ tổng trên giao diện, hoặc thêm hồ sơ lớp mới theo XLS-02. File học vụ được sửa dữ liệu lịch sử của học sinh đã xóa mềm nếu lớp không xóa, còn quyền học vụ và đúng khoảng tham gia; không đổi trạng thái hồ sơ.
  - Giá trị Khôi phục trong cột Thao tác không được hỗ trợ; báo lỗi và chặn toàn bộ lần đồng bộ theo chính sách lỗi.
  - Quy tắc áp dụng cho học sinh ở danh sách tổng, học sinh trong lớp, điểm và nhận xét trong lớp.
- **Tiêu chí nghiệm thu thao tác:** Dòng mới được thêm, dòng khớp bản ghi hiện có được cập nhật, dòng đánh dấu Xóa được xử lý theo nghiệp vụ xóa; bản ghi ngoài file không bị thay đổi do thiếu dòng.
- **Xem trước và xác nhận đã thống nhất:**
  - Sau khi tải file, hiển thị các bản ghi sẽ thêm, sửa, xóa cùng số lượng theo từng nhóm và danh sách lỗi phát hiện được.
  - Với dòng sửa, hiển thị thông tin hiện tại và thay đổi dự kiến để người dùng đối chiếu.
  - Lỗi được gắn với dòng/cột tương ứng nếu xác định được, kèm nội dung cần sửa.
  - Chưa thay đổi dữ liệu nghiệp vụ trong bước kiểm tra và xem trước.
  - Chỉ áp dụng thay đổi khi người dùng chủ động xác nhận; hủy hoặc rời bước xem trước không cập nhật dữ liệu.
  - Kiểm tra lại quyền và điều kiện nghiệp vụ khi xác nhận; bản xem trước không cho phép vượt quyền hoặc bỏ qua điều kiện đã thay đổi.
- **Tiêu chí nghiệm thu xem trước:** Tải file lên chưa làm thay đổi dữ liệu; người dùng xem được thay đổi và lỗi trước khi xác nhận; hủy giữ nguyên dữ liệu; áp dụng chỉ bắt đầu sau xác nhận.
- **Chính sách lỗi — chặn toàn bộ:**
  - Nếu phát hiện bất kỳ lỗi nào trong file, không cho phép xác nhận áp dụng; không thêm, sửa hoặc xóa bất kỳ bản ghi nghiệp vụ nào trong lần đồng bộ đó.
  - Vẫn hiển thị bản xem trước và danh sách lỗi để người dùng đối chiếu, sửa file rồi tải lại kiểm tra.
  - Chỉ cho xác nhận áp dụng khi toàn bộ file hợp lệ; không có lựa chọn bỏ qua dòng lỗi để nhập riêng các dòng hợp lệ.
  - Khi áp dụng, nếu kiểm tra lại phát hiện lỗi hoặc một thao tác ghi thất bại, hủy toàn bộ thay đổi của lần đồng bộ; không để lại dữ liệu cập nhật một phần.
- **Tiêu chí nghiệm thu xử lý lỗi:** File có cả dòng đúng và dòng lỗi không làm thay đổi dữ liệu; sau khi sửa hết lỗi và tải lại, người dùng mới được xác nhận; lỗi khi áp dụng không để lại kết quả thêm/sửa/xóa dở dang.
- **Audit đồng bộ:** Mỗi lần áp dụng thành công tạo một mục audit chứa toàn bộ chi tiết thay đổi theo AUD-01; không ghi riêng từng dòng.
- **Xử lý xung đột:**
  - Khi xuất Excel, lưu phạm vi/phiên bản mẫu trong `_Meta` và phiên bản từng dòng trong cột ẩn `PhienBan` theo XLS-06; đối chiếu lại phiên bản ở backend.
  - Khi tải lên, đối chiếu dữ liệu hiện tại với phiên bản lúc xuất đối với các bản ghi mà file yêu cầu cập nhật hoặc xóa, gồm trạng thái hồ sơ và các sự kiện liên quan bị tác động bởi lưu trữ.
  - Nếu bản ghi đã được người khác hoặc tác vụ hệ thống thay đổi sau khi xuất, báo xung đột và chặn toàn bộ lần đồng bộ; không ghi đè dữ liệu mới bằng file cũ.
  - Người dùng phải tải lại dữ liệu mới, đối chiếu và chỉnh sửa rồi tải lên lại để kiểm tra.
  - Kiểm tra lại xung đột khi xác nhận áp dụng, bao gồm thay đổi phát sinh sau bước xem trước; nếu có xung đột, hủy toàn bộ lần áp dụng và giữ nguyên dữ liệu hiện tại.
  - Lần đồng bộ bị chặn hoặc bị hủy do xung đột không tạo audit thay đổi dữ liệu.
- **Tiêu chí nghiệm thu xung đột:** File xuất trước một thay đổi không ghi đè được bản ghi đã thay đổi; xung đột trên một bản ghi chặn toàn bộ lần đồng bộ; thay đổi phát sinh giữa xem trước và xác nhận cũng được phát hiện.
- **Chống nhập lại file:**
  - Không cho áp dụng lại đúng file đã đồng bộ thành công trong cùng phạm vi nghiệp vụ và lớp tương ứng, kể cả khi đổi tên file hoặc do người dùng khác tải lên.
  - Hệ thống lưu dấu nhận diện lần xử lý thành công; không chỉ dựa vào tên file để nhận diện.
  - Khi phát hiện file đã được xử lý thành công, báo rõ và chặn toàn bộ lần đồng bộ; không thêm/sửa/xóa dữ liệu hoặc tạo thêm audit thay đổi dữ liệu.
  - File chỉ mới xem trước, bị người dùng hủy, có lỗi hoặc áp dụng thất bại không được đánh dấu đã đồng bộ thành công; có thể tải lại để kiểm tra và thử lại theo các điều kiện hiện hành.
  - Việc kiểm tra file trùng được thực hiện lại trước khi áp dụng để tránh hai phiên cùng xử lý một file.
- **Tiêu chí nghiệm thu nhập lại:** Tải lại file đã thành công không làm tăng số học sinh hoặc áp dụng lần nữa các thay đổi; đổi tên file không vượt qua kiểm tra; file chưa từng thành công không bị chặn chỉ vì đã tải lên trước đó.

#### XLS-05. Mã học sinh trong cột ẩn

- **Mục đích:** Đối chiếu chính xác học sinh khi đồng bộ, không dựa vào họ tên hoặc số điện thoại có thể bị trùng hay thay đổi.
- **Quy tắc nghiệp vụ:**
  - Mỗi học sinh có một mã duy nhất do hệ thống cấp, dùng thống nhất giữa danh sách tổng và các lớp.
  - File Excel xuất từ hệ thống chứa mã học sinh trong một cột riêng được ẩn mặc định, không hiển thị trong vùng dữ liệu khi mở file thông thường.
  - Khi chỉnh sửa hoặc đánh dấu xóa học sinh hiện có, giữ nguyên mã trong dòng tương ứng; thay đổi tên hoặc số điện thoại không tạo thành học sinh khác.
  - Khi tạo học sinh mới tại danh sách tổng, để trống mã; hệ thống tự cấp mã sau khi thêm thành công. Thêm học sinh vào lớp phải dùng hồ sơ tổng và mã đã có, không áp dụng quy tắc cấp mã mới.
  - Mã được cấp sẽ có trong cột ẩn khi xuất lại dữ liệu.
  - Cột ẩn chỉ phục vụ cách hiển thị file, không phải cơ chế phân quyền hoặc bảo mật. Hệ thống vẫn kiểm tra mã và quyền ở backend khi nhận file.
- **Luồng đối chiếu học sinh:**
  1. Đọc mã học sinh trong cột ẩn của từng dòng.
  2. Nếu có mã hợp lệ thuộc học sinh hiện có, xác định đúng học sinh để xử lý sửa hoặc yêu cầu xóa theo cột “Thao tác”, trong phạm vi nghiệp vụ được chọn.
  3. Tại danh sách tổng, không có mã và không đánh dấu xóa thì kiểm tra hồ sơ mới và quy tắc trùng trước khi cấp mã. Tại lớp, dòng thêm chưa có mã dùng tên, bổ sung số điện thoại phụ huynh nếu cần phân biệt theo XLS-06; chỉ liên kết hồ sơ tổng có sẵn.
  4. Nếu mã được cung cấp không tồn tại hoặc người dùng không có quyền với bản ghi đích, báo lỗi; không tự coi dòng có mã sai là học sinh mới.
- **Tiêu chí nghiệm thu:**
  - Cột mã tồn tại và được ẩn mặc định trong file xuất.
  - Tại danh sách tổng, đổi tên hoặc số điện thoại nhưng giữ mã vẫn cập nhật đúng học sinh. Tại lớp, mã chỉ đối chiếu học sinh để thao tác quan hệ học sinh–lớp; không cập nhật hồ sơ chung.
  - Hai học sinh trùng tên hoặc số điện thoại được đối chiếu riêng bằng mã.
  - Dòng tạo học sinh mới tại danh sách tổng để trống mã được cấp mã duy nhất khi thêm thành công; đồng bộ tại lớp không cấp mã hoặc tạo hồ sơ tổng mới.
  - Mã đã cung cấp nhưng không hợp lệ phải báo lỗi, không tự chuyển sang tra tên để sửa nhầm bản ghi; dòng thêm lớp không có mã chỉ được liên kết khi tra cứu duy nhất theo XLS-06.

#### XLS-06. Mẫu Excel theo chức năng và cấu trúc đối chiếu

- **Phạm vi:** Chỉ `.xlsx` từ mẫu hệ thống. Một file cho danh sách tổng hoặc một lớp; học vụ gắn đúng một bài kiểm tra/đợt đã tạo trên giao diện. Không tạo bài/đợt hoặc khôi phục hồ sơ từ file.
- **Cấu trúc:** Một sheet dữ liệu `DuLieu` và sheet ẩn `_Meta` chứa phiên bản mẫu, phạm vi, mã lớp/bài/đợt, cấu trúc phần và phiên bản dữ liệu. Cột kỹ thuật ẩn mặc định, không phải cơ chế bảo mật; backend kiểm tra toàn bộ. Không nhận công thức hoặc macro làm dữ liệu nghiệp vụ, không thực thi công thức khi đọc.
- **Cột chung:** `MaHocSinh` (ẩn), `ThaoTac` (trống hoặc Xóa); dòng sửa có `PhienBan` ẩn. Dòng thiếu mã chỉ hợp lệ trong luồng thêm mới/đối chiếu thêm vào lớp. Giá trị ThaoTac khác bị lỗi; dòng trống toàn bộ được bỏ qua.
- **Học sinh tổng:** `HoTen`, `TenPhuHuynh`, `SDTPhuHuynh`, `SDTHocSinh`, `NgaySinh`, `Truong`, `GhiChuTongQuan`; nhiều số cách nhau bằng dấu `;`. Thêm mới để trống mã; sửa/xóa bắt buộc mã. Ngày là ô ngày Excel hoặc `YYYY-MM-DD`, không suy đoán định dạng ngày mơ hồ.
- **Học sinh tại lớp:** `HoTenDoiChieu`, `SDTPhuHuynhDoiChieu`, `NgayVao`, `NgayNghi`, `GhiChuLop`; thêm mã ẩn `MaHoSoLop` và `MaLanThamGia` cho dòng cũ. Tên/số chỉ dùng nhận diện khi thêm, không sửa hồ sơ tổng. Sửa ngày tuân theo STU-03. Dòng Xóa nhắm hồ sơ lớp và lưu trữ mọi lần tham gia của hồ sơ đó theo XLS-02.
- **Nhận diện khi thêm:** Tra tên chuẩn hóa trên hồ sơ tổng; một kết quả thì dùng hồ sơ đó, nhiều kết quả phải có số phụ huynh chuẩn hóa để chọn duy nhất. Không có hoặc còn nhiều kết quả thì chặn, không đoán/tạo mới. Học sinh tổng đã xóa mềm phải khôi phục trên giao diện trước.
- **Điểm:** `Vang` nhận Có/Không; thang số nhập `Diem`, phân số nhập `SoCauDung`, thang chữ nhập `MucChu`; cấu hình của bài nằm trong `_Meta`. Theo phần xuất một cột mỗi phần có mã phần ánh xạ trong `_Meta`, tổng chỉ để hiển thị không làm nguồn cập nhật. Không nhập điểm đồng thời Vắng; thiếu phần được lưu chưa hoàn tất theo TEST-04.
- **Điểm IELTS:** `_Meta` lưu phiên bản cấu hình bài, tập kỹ năng, chế độ nhập từng kỹ năng và mã tiêu chí/Task. L/R chi tiết có số câu đúng và band nhập tay; trực tiếp chỉ có band. Writing chi tiết có tám ô tiêu chí chia hai Task; Speaking chi tiết có bốn ô tiêu chí; chế độ trực tiếp chỉ có band kỹ năng. Điểm Task, band W/S tự tính và Overall chỉ là cột hiển thị khi được tính tự động, không phải đầu vào ghi đè. Backend tính theo TEST-01; chặn cột/chế độ không khớp phiên bản bài. Thiếu dữ liệu được lưu chưa hoàn tất như UI; Vắng cả bài không kèm điểm; template chung mới không làm thay đổi cách đọc file của bài cũ.
- **Nhận xét:** Mẫu riêng chứa `NhanXet` cho đúng bài hoặc đợt; không thay điểm hoặc công bố. Khóa kết quả theo học sinh/bài hay học sinh/đợt, không theo lần tham gia.
- **Xóa/giá trị trống:** Ô trống khi sửa giữ nguyên; `XÓA` yêu cầu xóa giá trị nếu nghiệp vụ cho phép, không thay thao tác Xóa bản ghi. Xóa bản ghi không tồn tại là lỗi, chặn file; không coi là thêm mới hoặc thành công giả. Dữ liệu trước thay đổi giữ trong lịch sử nghiệp vụ theo A.3.
- **Giới hạn:** Mọi file phải dưới 10.000.000 byte và tối đa 5.000 dòng dữ liệu không tính tiêu đề/dòng trống. Từ chối file đạt 10.000.000 byte hoặc có 5.001 dòng; không tự cắt bớt dòng.
- **Trùng/xung đột:** Khóa dòng tùy đối tượng: học sinh tổng; hồ sơ lớp/lần tham gia; hoặc học sinh/bài/đợt. Các lần tham gia khác nhau không trùng chỉ vì cùng học sinh; các dòng mới vẫn kiểm tra chồng khoảng và trùng hồ sơ. Kiểm tra phiên bản khi tải lên và xác nhận, bao gồm trạng thái công bố/lưu trữ và dữ liệu có liên quan.
- **Chống nhập lại:** Dấu nhận diện nội dung file đã thành công gắn phạm vi/lớp/bài/đợt được giữ không thời hạn, độc lập audit; đổi tên file không vượt qua. Không đánh dấu file mới xem trước, hủy hoặc lỗi. File không có thay đổi được báo Không có thay đổi, không tạo audit thay đổi hoặc đánh dấu đã nhập.
- **Nghiệm thu:** Đúng mẫu/phạm vi/phiên bản mới áp dụng; lỗi một dòng chặn toàn bộ, thành công có một audit chung; file chỉnh điểm không cập nhật hồ sơ tổng hoặc công bố. Các trường nhận diện dùng chung chuẩn hóa STU-04.

### C.14. Nhật ký kiểm toán

#### AUD-01. Audit và tác vụ tự động

- **Quyền:** Chỉ Admin truy vấn audit, kể cả khi Receptionist/User là người thực hiện thao tác. Không ai sửa/xóa audit thủ công qua UI/API.
- **Phạm vi:** Mọi thay đổi dữ liệu nghiệp vụ thành công từ UI/API/Excel/tác vụ đều có audit: hồ sơ, lịch, học vụ, công bố, phân công, tài khoản, tài chính và xóa mềm/khôi phục. Thất bại, bị chặn, hủy xem trước hoặc không có thay đổi không tạo audit thành công.
- **Thông tin:** Người/tác vụ thực hiện, thời điểm thực tế, nguồn, thao tác, định danh học sinh/lớp/đối tượng, mã lần nhập nếu có, dữ liệu trước/sau và kết quả. Thêm mới lưu sau, xóa mềm lưu trước/sau cờ và sự kiện kết thúc; thay học vụ lưu phiên bản trước/sau.
- **Bí mật:** Không lưu mật khẩu, băm mật khẩu, link/token đặt lại hoặc thông tin xác thực phiên; chỉ ghi nhận sự kiện đổi xác thực.
- **Thời hạn:** Audit lưu đúng 60 ngày kể từ thời điểm tạo rồi tự xóa, không gia hạn vì xem. Thông báo cũng có hạn riêng theo NOTIF-01. Xóa audit/thông báo hết hạn không tạo audit thay thế để tránh chuỗi tự sinh vô hạn.
- **Lịch sử nghiệp vụ:** Hồ sơ lưu trữ, phiên bản học vụ/cấu hình và lịch sử thu/hủy được giữ độc lập, không mất khi audit đủ 60 ngày. Audit không là nguồn duy nhất để dựng lịch sử hoặc khôi phục dữ liệu; không dùng audit trả dữ liệu công khai.
- **Nguyên khối:** Audit và thay đổi nghiệp vụ cùng thành công/thất bại. Không ghi được audit thì hủy toàn bộ thay đổi của thao tác. Một lần Excel thành công chỉ có một mục audit chứa mọi chi tiết; lỗi audit hủy cả file. Một lần thu/gỡ thu hoặc đóng/mở/xóa/khôi phục lớp cũng nguyên khối với toàn bộ lựa chọn.
- **Tra cứu:** Lọc khoảng thời gian, người thực hiện, loại thao tác, học sinh, lớp, mã đối tượng/lần nhập; phân trang. Phản hồi backend kiểm tra quyền Admin.
- **Quét/chạy bù:** Kiểm tra mốc đến hạn ít nhất mỗi 5 phút theo A.3; sau gián đoạn quét các mốc bỏ lỡ. Quyền, điều kiện bắt đầu/đã nghỉ và hạn token xét thời gian yêu cầu, không đợi quét. Dùng lịch sử khoảng mở/đóng/lưu trữ và tham gia theo FEE-07, không tạo bù cho thời gian không đủ điều kiện.
- **Đơn vị tác vụ:** Một nghĩa vụ cùng audit là một đơn vị nguyên khối; lỗi một nghĩa vụ không hủy đơn vị khác đã thành công. Không áp cách chia nhỏ này cho Excel, thu/gỡ thu và thao tác vòng đời lớp. Chạy lại hoặc đồng thời phải nhận diện sự kiện đã xử lý, không nhân đôi khoản, audit hoặc thông báo.
- **Thử lại:** Lỗi kỹ thuật thử sau 1, 5, 15 phút rồi mỗi giờ, tối đa 24 giờ từ lỗi đầu; sau đó Chờ Admin xử lý, cho Admin yêu cầu thử lại. Lỗi dữ liệu như thiếu mức thu chỉ kiểm tra lại sau khi dữ liệu liên quan thay đổi; không gửi thông báo lặp mỗi lượt quét.
- **Theo dõi lỗi:** Admin thấy loại, đối tượng, mốc, lần thử, lỗi cuối và hướng xử lý. Nhật ký lỗi vận hành không phải audit thành công, không chứa bí mật. Lỗi thông báo không làm mất nguồn lỗi hoặc đảo nghiệp vụ đã thành công.
- **Nghiệm thu:** Mô phỏng lỗi audit giữ nguyên dữ liệu, không có thay đổi một phần; một file nhiều dòng có đúng một audit. Hết 60 ngày audit mất nhưng học vụ/thu/hủy và hồ sơ lưu trữ còn; chạy bù không thu trùng hoặc bỏ nợ chỉ vì hồ sơ nay đã xóa mềm.

### C.15. In ấn và dashboard

#### REPORT-01. In điểm danh, giấy báo học phí và biên nhận theo mẫu Word

- **Quyết định thay thế ngày 28/10/2026:** Bổ sung biên nhận thu và mẫu Word `.docx` do Admin tải lên cho giấy báo/biên nhận, hỗ trợ cả tải Word đã điền và preview/in ngay trong ứng dụng. Thay quy định cũ không có biên nhận; giữ mã REPORT-01. Chọn xử lý/render tại trình duyệt với tập bố cục DOCX giới hạn được kiểm thử, không yêu cầu tương thích mọi tài liệu Word hoặc một dịch vụ chuyển đổi DOCX → PDF.
- **Quyền:** Chỉ Admin quản lý mẫu, phiên bản và mẫu mặc định. Admin/Receptionist được chọn mẫu đang dùng để xem/tải/in giấy báo và biên nhận đúng phạm vi; Receptionist không xem/in tổng tiền toàn trung tâm. User chỉ in điểm danh lớp có phân công hiệu lực, không được đọc mẫu tài chính hoặc dữ liệu/file giấy báo, biên nhận qua UI/API/Storage. Quyền được kiểm tra lại khi lấy dữ liệu và template, không chỉ khi mở màn hình.
- **Điểm danh A4:** Theo lớp/tháng, danh sách xét đúng khoảng tham gia; lịch sau điều chỉnh, kết quả hiện hành, ô chưa điểm danh để trống. Phân biệt buổi nghỉ/lễ với học sinh Vắng; dữ liệu lưu trữ có nhãn khi được chọn xem lịch sử.
- **Giấy báo A5:** Theo học sinh/lớp và tháng hoặc kỳ được chọn; liệt kê mức gốc học phí, điều chỉnh có dấu và lý do ngắn, khoản ngoài học phí, số phải thu/trạng thái và tổng cần đóng của các nghĩa vụ còn hiệu lực. Không cộng các khoản đã thu/Không phải thu vào tổng cần đóng. Có tên trung tâm, tên lớp/học sinh, kỳ, ngày in; không tự thêm thông tin tài khoản ngân hàng chưa cấu hình.
- **Biên nhận:** Một biên nhận cho một lần thu thành công của một học sinh/một lớp theo FEE-05; không phát hành cho khoản chưa thu hoặc Không phải thu. Có mã biên nhận, tên trung tâm/học sinh/lớp, thời điểm thu, người thu, phương thức, các khoản/tháng/kỳ, mức gốc/điều chỉnh/số thực thu và tổng đã thu. In lại dùng mã và dữ liệu giao dịch gốc, phân biệt ngày thu với ngày in lại, không tạo lần thu mới.
- **Gỡ thu/in lại:** Theo FEE-06, khi gỡ một phần phải hiện rõ khoản nào bị hủy, tổng giao dịch gốc và phần còn hiệu lực, cùng nhãn không còn hiệu lực nguyên trạng; khi gỡ toàn bộ hiện Không còn hiệu lực. Nội dung trạng thái là bắt buộc, mẫu không được bỏ để in một biên nhận có vẻ còn nguyên hiệu lực. Không thể thu hồi/sửa từ xa bản giấy hoặc file đã tải; trạng thái đúng được bảo đảm trên hệ thống và những lần lấy bản mới.
- **Thư viện mẫu in:** Có nhiều mẫu cho mỗi loại Giấy báo học phí/Biên nhận, dùng chung toàn trung tâm; mỗi loại có một mẫu mặc định đang hoạt động do Admin chọn, được chọn sẵn khi tạo bản in mới. Người có quyền in được chọn mẫu hoạt động khác. Tải lên/thay mẫu tạo phiên bản mới; xóa mềm ngừng dùng mới nhưng giữ phiên bản đã tham chiếu. Không xóa mềm mẫu mặc định mà chưa chọn mẫu thay thế hợp lệ trong cùng thao tác.
- **Định dạng và bố cục:** Chỉ `.docx`, không `.doc`/`.docm`, macro hoặc tài liệu có mật khẩu. Hỗ trợ bộ bố cục đã kiểm chứng gồm đoạn văn, định dạng chữ, bảng, logo/ảnh nhúng trong dòng, header/footer và ngắt trang rõ. Không hỗ trợ tùy ý hộp chữ/shape nổi, đối tượng nhúng, tài nguyên ngoài hoặc field/mã thực thi. Giấy báo giữ A5; khổ biên nhận được khai báo trong mẫu thuộc tập khổ A4/A5 đã kiểm chứng. Phần không hỗ trợ phải báo cho Admin trước khi kích hoạt, không âm thầm làm mất nội dung.
- **Marker:** Dùng danh mục marker có kiểu/phạm vi do hệ thống công bố; ví dụ `{{ten_hoc_sinh}}`, `{{ten_lop}}`, `{{ma_bien_nhan}}`, `{{tong_tien}}` và vùng lặp dòng khoản thu. Marker là vị trí nội dung trong tài liệu, không phải tọa độ tuyệt đối; văn bản dài/số dòng tăng có thể làm dịch chuyển và ngắt trang. Không chạy biểu thức tùy ý, công thức hoặc mã từ file; số tiền/tổng/trạng thái do backend cung cấp. Marker sai/thiếu dữ liệu bắt buộc, vùng lặp không hợp lệ hoặc sai loại mẫu phải chặn kích hoạt/tạo file và chỉ rõ lỗi, không để `undefined` hoặc marker sót trên bản in.
- **Kích hoạt mẫu:** Admin xem thử bằng dữ liệu giả cả tên dài, nhiều khoản và nhiều trang rồi xác nhận. Chỉ mẫu qua kiểm tra mới được dùng/mặc định. Upload file và transaction DB riêng: commit metadata/phiên bản/default và audit nguyên khối; lỗi kiểm tra/commit giữ mẫu cũ, chỉ dọn file mới không còn tham chiếu. File mẫu ở Storage private, không công khai link chứa dữ liệu học sinh/tài chính.
- **Một bộ dữ liệu cho hai đầu ra:** API trả bản dữ liệu được cấp quyền cùng phiên bản mẫu xác định; trình duyệt điền một DOCX dùng để tải và làm nguồn preview/in. Preview/tải/in cùng lần phát hành phải dùng cùng số tiền, chi tiết và trạng thái. Nếu dữ liệu/phiên bản thay đổi trước khi lấy bản mới, tải lại và thông báo thay đổi; không trộn phần cũ/mới. Dữ liệu đã tải xuống có thể được sửa ngoài ứng dụng, không được coi file Word là chứng từ chống chỉnh sửa hoặc nguồn dữ liệu tài chính.
- **Phiên bản bản in:** Lưu bản chụp dữ liệu/định danh phiên bản mẫu cho lần phát hành đầu của biên nhận; in lại giữ dữ liệu giao dịch và phiên bản mẫu đó, đồng thời bổ sung trạng thái gỡ thu hiện hành bắt buộc. Đổi mẫu mặc định không thay biên nhận đã phát hành; giữ nguồn để dựng lại độc lập với audit 60 ngày. Giấy báo là thông tin nghĩa vụ ở lần lấy dữ liệu, không phải xác nhận đã thu.
- **Thao tác lô:** Preview và in trực tiếp bằng trình duyệt; giấy báo nhiều học sinh chia riêng theo học sinh/kỳ; biên nhận chia riêng theo lần thu. Không cắt mất cột/tên/khoản, không trộn người. Không bắt buộc xuất/lưu PDF riêng hoặc thêm giấy báo công nợ. Đặt giới hạn kỹ thuật cho file nén/giải nén, ảnh và số phiếu mỗi lượt sau kiểm chứng mẫu thực tế theo techstack; không suy giới hạn này từ Excel và không chia transaction thu tiền để phục vụ in lô.
- **Nghiệm thu:** Tải DOCX đã điền và preview/in đều hoạt động với bộ mẫu được hỗ trợ; giữ đúng dữ liệu, khổ giấy và không cắt nội dung trong tên dài/nhiều khoản/nhiều trang. Đổi default/xóa mẫu không làm hỏng in lại; marker lỗi bị chặn; User bị chặn API/file. Biên nhận chỉ sau commit, in lại không thu lần hai; gỡ một phần/toàn bộ hiển thị đúng, lỗi audit không để lại mẫu/default hoặc trạng thái tài chính thay đổi một phần. Chưa tuyên bố giữ bố cục như Microsoft Word trên mọi file/trình duyệt nếu chưa có bằng chứng render/print.

#### DASH-01. Dashboard và tổng hợp tài chính theo vai trò

| Workspace | Nội dung | Giới hạn |
| --- | --- | --- |
| Admin | Học sinh/lớp hoạt động, lịch hôm nay, Tổng phải thu/Chưa thu/Tổng thu, lỗi cấu hình/tác vụ, lối vào audit. | Tiền gồm cả khoản còn hiệu lực của hồ sơ lưu trữ; loại nghĩa vụ đã hủy và chi tiết thu đã hủy khỏi chỉ số tương ứng. |
| Receptionist | Lịch, buổi chưa điểm danh, tìm học sinh, khoản chưa thu theo học sinh/lớp và thao tác thu, tra lịch sử khoản của hồ sơ lưu trữ. | Không tổng tiền toàn trung tâm, không audit, không cấu hình điều chỉnh hoặc gỡ thu sai. |
| User | Lớp phụ trách, lịch, buổi chưa điểm danh, bài thiếu kết quả, nội dung chờ giáo viên công bố, thông báo. | Chỉ dữ liệu lớp theo phân công hiện hành, không tiền hoặc giấy báo học phí; trợ giảng không có nút công bố/xóa cả bài/đợt. |

- **Mặc định:** Lịch ngày hiện tại, tài chính Admin tháng hiện tại; luôn hiện rõ kỳ và phạm vi lọc. Admin đổi workspace thấy bộ thông tin của workspace được chọn, backend vẫn kiểm tra loại tài khoản.
- **Tiền:** VND nguyên đồng, cộng chính xác các số tiền đã lưu, không tính phần trăm hoặc tự làm tròn đầu vào. Tổng thu gồm học phí sau điều chỉnh và khoản ngoài học phí; lọc riêng được hai nhóm. Điều chỉnh đã nằm trong học phí, không cộng lần hai như một giao dịch thu độc lập.
- **Nghĩa vụ:** Tổng phải thu = tổng số phải thu hiện hành của nghĩa vụ còn hiệu lực thuộc kỳ lọc; Chưa thu chỉ cộng nghĩa vụ còn Chưa thu. Không phải thu thống kê số khoản riêng, không cộng vào tiền. Nghĩa vụ tháng lọc theo ngày đầu tháng, kỳ theo ngày đầu kỳ; khoản ngoài theo ngày áp dụng thực tế đã lưu.
- **Tiền nhận:** Tổng thu cộng chi tiết còn hiệu lực theo ngày nhận tiền, kể cả thu trước. Gỡ thu sai loại đúng chi tiết khỏi kỳ thu gốc khi truy vấn lại; dữ liệu phản ánh trạng thái hiện tại, không có khóa sổ. Không lấy Tổng phải thu trừ Tổng thu để suy Chưa thu khi dùng mốc lọc khác nhau.
- **Bộ lọc:** Khoảng ngày, lớp, học sinh/hồ sơ lớp và nhóm khoản trong quyền được cấp. Địa điểm chỉ lọc lịch/buổi, không lọc tiền vì lớp có thể học nhiều nơi; không nhân tiền theo địa điểm hoặc lần tham gia.
- **Nguồn lịch sử:** Giữ định danh học sinh, hồ sơ lớp, khoản, tháng/kỳ, mức gốc, phiên bản điều chỉnh, tiền thu, ngày/người/phương thức, tên học sinh/lớp tại lúc thu và mọi sự kiện hủy với lý do/người/thời điểm. Lưu độc lập với audit, không xóa khi hồ sơ/lớp lưu trữ. Mỗi chi tiết chỉ được cộng một lần; khoản cũ và mới sau xóa/thêm lại phân biệt theo mã hồ sơ.
- **Nghiệm thu:** Thu trước vào đúng kỳ nhận tiền; nghĩa vụ vào đúng kỳ áp dụng; gỡ một khoản chỉ giảm đúng tiền khoản đó. Hồ sơ lưu trữ vẫn giữ nợ/thu lịch sử; tạo hồ sơ mới theo D07 không ghi đè khoản cũ. User không nhận dữ liệu tiền qua API/dashboard/export/thông báo.

### C.16. Giao diện, thiết bị và thông báo

#### UX-01. Thiết bị, ngôn ngữ và giao diện

- **Thiết bị:** Tối ưu cả điện thoại và máy tính, gồm bảng dữ liệu, bộ lọc, điểm danh, xác nhận thu và trang phụ huynh. Thao tác có cùng quy tắc trên hai loại thiết bị.
- **Tùy chọn:** Tiếng Việt/tiếng Anh; sáng/tối/theo hệ thống. Lưu cục bộ theo thiết bị/trình duyệt, không đồng bộ theo tài khoản sang máy khác.
- **Hành vi:** Tải lại trang giữ lựa chọn còn lưu; chế độ theo hệ thống bám tùy chọn hệ điều hành. Xóa dữ liệu trình duyệt không làm mất dữ liệu nghiệp vụ nhưng có thể mất tùy chọn cục bộ.
- **Nghiệm thu:** Thiết bị khác có lựa chọn độc lập; thao tác cốt lõi dùng được trên màn hình nhỏ; không đổi quyền theo giao diện.

#### NOTIF-01. Thông báo trong ứng dụng

- **Phạm vi:** Danh sách theo người nhận, số chưa đọc, chi tiết, đánh dấu đã đọc và mở đối tượng theo quyền hiện tại; không thêm email/SMS/Zalo hoặc push hệ điều hành. Email đặt lại mật khẩu là luồng AUTH-02 riêng.
- **Sự kiện:** Thiếu mức thu/lỗi tác vụ gửi Admin; thay đổi khoản điều chỉnh gửi Receptionist để xem số tiền hiện hành; đổi lịch/đóng/mở lớp gửi nhân sự có phân công liên quan. Thông báo tài chính không gửi User; số tiền mới có hiệu lực được xem trực tiếp trên khoản liên quan.
- **Lưu/phân phối:** Lưu yêu cầu thông báo cùng nghiệp vụ thành công, phân phối sau; thử lại theo AUD-01 và chống trùng theo sự kiện/người nhận. Lỗi phân phối không đảo nghiệp vụ đã thành công; nếu không lưu được yêu cầu thông báo bắt buộc thì hủy giao dịch ban đầu.
- **Bảo vệ quyền:** Nội dung không chứa tổng tiền toàn trung tâm cho Receptionist/User. Khi đối tượng lưu trữ hoặc hết quyền, kiểm tra lại backend: người đủ quyền mở chế độ lịch sử; người không còn quyền thấy thông báo Đối tượng không còn truy cập được, không lộ nội dung bị chặn.
- **Thời hạn:** Lưu 60 ngày từ lúc tạo, tự xóa; không xóa thủ công, đánh dấu đã đọc không gia hạn. Danh sách/số chưa đọc tự cập nhật khi có mới mà không cần tải lại.
- **Nghiệm thu:** Đúng người/đúng quyền, không tạo thông báo lặp khi tác vụ thử lại; hết hạn giảm đúng số chưa đọc, nghiệp vụ/hồ sơ lịch sử không bị xóa theo thông báo.

## D. Các quyết định đã hợp nhất

`plans.md` là nguồn đặc tả hiện hành. Người dùng đã quyết định D02/D04/D05/D06/D07/D08, giao tự quyết D01/D03 và mọi chi tiết còn thiếu ngày 24/10/2026, với ưu tiên giữ lịch sử và dùng xóa mềm khi cần. Phần C đã áp dụng các quyết định dưới đây; tài liệu tổng hợp/rà soát cũ chỉ lưu lịch sử.

| Mã | Quyết định hiện hành | Nguồn và tham chiếu |
| --- | --- | --- |
| D01 | Hủy đăng ký tương lai bằng sự kiện có lý do, giữ bản ghi. Xóa hồ sơ/lớp là xóa mềm nên không chặn vì nợ; giữ khoản đã phát sinh/đã thu, hủy nghĩa vụ chưa thu tương lai không còn đối tượng. Lỗi tạo khoản lịch sử vẫn được theo dõi/chạy bù, không coi là đã thanh toán. | Tự quyết theo ủy quyền; STU-03, STU-01, CLASS-05, FEE-07. |
| D02 | Đóng đột xuất gỡ toàn bộ buổi chưa bắt đầu; mở lại tạo/khôi phục phần còn ở tương lai sau kiểm tra phòng/lễ. Đóng/xóa không thay quá khứ. Lớp xóa mềm giữ không thời hạn, khôi phục về Đóng; không tự hồi sinh khoảng tham gia/phân công đã kết thúc. | Người dùng chốt lịch; cách lưu trữ/khôi phục tự quyết; CLASS-03/05, SCHED-01, FEE-02/07. |
| D03 | Khoản ngoài học phí một lần áp theo ngày, định kỳ theo giao khoảng tham gia; vào giữa kỳ thu đủ, không trùng trong cùng hồ sơ. Đổi cấu hình chỉ áp lần phát sinh mới, sửa/hủy khoản chưa thu có lý do và lịch sử; khoản đã thu phải Admin gỡ sai trước. | Tự quyết theo ủy quyền; FEE-11. |
| D04 | Dùng khoản điều chỉnh cố định có dấu cho học phí từng học sinh/tháng hoặc kỳ, chỉ Admin cấu hình; không có đề xuất/duyệt hoặc phần trăm. Mức gốc + điều chỉnh không âm, bằng 0 là Không phải thu. | Người dùng chốt mô hình/quyền; chi tiết cách tính tự quyết; FEE-04. |
| D05 | Kết quả duy nhất theo học sinh/bài kiểm tra; nhận xét theo học sinh/bài hoặc học sinh/đợt. Sửa ngày bài không đẩy kết quả ra ngoài khoảng tham gia; tra cứu khoản tiền theo hồ sơ/kỳ áp dụng, không làm mất thu trước hoặc trả nợ sau nghỉ. | Người dùng chốt khóa; mốc bổ sung tự quyết; TEST-05, COMMENT-02, PORTAL-02. |
| D06 | User không xem chi tiết tiền/in giấy báo học phí; trợ giảng/Receptionist không sửa mô tả/thông báo trang lớp. Giáo viên có phân công hiệu lực và Admin vẫn sửa trang lớp đúng quyền. | Người dùng chốt Không; A.2, FEE-01, REPORT-01, PORTAL-01. |
| D07 | Xóa hồ sơ học sinh tại lớp rồi thêm lại tạo hồ sơ và khoản thu mới, kể cả cùng tháng/kỳ; mọi lịch sử cũ giữ riêng. Nghỉ/học lại trong cùng hồ sơ chưa xóa không tạo trùng nghĩa vụ. Học vụ vẫn dùng khóa học sinh/bài. | Người dùng chốt; CLASS-04, XLS-02, FEE-07. |
| D08 | Tên tra cứu bỏ dấu/đổi đ thành d, chuẩn hóa hoa thường/khoảng trắng, giữ tên có dấu hiển thị. Thêm tên chuẩn hóa đã có bắt buộc số phụ huynh; chặn trùng tên và giao số, kiểm tra cả bản lưu trữ. Số chuẩn hóa nhất quán nội bộ/Excel/phụ huynh. | Người dùng chốt tên/điều kiện số; chi tiết chuẩn hóa tự quyết; STU-04, XLS-06, PORTAL-02. |

### D.1. Các mặc định bổ sung đã quyết định

- **Tài khoản:** Giao mật khẩu tạm qua kênh ngoài sẵn có; cấp lại làm mất hiệu lực phiên/link cũ. Email lỗi không đổi mật khẩu. Quản trị Admin qua công cụ vận hành có audit, không qua ứng dụng.
- **Hồ sơ/lớp:** Không có trường riêng tùy biến ngoài bộ đã nêu. Lớp bắt buộc tên/môn/khối/ngày mở/kết thúc; ngày/khoảng đã kết thúc không tự mở lại khi gia hạn. Phân công không giới hạn số người, không chồng cùng người/lớp; môn phụ trách tùy chọn.
- **Quyền sửa học sinh (cập nhật 28/10/2026):** User gồm giáo viên/trợ giảng được sửa thông tin học sinh và lần tham gia trong lớp có phân công hiệu lực theo STU-04/STU-03, cùng các khóa nghiệp vụ như Admin/Receptionist. Không tạo học sinh, thêm vào lớp/tạo lần tham gia, xóa/hủy/khôi phục hoặc chuyển lớp/học lại. Áp dụng thống nhất UI/API/Excel; sửa hồ sơ tổng cập nhật dữ liệu dùng chung, không cấp quyền sửa lần tham gia ở lớp khác hoặc xem tài chính.
- **Danh mục/lịch:** Xóa mềm danh mục đã dùng; phòng/địa điểm có buổi đang diễn ra hoặc lịch tương lai phải xử lý lịch trước. Hai buổi liền giờ hợp lệ, không thêm khoảng đệm di chuyển. Buổi đã tới giờ bắt đầu không tạo/khôi phục lại; chỉ tương lai được dựng khi bỏ lễ/mở lớp.
- **Học vụ (cập nhật 28/10/2026):** Template số/phân số/chữ/IELTS dùng chung toàn trung tâm, chỉ Admin quản lý; bộ chữ 1–20 mức nằm trong template hoặc cấu hình riêng của bài, không còn thư viện chữ theo lớp. Bài số/phân số theo phần có 1–50 phần; IELTS theo kỹ năng/chế độ và công thức TEST-01. Bản sao của bài không bị thay bởi template mới. Cho trùng tên bài/đợt nhưng dùng mã đối chiếu; xóa là lưu trữ, khôi phục về Chưa công bố, giữ phiên bản nghiệp vụ độc lập audit.
- **Phụ huynh:** Chỉ nhân sự hiện còn phân công và tài khoản hoạt động được hiện công khai. Bật/tắt/reroll có xác nhận; link khôi phục giữ cấu hình đã lưu nhưng chỉ dùng sau mở lớp. Không khớp số không trả gợi ý hồ sơ.
- **Tài chính/in (cập nhật 28/10/2026):** Không hạn thanh toán/quá hạn. A4 điểm danh; A5 báo học phí; bổ sung biên nhận theo lần thu, giữ dữ liệu gốc và thể hiện gỡ thu. Admin quản lý nhiều mẫu Word/phiên bản và một default mỗi loại giấy tiền; hỗ trợ tải DOCX và preview/in trình duyệt trong tập bố cục giới hạn. User không xem/tải/in giấy tiền; không thêm giấy công nợ riêng hoặc bắt buộc xuất/lưu PDF.
- **Excel:** Sheet/cột/định danh tại XLS-06, file dưới 10.000.000 byte và tối đa 5.000 dòng mọi chức năng; xóa bản ghi không tồn tại là lỗi, dấu file đã nhập giữ không thời hạn. Chỉ một audit cho lần nhập thành công.
- **Thông báo/lịch sử:** Thông báo/audit giữ 60 ngày riêng; dữ liệu nghiệp vụ không bị xóa theo. Hết quyền mở thông báo thì báo không còn truy cập, không lộ chi tiết; giữ quyền đọc lịch sử theo đối tượng tại C.1.1.

Không còn câu hỏi D01–D08 hoặc chi tiết D.2 cũ ở trạng thái chờ quyết định. Tên bảng/API, thư viện và kỹ thuật lưu trữ do triển khai lựa chọn, phải giữ đúng các kết quả nghiệp vụ trên.
