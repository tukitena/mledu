# MLedu — Tech stack đã chốt và dự toán vận hành

Ngày ghi nhận và đối chiếu giá: **26/10/2026**.

Tài liệu này ghi lại lựa chọn kỹ thuật đã được chấp nhận trong trao đổi. [plans.md](plans.md) tiếp tục là nguồn đặc tả nghiệp vụ hiện hành; tài liệu này không thay đổi quyền, quy tắc dữ liệu hoặc tiêu chí nghiệm thu trong đó. Giá và giả định chi phí ở phần cuối là dự toán, không phải cam kết tải hoặc quyết định mua dịch vụ.

## 1. Kiến trúc đã chốt

**Vue 3 + TypeScript + Vite → Cloudflare Pages; Cloudflare Workers + Hono → Supabase Auth, PostgreSQL, Storage, Realtime và Cron.**

| Lớp | Công nghệ | Trách nhiệm |
| --- | --- | --- |
| Frontend | Vue 3, TypeScript, Vite, Vue Router | SPA cho các workspace nội bộ và trang phụ huynh; route, component và trạng thái giao diện. Đọc/xuất file `.xlsx` ngay tại trình duyệt (mục 5.1). |
| Giao diện | Bootstrap 5, SCSS, Bootstrap Icons | Xây dựng giao diện trong source chính thức, tham khảo hình thức của Metis. |
| Biểu đồ | ApexCharts + `vue3-apexcharts` | Dashboard theo vai trò (DASH-01); điều kiện giấy phép tại mục 3. |
| Hosting web | Cloudflare Pages | Build và phục vụ tài nguyên tĩnh của SPA. |
| API | Cloudflare Workers, Hono, TypeScript | Kiểm tra đầu vào, xác thực yêu cầu, API phụ huynh, nhận dữ liệu Excel đã được trình duyệt trích thành JSON để kiểm tra/áp dụng, và các thao tác cần quyền backend. |
| Xác thực | Supabase Auth | Đăng nhập email/mật khẩu, phiên và khôi phục mật khẩu; bổ sung kiểm tra để đáp ứng chính xác AUTH-01 đến AUTH-08. |
| Dữ liệu | PostgreSQL do Supabase quản lý | Dữ liệu quan hệ, RLS, constraint, khóa và transaction. Dùng phiên bản PostgreSQL được Supabase hỗ trợ tại lúc tạo project. |
| Giao dịch nghiệp vụ | PostgreSQL functions, gọi qua RPC | Thực hiện nguyên khối các lệnh thu/gỡ thu, chuyển lớp, đóng/mở lớp, nhập Excel và audit liên quan. |
| File | Supabase Storage | Ảnh hồ sơ; bucket private và quyền đọc/ghi theo nghiệp vụ. File Excel không lưu lên Storage (mục 5.1). |
| Cập nhật trực tiếp | Supabase Realtime | Báo có thay đổi để SPA tải lại thông báo, số chưa đọc hoặc dữ liệu theo quyền hiện hành. |
| Tác vụ | Supabase Cron, bảng job/outbox | Sinh nghĩa vụ học phí, chạy bù, phân phối thông báo, thử lại và dọn audit/thông báo hết hạn. |
| Email | SMTP riêng kết nối Supabase Auth | Email đặt lại mật khẩu; nhà cung cấp cụ thể chưa chốt. |
| Kiểm thử | Kiểm thử PostgreSQL/RLS, API và trình duyệt | Kiểm tra nghiệp vụ, quyền, giao dịch đồng thời và thao tác trên điện thoại/máy tính. Bộ công cụ cụ thể chọn khi khởi tạo dự án. |

Lựa chọn backend chính là **Workers + Supabase**. Supabase Edge Functions là phương án thay thế lớp API để so sánh, không triển khai song song mặc định. Hono hỗ trợ [Workers](https://hono.dev/docs/getting-started/cloudflare-workers); Supabase cung cấp [database functions/RPC](https://supabase.com/docs/guides/database/functions).

Lộ trình và cấu trúc thư mục được mô tả tại [kế hoạch triển khai MLedu](Implementation-plan.md). Repository đã có source ứng dụng và migration được áp dụng local; xem [schema PostgreSQL hiện tại](schema.md) để phân biệt cấu trúc đã triển khai với thiết kế của các giai đoạn sau. Trạng thái local không xác nhận CI hoặc hosted/staging/production.

### 1.1. Ranh giới giao tiếp frontend

| Luồng | Đường đi |
| --- | --- |
| Đọc/ghi nghiệp vụ nội bộ và tra cứu phụ huynh | Vue → Workers/Hono → PostgreSQL/RPC. |
| Đăng nhập và refresh phiên thông thường | Vue dùng Supabase Auth SDK; khi gọi API gửi JWT để backend kiểm tra phiên, trạng thái và quyền hiện hành. |
| Quản trị tài khoản, đổi/đặt lại mật khẩu và thao tác xác thực cần audit | Theo luồng backend được thiết kế và kiểm chứng cho AUTH-01–08; không dùng lời gọi SDK trực tiếp để bỏ qua kiểm tra/audit. |
| Realtime | Vue kết nối kênh được cấp quyền để nhận tín hiệu thay đổi tối thiểu, sau đó lấy dữ liệu mới qua API. |
| Truyền file | API cấp quyền cho đúng đường dẫn; trình duyệt có thể truyền trực tiếp tới Storage bằng quyền/URL được cấp. Bước kiểm tra và xác nhận cập nhật nghiệp vụ vẫn qua API. Hiện chỉ áp dụng cho avatar. |
| Excel | Trình duyệt đọc `.xlsx` và gửi dữ liệu đã trích dạng JSON qua request API thông thường; file không rời trình duyệt. Xuất mẫu cũng tạo tại trình duyệt từ dữ liệu API trả về. |

Không dùng việc frontend có publishable key làm lý do mở quyền đọc/ghi rộng các bảng hoặc RPC. Quyền truy cập trực tiếp ngoài API vẫn phải được thu hẹp và kiểm thử theo mục 4.1–4.3.

## 2. Quy định về Metis và thư mục tham khảo

**Metis chỉ là template tham khảo. Không lấy Metis làm bộ khung source code của dự án.**

- Đường dẫn dự kiến trong dự án là **`template/`**, được đưa vào `.gitignore` bằng quy tắc `/template/` khi khởi tạo dự án.
- `template/` không tham gia tổ chức source code, workspace/package, dependency graph, TypeScript project, routing, build, lint, test, CI/CD hoặc artifact deploy.
- Source chính thức không import, alias, symlink, đọc lúc runtime hoặc dùng script lấy tài nguyên tự động từ `template/`.
- Không dùng `package.json`, lockfile, cấu hình Vite, tài liệu DEVELOPMENT/CLAUDE hoặc workflow CI của Metis làm cấu hình hay quy ước mặc định của dự án.
- Dùng template để xem bố cục, màu sắc, cách trình bày component và hành vi giao diện. Component, SCSS, asset và logic của ứng dụng được tổ chức độc lập trong source chính thức.
- Chọn dependency trực tiếp cho ứng dụng; không sao chép toàn bộ dependency hoặc số phiên bản từ template. Bootstrap được cài như dependency của ứng dụng.
- Khi thiếu hoặc xóa toàn bộ `template/`, dự án vẫn phải cài dependency, build, kiểm thử và deploy được bình thường.
- Script đóng gói/deploy phải chỉ rõ đầu vào và không đưa `template/` vào bundle hoặc upload cả repository như tài nguyên web.

Thư mục đang có trong workspace là `metis-v1.0.0/`. Lần ghi nhận tài liệu này **không di chuyển/đổi tên thư mục và không tạo hoặc sửa `.gitignore`**; quy định trên áp dụng cho dự án sẽ khởi tạo.

## 3. Tổ chức frontend

- Xây SPA Vue với component, route và logic của MLedu; chuyển cách thể hiện tham khảo từ template thành các component độc lập.
- Vue quản lý trạng thái và vòng đời component. Không đưa Alpine của template vào làm lớp quản lý trạng thái thứ hai cho cùng vùng DOM.
- Tách giao diện nội bộ và trang phụ huynh theo route/layout; quyền dữ liệu luôn được kiểm tra phía backend.
- Lựa chọn ngôn ngữ Việt/Anh và giao diện sáng/tối/theo hệ thống lưu theo trình duyệt. Lưu riêng lựa chọn `system` với màu thực tế đang áp dụng.
- In điểm danh A4 bằng HTML/CSS. Giấy báo học phí và biên nhận dùng mẫu Word `.docx` do Admin tải lên, điền marker trong trình duyệt để tải DOCX và preview/in qua HTML/CSS theo REPORT-01 và mục 4.7 (quyết định 28/10/2026). Chỉ hỗ trợ tập bố cục đã kiểm chứng, không cam kết render mọi file như Microsoft Word.
- Build SPA ra thư mục output riêng, dự kiến `dist/`; cấu hình fallback để tải trực tiếp/reload route con hoạt động. Không mang cơ chế build nhiều trang của Metis sang ứng dụng.

Cloudflare có hướng dẫn [deploy Vue lên Pages](https://developers.cloudflare.com/pages/framework-guides/deploy-a-vue-site/). Pages mặc định xử lý fallback SPA khi không có `404.html` cấp gốc; khi triển khai cần kiểm tra điều kiện này trên artifact thực tế. [Nguồn routing](https://developers.cloudflare.com/pages/configuration/serving-pages/)

Các thư viện bổ trợ đã khảo sát gồm FullCalendar Standard cho lịch, Tabulator cho bảng phức tạp, Tom Select cho tìm/chọn và SweetAlert2 cho xác nhận. Các gói này đã được cài và khóa phiên bản; wrapper Vue và mức sử dụng vẫn chốt qua kiểm tra tích hợp ở giai đoạn dùng đến. **Đọc/ghi XLSX: chốt SheetJS CE 0.20.3** (Apache-2.0) tại trình duyệt, cài từ kênh phát hành chính thức `https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz` vì gói `xlsx` trên npm registry dừng ở 0.18.5 và có lỗ hổng đã công bố. Lockfile ghi URL và integrity; khi nâng phiên bản phải đổi URL tarball và xem trang security advisories của SheetJS.

**Biểu đồ: chốt ApexCharts** (quyết định ngày 27/10/2026), dùng `apexcharts` 8.5.0 và `vue3-apexcharts` 1.11.3. ApexCharts không dùng giấy phép MIT mà theo [mô hình theo doanh thu](https://apexcharts.com/license/); không suy từ giấy phép của template:

- **Community License (miễn phí)** chỉ áp dụng khi đơn vị sử dụng — kể cả công ty mẹ/đơn vị liên kết — có doanh thu, ngân sách hoạt động hoặc nguồn tài trợ hằng năm **dưới 2 triệu USD**. Vượt ngưỡng phải mua giấy phép thương mại (Pro/Premium tính theo developer).
- Chỉ dùng các loại biểu đồ trong gói mặc định. Các tính năng Premium (Unit/Waffle, Raincloud, Trellis, Storyboard, Linked Views, Ink, Measure Ruler, Context Menu, Perspectives, Rewind) cần license key; không import các module này.
- Community License không cho nhúng vào sản phẩm/nền tảng phân phối cho bên khác dùng (cần OEM). MLedu là ứng dụng nội bộ của trung tâm; nếu sau này đóng gói bán hoặc cung cấp cho đơn vị khác thì phải xem lại giấy phép.
- Đơn vị vận hành cần xác nhận mình đủ điều kiện Community trước khi đưa lên production. Điều khoản có thể đổi theo phiên bản, nên đọc lại `LICENSE.md` khi nâng cấp gói.

## 4. Ranh giới backend và dữ liệu

### 4.1. API và transaction

- Workers kiểm tra request và điều phối; PostgreSQL là nơi kiểm tra lại quyền/điều kiện nghiệp vụ và ghi các thay đổi cần nguyên khối.
- Một lệnh nghiệp vụ nhiều bước gọi một RPC bao trùm toàn bộ thay đổi, audit và yêu cầu thông báo bắt buộc. Không coi nhiều request insert/update riêng lẻ là một transaction.
- Thu hẹp schema và quyền được công khai qua Data API. Chỉ cấp quyền ghi theo các lệnh đã thiết kế; kiểm tra cả truy cập trực tiếp ngoài giao diện.
- Function dùng `SECURITY DEFINER` chỉ khi cần, đặt trong phạm vi phù hợp, giới hạn quyền execute, cố định `search_path` và kiểm tra rõ người thực hiện/phạm vi. Không mặc định rằng RLS sẽ bảo vệ mọi function chạy với quyền chủ sở hữu.
- Kiểm soát phiên bản cho cập nhật, khóa các bản ghi cần thiết và dùng constraint/khóa duy nhất để chống thu trùng, tạo nghĩa vụ trùng, nhập lại file và lịch phòng chồng nhau.

### 4.2. Xác thực và phân quyền

- Phân biệt loại tài khoản Admin/Receptionist/User với vai trò giáo viên/trợ giảng theo từng lớp.
- RLS và RPC đọc trạng thái tài khoản, yêu cầu đổi mật khẩu và phân công có hiệu lực tại thời điểm yêu cầu. Không lấy workspace đang hiển thị làm quyền backend.
- Quyền sửa học sinh ngày 28/10/2026 theo STU-04/STU-03: tách quyền sửa khỏi tạo/thêm/xóa/khôi phục. User sửa hồ sơ tổng qua quan hệ học sinh–lớp chưa xóa thuộc một phân công hiện hành; sửa lần tham gia phải kiểm tra chính lớp của lần đó. Cả giáo viên/trợ giảng dùng cùng phạm vi sửa, vẫn chịu khóa ngày và ràng buộc nghiệp vụ. Không mở rộng helper quản trị chung để vô tình cấp quyền thêm/xóa; API/RPC kiểm tra lại phạm vi, version và audit, kể cả khi apply Excel sau preview. Phần UI/API/RPC đã triển khai và kiểm chứng local ngày 29/10/2026 theo [biên bản quyền sửa](decisions/student-edit-permissions.md); Excel chưa triển khai, vẫn theo GĐ8.
- Không chỉ dựa vào role trong JWT để áp dụng quyền mới tức thời; JWT có thể chưa phản ánh thay đổi đến khi refresh. [Nguồn RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- Bổ sung kiểm tra phiên hiện hành qua helper backend/database được giới hạn quyền để vô hiệu phiên đúng AUTH-02/03/04/08. Supabase hướng dẫn đối chiếu `session_id` với `auth.sessions` khi cần chặn access token còn hạn sau đăng xuất. [Nguồn sessions](https://supabase.com/docs/guides/auth/sessions)
- SPA dùng publishable key. Secret key chỉ nằm trong backend secrets; thao tác dùng quyền cao phải có kiểm tra quyền rõ ràng vì secret key bỏ qua RLS. Yêu cầu nội bộ thông thường chuyển tiếp JWT người dùng để giữ ngữ cảnh phân quyền. [Nguồn API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- Quản trị tài khoản Admin dùng công cụ vận hành có audit theo AUTH-06, không thêm route quản trị Admin vào ứng dụng.

### 4.3. Trang phụ huynh

- API riêng trên Workers nhận token liên kết lớp và số điện thoại, giới hạn tần suất, chuẩn hóa rồi trả dữ liệu đúng phạm vi PORTAL-01/02/03.
- Không tạo tài khoản phụ huynh hoặc bật anonymous sign-in của Supabase cho luồng tra cứu này; phụ huynh vẫn chưa xác thực theo đặc tả.
- Không mở quyền đọc rộng các bảng học sinh, học vụ hoặc tài chính cho `anon`; endpoint public dùng truy vấn/function giới hạn dữ liệu, không để người gọi bỏ qua bước kiểm soát của API.
- Kiểm tra bật/tắt/reroll liên kết, vòng đời lớp/hồ sơ, khoảng tham gia và trạng thái công bố mỗi lần tra cứu. Dữ liệu trả về không chứa ghi chú nội bộ, phiên bản bị thay thế hoặc học vụ chưa công bố.
- Không cache chung phản hồi cá nhân hoặc phản hồi nội bộ ở CDN; asset SPA được cache độc lập với dữ liệu nghiệp vụ.

### 4.4. Lịch sử và kiểu dữ liệu

- Tách học sinh tổng, hồ sơ học sinh–lớp và lần tham gia. Nghĩa vụ tài chính gắn hồ sơ lớp; điểm gắn học sinh/bài; điểm danh gắn học sinh/buổi theo plans.md.
- Lưu riêng lịch sử phiên bản và sự kiện nghiệp vụ không thời hạn. Audit và thông báo có thời hạn 60 ngày; không dùng log nền tảng làm audit nghiệp vụ.
- Thời gian nghiệp vụ dùng `Asia/Ho_Chi_Minh`; tách ngày nghiệp vụ với timestamp sự kiện. Quyền và hạn token được kiểm tra tại request, không đợi cron.
- Tiền VND lưu bằng số nguyên; điểm số thông thường chính xác đến 0,01. IELTS dùng số chính xác cho trung bình/trọng số, không cắt trung gian về 0,01; chỉ làm tròn theo đúng các bước TEST-01. Tránh sai số floating point ở biên 0,25/0,75. Chuẩn hóa tên/số điện thoại theo STU-04 tại backend và dùng thống nhất cho UI/API/Excel/phụ huynh.
- Lịch phòng kiểm tra theo buổi thực tế và khoảng [bắt đầu, kết thúc); có ràng buộc chống trùng khi gửi đồng thời. Trùng giờ nhân sự chỉ cảnh báo như đặc tả.

### 4.5. Avatar và luồng lưu file

- Ảnh avatar nằm trong bucket private **`avatars`**. Hồ sơ tài khoản lưu **`account_profiles.avatar_path text NULL`**, là đường dẫn tương đối trong bucket, ví dụ `<user_id>/<file_id>.webp`. Tên bucket dùng cấu hình ứng dụng; file giữ định dạng được kiểm tra, không tự đổi đuôi để giả chuyển định dạng.
- Không lưu binary, Base64 hoặc signed URL vào cột hồ sơ; không tạo FK avatar tới schema `storage`. Supabase quản lý object và metadata nội bộ; upload/di chuyển/xóa file qua Storage API. [Nguồn Storage schema](https://supabase.com/docs/guides/storage/schema/design).
- Chỉ chủ tài khoản được đổi avatar theo AUTH-08. Workers xác định user từ phiên, cấp đường dẫn mới duy nhất dưới thư mục của user, kiểm tra JPG/PNG/WebP và kích thước **tối đa 5.000.000 byte** ở backend. Không chỉ tin tên file, MIME do trình duyệt khai báo hoặc thông báo upload thành công từ client.
- Luồng đổi ảnh: xin quyền upload → tải ảnh mới lên Storage → backend xác minh file thực tế → một RPC cập nhật `avatar_path`, phiên bản hồ sơ và audit → sau khi commit mới xếp việc dọn ảnh cũ. Trước commit, avatar hiện hành vẫn là ảnh cũ.
- Storage upload và transaction PostgreSQL là hai thao tác riêng. Nếu upload thành công nhưng cập nhật hồ sơ/audit thất bại, giữ path cũ và dọn file mới chưa được tham chiếu. Việc dọn phải kiểm tra lại không có hồ sơ đang dùng file; không xóa ảnh còn hiệu lực khi có hai lần đổi ảnh đồng thời. Nhật ký/audit chỉ ghi path và thay đổi nghiệp vụ phù hợp, không ghi token/URL upload hoặc URL đọc có chữ ký.
- Khi xem ảnh, API kiểm tra quyền và cấp URL ngắn hạn hoặc tải qua luồng có xác thực. URL được sinh khi cần, không lưu làm định danh lâu dài. Signed URL còn dùng được đến hết hạn; nếu chức năng đòi thu hồi quyền đọc ngay tại từng request thì dùng luồng tải kiểm tra quyền mỗi lần. [Nguồn truy cập bucket private](https://supabase.com/docs/guides/storage/buckets/fundamentals).

Lựa chọn này chỉ áp dụng tham chiếu avatar. Excel không dùng Storage: file được đọc tại trình duyệt theo mục 5.1.

### 4.6. Template bài kiểm tra và IELTS

Quyết định 28/10/2026 thay thư viện mẫu thang chữ riêng trong lớp bằng **thư viện template bài kiểm tra chung toàn trung tâm, chỉ Admin quản lý**. Giáo viên/trợ giảng chọn dùng theo quyền học vụ và chỉnh cấu hình riêng của bài; không có quyền ghi template. Chọn template là tùy chọn, không mở rộng quyền cho Receptionist.

- Template là cấu hình có kiểu, không phải mã/công thức chạy tùy ý: số/phân số/chữ/IELTS, chế độ nhập, phần/kỹ năng và mức/tiêu chí. Bộ mức chữ nằm trong cấu hình đó. Bài lưu snapshot đầy đủ, nguồn/phiên bản nếu có; sửa/xóa template không lan sang bài đã tạo.
- Cấu hình IELTS chọn kỹ năng L/R/W/S và chế độ riêng từng kỹ năng, thống nhất cả bài. L/R không tự quy đổi; W chi tiết có hai Task với bốn tiêu chí mỗi Task; S chi tiết có bốn tiêu chí. Backend tính Task, W/S và Overall theo TEST-01; client chỉ hiển thị dự tính, RPC tính lại khi ghi. Band đầu vào của L/R hoặc chế độ trực tiếp là dữ liệu người dùng, không phải giá trị suy ra từ số câu.
- Lưu đầu vào, cấu hình và phiên bản công thức để giữ lịch sử; công thức IELTS cố định theo TEST-01, không cho người dùng/template tùy chỉnh. Đổi cấu hình sau khi có điểm phải qua TEST-03; khóa công bố, Vắng, thiếu dữ liệu và lọc chi tiết phụ huynh vẫn áp dụng. Import Excel gửi đầu vào đúng schema/phiên bản bài, không áp template mới hoặc tin cột tổng/Overall.
- Công thức làm tròn từng Task rồi Writing là **quy tắc MLedu do người dùng chốt**. Nguồn IELTS xác nhận bốn tiêu chí, trung bình và nguyên tắc Overall; không dùng nguồn này để tuyên bố đã xác minh riêng bước làm tròn trung gian Task. [IELTS scoring](https://ielts.org/take-a-test/your-results/ielts-scoring-in-detail).

### 4.7. Mẫu Word, giấy báo và biên nhận

**Đã chọn ngày 28/10/2026:** xử lý DOCX và preview/in trong trình duyệt với giới hạn bố cục; đồng thời tải được Word đã điền. Phương án bộ chuyển đổi DOCX → PDF riêng chưa được chọn, không thêm dịch vụ, container hoặc Supabase Edge Functions để làm API thứ hai.

**Luồng dự kiến, chưa triển khai:**

1. Admin xin quyền upload mẫu → upload `.docx` vào Storage private → backend kiểm tra file thực tế, cấu trúc/marker và quyền → một RPC lưu metadata/phiên bản và audit. Mẫu chỉ được kích hoạt sau kiểm tra/preview bằng dữ liệu giả; upload chưa commit không thay mẫu đang dùng.
2. Mỗi loại giấy tiền có nhiều mẫu và một default do Admin quản lý. Ràng buộc DB/khóa đảm bảo thay default nguyên khối; giữ phiên bản được bản in tham chiếu. Không dùng bucket `avatars` hoặc pipeline Excel cho mẫu Word.
3. Admin/Receptionist lấy phiên bản mẫu và DTO dữ liệu qua API được phân quyền. File mẫu dùng cơ chế tải private có kiểm tra quyền; không công khai file học sinh/tài chính cho dịch vụ viewer bên ngoài. Browser không truy vấn trực tiếp bảng nghiệp vụ.
4. Trình duyệt điền marker/vùng lặp vào DOCX. Cùng DOCX đã điền là nguồn tải xuống và preview/in HTML/CSS. Công việc ZIP/điền mẫu có thể đưa vào Web Worker phía trình duyệt; render DOM vẫn ở luồng giao diện. Xử lý lô có giới hạn, cho hủy và giải phóng buffer sau mỗi nhóm; không thay đổi tính nguyên khối của giao dịch tiền.
5. Backend cấp mã biên nhận và snapshot giao dịch cùng transaction thu. Lần phát hành đầu lưu liên kết phiên bản mẫu; bước tạo file độc lập sau commit, có thể thử lại mà không thu lại. In lại dùng dữ liệu gốc/phiên bản mẫu đã ghi, kèm trạng thái hủy hiện hành. Quyền đọc lại được kiểm tra; file đã tải/giấy đã in không thể thu hồi từ xa và không phải nguồn dữ liệu tài chính.

**Khảo sát khả thi:** Docxtemplater hỗ trợ tạo DOCX từ marker trong browser và có ví dụ Vue; thư viện điền mẫu không tự render PDF. `docx-preview` chuyển DOCX thành HTML, bị giới hạn bởi khả năng bố cục HTML. Đây là các ứng viên để thử, chưa cài dependency/chốt phiên bản hoặc nghiệm thu trong MLedu. Core templating có lựa chọn mã nguồn mở; tính năng nâng cao có thể cần module riêng, phải kiểm tra license khi chọn. [Browser templating](https://docxtemplater.com/docs/get-started-browser/), [conversion/licensing](https://docxtemplater.com/faq/), [DOCX preview](https://github.com/VolodymyrBaydalka/docxjs).

**Trần nền tảng:** Workers Free có 10 ms CPU/request; Paid mặc định 30 giây, tối đa 5 phút; cả hai có 128 MB/isolate. Không chạy LibreOffice native trực tiếp trong Worker: `child_process` chỉ là stub. Nâng gói không tự thêm engine Word; Browser Run in HTML thành PDF cũng không phải engine bố cục Word. Supabase Pro không tự cung cấp DOCX renderer; Edge Functions vẫn có trần CPU 2 giây/request và 256 MB. Luồng đã chọn đặt dựng tài liệu ở thiết bị người dùng; Worker vẫn phải có ngân sách kiểm tra mẫu và cấp dữ liệu. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Node compatibility](https://developers.cloudflare.com/workers/runtime-apis/nodejs/), [Browser PDF](https://developers.cloudflare.com/api/resources/browser_rendering/subresources/pdf/methods/create/), [Edge limits](https://supabase.com/docs/guides/functions/limits).

**Giới hạn cần kiểm chứng trước GĐ9:**

- Chỉ hỗ trợ tập đoạn văn/bảng/ảnh trong dòng/header-footer/ngắt trang đã thử; không cam kết font, shape nổi hoặc phân trang tùy ý như Word. Giữ đủ dữ liệu quan trọng; nếu mẫu dùng tính năng ngoài tập hỗ trợ thì báo lỗi, không tự làm mất nội dung.
- Cần chốt mức tối đa byte DOCX nén, byte sau giải nén/số ZIP entry, ảnh, dòng và phiếu mỗi lượt dựa trên fixture giả/mẫu được duyệt ở desktop và mobile. Không áp ngầm giới hạn 10 MB/5.000 dòng của Excel hoặc 5 MB avatar cho DOCX. Chưa có số đo để công bố một trần lô in an toàn.
- Backend kiểm tra dung lượng/cấu trúc file, danh sách marker và tài nguyên ngoài; không chỉ tin MIME hoặc báo cáo client. Chặn ZIP bomb, macro/đối tượng nhúng, tài liệu mã hóa, XML external entities; marker là dữ liệu thuần có whitelist, không thực thi JS/biểu thức từ mẫu. Preview cô lập kiểu dáng/nội dung, không tải tài nguyên ngoài từ tài liệu.
- Kiểm chứng tên dài, Unicode, nhiều dòng khoản, nhiều trang, font sẵn có, marker bị Word tách thành nhiều text run, vùng lặp và gỡ thu. Preview/DOCX/bản in cùng dữ liệu; không cắt mất số tiền/trạng thái. Mẫu biên nhận thiếu marker bắt buộc về mã/giao dịch/trạng thái hủy không được kích hoạt.
- Template file ở Storage không cùng transaction với DB; audit lỗi giữ metadata/default cũ, dọn orphan chỉ khi không được tham chiếu. Bổ sung mẫu và phiên bản vào kế hoạch backup/restore nội dung Storage cùng liên kết DB.

**Hiện trạng khảo sát 28/10/2026:** repo mới có nền Auth, phân quyền, học sinh/lớp/lần tham gia và avatar private; chưa có module học vụ/IELTS, thư viện template, thu tiền/biên nhận, upload DOCX hoặc preview/in. Chưa chạy thử renderer với mẫu thực tế, chưa triển khai dịch vụ chuyển đổi tài liệu và chưa xác nhận tài khoản hosted đang mua gói nào. Các mục trên là thiết kế/điều kiện nghiệm thu, không phải bằng chứng tính năng đã hoàn tất.

## 5. Excel, tác vụ và thông báo

### 5.1. Đồng bộ Excel

Luồng đã chốt (27/10/2026, thay luồng upload file lên backend trước đó): **trình duyệt đọc `.xlsx` → trích thành JSON theo hợp đồng → API kiểm tra và trả bản xem trước (không ghi) → người dùng xác nhận → API kiểm tra lại → một RPC/transaction áp dụng**. File không được upload lên Storage hay Worker; không có bảng staging phía server.

**Trình duyệt (`apps/web/src/features/imports/`):**

- Chỉ nhận `.xlsx` theo mẫu, dưới 10.000.000 byte, tối đa 5.000 dòng dữ liệu; kiểm tra sheet `DuLieu`/`_Meta`, cột và cột ẩn mã/phiên bản.
- Đọc giá trị ô, **không tính công thức**: ô có công thức hoặc macro là lỗi. Ngày là ô ngày Excel hoặc `YYYY-MM-DD`; số điện thoại đọc dạng text; giữ đúng nghĩa ô trống và `XÓA` theo XLS-04.
- Chuyển thành JSON có `rowNumber` và tên cột để gắn lỗi về đúng dòng/cột. Lỗi phát hiện ở trình duyệt được báo ngay nhưng **không thay kiểm tra ở backend**.
- Xuất mẫu cũng tạo tại trình duyệt từ dữ liệu API trả về (mã ẩn, `PhienBan`, `_Meta`).

**Request gửi về backend là request API JSON thông thường.** Mỗi phạm vi (học sinh tổng, học sinh tại lớp, điểm, nhận xét) có hai thao tác:

| Thao tác | Nội dung | Ghi dữ liệu |
| --- | --- | --- |
| Xem trước | `{ scope, meta, rows[] }` → danh sách Thêm/Sửa/Xóa, giá trị hiện tại/dự kiến, lỗi theo dòng/cột, xung đột phiên bản, file đã nhập | Không |
| Áp dụng | Cùng payload, gửi lại sau khi người dùng xác nhận | Một RPC: toàn bộ dòng, một audit, dấu chống nhập lại |

Các quy tắc XLS-04/05/06 trong `plans.md` giữ nguyên. Hệ quả cho triển khai:

- **Một lần áp dụng là một request và một transaction.** Không tách thành nhiều request ghi theo từng dòng hoặc từng nhóm, vì như vậy không bảo đảm được "lỗi một dòng chặn toàn file", không để lại thay đổi dở dang và đúng một audit.
- **Backend không tin dữ liệu từ trình duyệt:** kiểm tra lại quyền và phân công hiện hành, số dòng (≤ 5.000), giới hạn kích thước body, kiểu dữ liệu, chuẩn hóa STU-04, mã/phiên bản, khóa công bố, trạng thái lưu trữ, trùng khóa trong file — ở cả bước xem trước và áp dụng.
- **Chống nhập lại:** backend tính dấu SHA-256 từ payload đã chuẩn hóa theo thứ tự cố định cùng phạm vi/lớp/bài/đợt, lưu không thời hạn khi áp dụng thành công. Tên file không nằm trong dấu nên đổi tên không vượt qua. Hash file do trình duyệt gửi (nếu có) chỉ để hiển thị, không dùng làm khóa.
- **Giới hạn 10.000.000 byte** là giới hạn của file nên chỉ kiểm tra được ở trình duyệt; backend chặn bằng số dòng và kích thước body. Gọi API trực tiếp không qua file vẫn chịu toàn bộ kiểm tra nghiệp vụ ở trên.

**Hiệu năng — đóng, không đo (quyết định 27/10/2026).** Chấp nhận độ trễ khi đọc file lớn trên trình duyệt (nhất là điện thoại) và khi áp dụng file lớn; không làm benchmark và không coi hiệu năng Excel là điều kiện chặn của bất kỳ giai đoạn nào. Cách làm giảm rủi ro mà không cần số đo:

- Đọc file trong Web Worker để giao diện không bị treo; hiển thị trạng thái đang xử lý.
- SheetJS đọc với `cellFormula: true` (phát hiện ô công thức để báo lỗi; thư viện không tính công thức) và `cellStyles: true` (đọc cột ẩn); sheet ẩn đọc qua `Workbook.Sheets[].Hidden`.
- Nếu một lần áp dụng vượt timeout thì xử lý ở tầng DB (khóa, xử lý theo lô trong cùng transaction, cấu hình timeout của RPC), không chia thành nhiều transaction.

Tiêu chí **chức năng** của `plans.md` vẫn phải đạt và được kiểm thử ở GĐ 8: file 5.000 dòng hợp lệ không bị cắt, file 5.001 dòng hoặc từ 10.000.000 byte bị từ chối, cả file nguyên khối với một audit.

### 5.2. Tác vụ nền và Realtime

- Supabase Cron quét mốc đến hạn ít nhất mỗi 5 phút; dùng lịch sử để chạy bù khi gián đoạn. [Nguồn Cron](https://supabase.com/docs/guides/cron)
- Bảng job/outbox lưu định danh sự kiện, đối tượng, trạng thái, lần thử, lỗi cuối và lần thử kế tiếp. Thử lại theo AUD-01; lỗi dữ liệu chờ dữ liệu liên quan thay đổi.
- Tạo yêu cầu thông báo cùng transaction nghiệp vụ; phân phối sau và chống trùng theo sự kiện/người nhận. Không coi tác vụ trong bộ nhớ của một request là hàng đợi bền vững.
- Realtime chỉ phát tín hiệu thay đổi tối thiểu, không phát nội dung tài chính/học vụ nhạy cảm vào kênh chung. SPA lấy dữ liệu mới qua API có kiểm tra quyền; có cơ chế đồng bộ lại khi kết nối lại.
- Quyền Broadcast channel có thể được cache trong thời gian kết nối, nên kiểm tra quyền tại lần lấy dữ liệu vẫn là bắt buộc. [Nguồn Realtime](https://supabase.com/docs/guides/realtime/authorization)

## 6. Các điểm phải kiểm chứng khi triển khai

Các mục dưới đây là tiêu chí kỹ thuật còn phải chứng minh, không phải thay đổi nghiệp vụ hoặc phương án stack đang chờ chọn:

1. Luồng Supabase Auth đáp ứng đúng link 5 phút, một lần dùng, cấp lại vô hiệu link cũ, bắt đổi mật khẩu tạm và thu hồi đúng các phiên. Cấu hình mặc định không được coi là đã đạt nghiệm thu.
2. Thiết kế audit cho thao tác Auth: gọi Auth Admin API rồi ghi audit là hai giao dịch. Phải giải quyết ranh giới này và thử lỗi để đáp ứng yêu cầu audit bắt buộc; không tự hạ xuống cơ chế bù như một ngoại lệ nghiệp vụ. Nếu nền tảng không bảo đảm được cần báo rõ để điều chỉnh triển khai hoặc thống nhất lại yêu cầu.
3. Kiểm tra quyền với token/phiên cũ, hết phân công giữa preview và xác nhận, tài khoản khóa/xóa và yêu cầu đổi mật khẩu chưa hoàn tất.
4. Kiểm tra hai yêu cầu đặt phòng/thu tiền/nhập cùng file đồng thời, lỗi audit và rollback đầy đủ.
5. ~~Benchmark Excel cực đại~~ — **đóng ngày 27/10/2026, không đo**; chấp nhận độ trễ (mục 5.1). Vẫn kiểm thử chức năng với file 5.000 dòng ở GĐ 8. Timeout DB tham khảo: [Nguồn timeout](https://supabase.com/docs/guides/database/postgres/timeouts)
6. Kiểm tra bản build không có template, không chứa secret; route con SPA, màn hình nhỏ và in A4/A5 hoạt động đúng.
7. Tách môi trường local/staging/production và kiểm tra khôi phục dữ liệu. Backup database của Supabase không bao gồm nội dung file trong Storage, nên cần kế hoạch sao lưu file riêng. [Nguồn backup](https://supabase.com/docs/guides/platform/backups)

Đã chốt ngày 27/10/2026: đọc/xuất Excel tại trình duyệt bằng SheetJS CE 0.20.3, ApexCharts cho biểu đồ, không benchmark hiệu năng Excel. Phiên bản patch, nhà cung cấp SMTP và gói compute mua thực tế chưa được chốt bởi tài liệu này. Cấu trúc source có phương án đề xuất trong [kế hoạch triển khai](Implementation-plan.md), cần kiểm chứng khi khởi tạo dự án.

## 7. So sánh chi phí ở quy mô MLedu

### 7.1. Phạm vi và giả định dự toán

- Quy mô đặc tả: 1.500 học sinh, 100 lớp, 100 tài khoản nội bộ; không suy thành 100 người dùng đồng thời hoặc 1.500 tài khoản Auth.
- Giá niêm yết USD được kiểm tra ngày 26/10/2026; compute theo giờ nên tổng thực tế có thể lệch mốc tháng làm tròn.
- Quy đổi minh họa **1 USD = 26.000 VND**, chỉ là tỷ giá lập ngân sách, không phải tỷ giá ngân hàng cập nhật.
- Bảng nền tảng giả định một production project, chưa vượt quota, email nằm trong gói miễn phí và không mua add-on riêng. Staging tính ở bảng riêng.
- Không gồm thuế, chênh lệch tỷ giá/phí thẻ, tên miền, nhân công phát triển/vận hành, bản quyền tùy chọn (kể cả giấy phép thương mại ApexCharts nếu không đủ điều kiện Community), sao lưu ngoài nền tảng hoặc dung lượng vượt quota.

Kịch bản lưu lượng để tính thử, chưa phải số đo thực tế:

| Nguồn | Giả định | API request/tháng |
| --- | --- | ---: |
| Nội bộ | 100 tài khoản × 200 request/ngày × 26 ngày | 520.000 |
| Phụ huynh | Giả sử 1.500 người × 20 lượt/tháng × 5 request/lượt | 150.000 |
| Tác vụ và phần dự phòng khác | Quy ước dự toán | 50.000 |
| Tổng cơ sở | Cộng ba nhóm | **720.000** |

Nếu 720.000 request cơ sở trung bình 10 ms CPU và thêm 1.000 request Excel (xem trước + áp dụng của 500 lần nhập), mỗi request giả sử 200 ms CPU để kiểm tra JSON, tổng là **721.000 request và 7.400.000 CPU-ms/tháng**. Đây chỉ là ví dụ billing: việc đọc file chạy ở trình duyệt nên không tính CPU Worker, thời gian chờ network không phải CPU, và bước kiểm tra JSON phải được đo riêng. Lượng request không bao gồm các lượt tải asset tĩnh qua Pages.

### 7.2. Chi phí từng dịch vụ

| Dịch vụ | Mốc giá/dự toán | Ghi chú |
| --- | ---: | --- |
| Cloudflare Pages Free | **$0/tháng** | Hosting SPA; tối đa 500 build/tháng trên Free. API Worker được tính riêng. |
| Cloudflare Workers Paid | **từ $5/tháng** | Đã gồm 10 triệu request và 30 triệu CPU-ms/tháng; kịch bản tính thử trên nằm trong phần bao gồm. |
| Supabase Pro | **$25/tháng** | Phí tổ chức; compute được tính rồi trừ compute credit theo công thức bên dưới. |
| Supabase Micro | **khoảng $10/tháng trước credit** | Paid plan có $10 compute credit mỗi tổ chức/tháng. |
| Supabase Small | **khoảng $15/tháng trước credit** | Nâng một production project từ Micro lên Small làm tăng khoảng $5/tháng. |
| Email qua Resend Free, ví dụ để tính | **$0 trong quota** | 3.000 email/tháng, tối đa 100/ngày; cần xác minh domain và cấu hình SMTP. Nhà cung cấp chưa được chốt. |

Nguồn: [Pages limits](https://developers.cloudflare.com/pages/platform/limits/), [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Supabase pricing](https://supabase.com/pricing), [compute và credit](https://supabase.com/docs/guides/platform/manage-your-usage/compute), [Resend quota](https://resend.com/docs/knowledge-base/account-quotas-and-limits).

Compute credit áp dụng **một lần cho mỗi tổ chức mỗi tháng**, không phải $10 cho mỗi project. Với một project Micro: Supabase ≈ $25 + $10 − $10 = **$25**. Với một project Small: ≈ $25 + $15 − $10 = **$30**. Nguồn và cách tính theo [Supabase Compute](https://supabase.com/docs/guides/platform/manage-your-usage/compute).

Để theo dõi dung lượng, Pro hiện gồm 8 GB disk/project, 100 GB file storage và 250 GB egress thông thường ở phạm vi tổ chức; quota Auth là 100.000 MAU. Với 100 tài khoản nội bộ, chi phí Auth theo MAU chưa phải yếu tố chính. Dữ liệu lịch sử giữ lâu dài vẫn cần theo dõi tăng trưởng; không khẳng định dung lượng đủ vĩnh viễn. [Nguồn quota/billing](https://supabase.com/docs/guides/platform/billing-on-supabase)

Realtime Pro gồm 5 triệu message/tháng; phần vượt được tính theo gói triệu message. Ước lượng phải tính số lần phân phối tới các subscriber, không chỉ số bản ghi thông báo. [Nguồn Realtime usage](https://supabase.com/docs/guides/platform/manage-your-usage/realtime-messages)

### 7.3. So sánh các phương án production

| Phương án | Công thức tháng | USD/tháng | VND/tháng minh họa | USD/năm |
| --- | --- | ---: | ---: | ---: |
| **Đã chọn: Pages + Workers Paid + Supabase Pro/Micro** | 0 + 5 + (25 + 10 − 10) | **≈ $30** | **780.000** | **≈ $360** |
| **Đã chọn, nâng DB Small** | 0 + 5 + (25 + 15 − 10) | **≈ $35** | **910.000** | **≈ $420** |
| Phương án so sánh: Pages + Supabase Edge Functions/Micro | 0 + (25 + 10 − 10), function trong quota | ≈ $25 | 650.000 | ≈ $300 |
| Phương án so sánh: Laravel + PostgreSQL tự quản trên một VPS | VPS $24 + backup hằng ngày 30% | ≈ $31.20 | 811.200 | ≈ $374.40 |

Phương án Supabase Edge Functions giả định không dùng Workers Paid và không vượt 2 triệu lượt gọi function/tháng của Pro. Tiết kiệm khoảng $5/tháng so với stack đã chọn; vì Excel được đọc ở trình duyệt, giới hạn CPU 2 giây/request chỉ còn ảnh hưởng tới bước kiểm tra JSON. [Nguồn function usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations)

VPS minh họa là DigitalOcean Basic Regular 4 GiB RAM/2 vCPU giá $24/tháng; backup hằng ngày cộng 30%, tức $7.20. Phương án này tự vận hành ứng dụng, PostgreSQL, worker, cập nhật hệ điều hành và phục hồi. Bảng không mặc định VPS đáp ứng tải và không coi tài nguyên/SLA của VPS tương đương Supabase managed. [Giá Droplet](https://www.digitalocean.com/pricing/droplets), [giá backup](https://www.digitalocean.com/pricing/backups)

So với VPS $31.20, stack đã chọn Micro thấp hơn khoảng $1.20/tháng, Small cao hơn khoảng $3.80/tháng. Chênh lệch tiền nền tảng nhỏ; lợi ích của lựa chọn đã chốt nằm ở dịch vụ Auth/Storage/Realtime được quản lý và giảm việc quản trị máy chủ. Đổi lại, cần đầu tư thiết kế RPC/RLS và kiểm thử các giới hạn runtime. Chưa có dữ liệu để định giá nhân công hay kết luận tổng chi phí sở hữu bằng một con số.

### 7.4. Khi thêm staging

| Môi trường trong cùng một tổ chức Pro | Supabase/tháng | Cộng Workers Paid | Tổng nền tảng/tháng |
| --- | ---: | ---: | ---: |
| Production Micro + staging Micro | 25 + 10 + 10 − 10 = $35 | $5 | **≈ $40** |
| Production Small + staging Micro | 25 + 15 + 10 − 10 = $40 | $5 | **≈ $45** |

Giả định Workers production/staging cùng tài khoản Paid và tổng usage còn trong quota; không cộng thêm $5 chỉ vì có thêm một Worker. Supabase tính compute riêng từng project; không có project Free trong cùng một tổ chức Pro. Có thể dùng local cho phát triển hoặc tổ chức Free riêng cho môi trường thử nghiệm phù hợp giới hạn. [Nguồn Supabase organization billing](https://supabase.com/docs/guides/platform/billing-on-supabase), [nguồn Workers account pricing](https://developers.cloudflare.com/workers/platform/pricing/)

### 7.5. Ngân sách đề xuất và các khoản làm tăng hóa đơn

- Dùng **$30/tháng** làm mốc nền tảng cho một production Micro; dự trù **$35–50/tháng**, tương đương **910.000–1.300.000 VND/tháng** theo tỷ giá quy ước, để có khoảng nâng compute hoặc biến động nhỏ. Khoảng dự trù không phải gói dịch vụ hoặc trần hóa đơn.
- Nếu giữ staging trả phí liên tục, dùng mốc **$40–45/tháng** trước phần dự phòng và các khoản loại trừ. Việc chọn Micro hay Small phải dựa vào đo tải và theo dõi CPU, RAM, query/lock, không chỉ số lượng học sinh.
- Audit 60 ngày của MLedu nằm trong database ứng dụng và có tính vào dung lượng; retention log của nhà cung cấp không thay cho audit này.
- Supabase Pro có backup database hằng ngày, giữ 7 ngày. Nếu cần phục hồi tới thời điểm gần sự cố hơn, PITR là add-on riêng: mốc 7 ngày khoảng $100/tháng và cần tối thiểu compute Small. Như vậy stack Small + Workers + PITR vào khoảng **$135/tháng**, chưa gồm staging/chi phí khác. Đây là lựa chọn về phục hồi chưa được quyết định mua. [Nguồn backup/PITR](https://supabase.com/docs/guides/platform/backups)
- Sao lưu nội dung Storage ra nơi khác, tên miền, email trả phí, dung lượng/egress vượt quota, tăng compute và giấy phép thương mại ApexCharts (khi đơn vị từ 2 triệu USD/năm trở lên hoặc cần tính năng Premium) có thể phát sinh thêm. Chưa gộp các khoản chưa có yêu cầu hoặc số đo vào mốc $30/$35.
- Giới hạn CPU mỗi request, giới hạn tần suất tra cứu công khai và cảnh báo usage giúp kiểm soát chi phí. Kiểm tra lại bảng giá khi triển khai; không coi spend cap là trần cho mọi hạng mục, đặc biệt compute. [Nguồn compute billing](https://supabase.com/docs/guides/platform/manage-your-usage/compute)
