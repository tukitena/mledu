# Sử dụng drawio-skill trong MLedu

## Cài đặt trong dự án

- Nguồn: [Agents365-ai/drawio-skill](https://github.com/Agents365-ai/drawio-skill).
- Đã cài ngày **26/10/2026**, phiên bản trong metadata: **3.4.3**.
- Phần skill được lấy từ `skills/drawio-skill` của nhánh `main`, bằng trình cài `skill-installer` của Codex.
- Vị trí: [`.agents/skills/drawio-skill/SKILL.md`](../../.agents/skills/drawio-skill/SKILL.md). Các script, reference, dữ liệu, style và giấy phép MIT đi kèm được giữ trong cùng thư mục.
- Đây là bản sao cài cục bộ cho repository MLedu; không tự cập nhật theo upstream. Quy tắc `/.agents/` trong `.gitignore` bỏ qua thư mục này; mỗi máy cần cài skill riêng từ nguồn ở trên.

Codex có thể nhận skill từ lượt trao đổi tiếp theo. Gọi đích danh `$drawio-skill` khi cần tạo hoặc sửa sơ đồ, ví dụ:

> Dùng $drawio-skill vẽ kiến trúc MLedu từ docs/developer/techstack.md, đối chiếu quy tắc nghiệp vụ trong docs/developer/plans.md. Lưu bản chỉnh sửa được vào docs/diagrams/architecture.drawio.

## Quy ước áp dụng

- [plans.md](plans.md) là nguồn nghiệp vụ; [techstack.md](techstack.md) là nguồn kiến trúc đã chốt. Ghi rõ sơ đồ mô tả thiết kế dự kiến khi ứng dụng chưa được triển khai.
- Lưu sơ đồ chính thức trong `docs/diagrams/`, giữ nguồn `.drawio` để chỉnh sửa và review. Chỉ tạo bản PNG/SVG/PDF khi cần chia sẻ.
- Không lấy kiến trúc, dependency hoặc cấu hình từ `template/` làm kiến trúc MLedu.
- Không đưa khóa, token, mật khẩu hoặc dữ liệu học sinh/phụ huynh thật vào sơ đồ và metadata.
- Đọc `SKILL.md` và reference phù hợp với loại sơ đồ trước khi tạo; chạy kiểm tra cấu trúc và kiểm tra bản render theo hướng dẫn của skill.

## Kiểm tra công cụ

Chạy từ gốc repository bằng PowerShell:

```powershell
# Trên máy hiện tại, draw.io Desktop đã cài nhưng chưa có trong PATH.
# Dòng này chỉ thêm đường dẫn cho phiên PowerShell hiện tại.
$env:PATH = 'C:\Program Files\draw.io;' + $env:PATH
python .agents/skills/drawio-skill/scripts/diagramctl.py doctor
python .agents/skills/drawio-skill/scripts/diagramctl.py --help
```

Đã xác nhận draw.io Desktop **32.6.1** có tại `C:\Program Files\draw.io\draw.io.exe` và `C:\Users\Admin\AppData\Local\Programs\draw.io\draw.io.exe`. Dùng đường dẫn trong `Program Files` cho các lệnh của dự án. Lần kiểm tra đầu báo `missing` vì script `doctor` chỉ dò `PATH` trên Windows; kết quả đó không có nghĩa ứng dụng chưa được cài. Sau khi thêm đường dẫn cho phiên hiện tại, `doctor` nhận draw.io và báo `native_export: true`; đây là kiểm tra phát hiện công cụ, chưa phải kiểm tra xuất file thực tế.

Python **3.14.2** và Git có sẵn. Chưa tìm thấy Graphviz trong `PATH`; công cụ này là tùy chọn cho bố trí tự động, độc lập với draw.io Desktop dùng để xuất PNG/SVG/PDF. Các gói YAML, PowerPoint cũng là tùy chọn và chưa được cài. Khi cần bố trí tự động, cài hoặc chỉ rõ vị trí [Graphviz](https://graphviz.org/download/), rồi chạy lại `doctor`. Không cần thêm MCP server để dùng các script cục bộ.

Cũng có thể gọi draw.io trực tiếp bằng đường dẫn đầy đủ mà không sửa `PATH`. Ví dụ xuất sơ đồ đã có sang PNG:

```powershell
& 'C:\Program Files\draw.io\draw.io.exe' -x -f png --width 2000 -o docs/diagrams/architecture.png docs/diagrams/architecture.drawio
```

Ví dụ kiểm tra sơ đồ sau khi tạo:

```powershell
python .agents/skills/drawio-skill/scripts/validate.py docs/diagrams/architecture.drawio --score
```

`.gitignore` bỏ qua `.agents/`, cache Python và file phục hồi draw.io; vẫn giữ nguồn `.drawio`, bản xuất chủ đích, tài liệu, migration SQL, lockfile và file Excel mẫu/fixture.
