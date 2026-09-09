import re
import pathlib

ROOT = pathlib.Path(r'C:\wamp64\www\Pinoy_POS')
SERVICE = ROOT / 'lib' / 'services' / 'report_export_service.dart'

content = SERVICE.read_text(encoding='utf-8')

pdf_new = (ROOT / 'tmp_pdf.dart').read_text(encoding='utf-8')
excel_new = (ROOT / 'tmp_excel.dart').read_text(encoding='utf-8')

# Replace _buildPdf: from signature until its unique closing return.
pdf_pattern = re.compile(
    r'  Future<Uint8List> _buildPdf\([\s\S]*?\) async \{[\s\S]*?'
    r'    return Uint8List\.fromList\(await pdf\.save\(\)\);[\s\S]*?'
    r'  \}'
)
content = pdf_pattern.sub(pdf_new, content, count=1)

# Replace _buildExcel: from signature until its unique closing return.
excel_pattern = re.compile(
    r'  Future<Uint8List> _buildExcel\([\s\S]*?\) async \{[\s\S]*?'
    r'    return Uint8List\.fromList\(bytes\);[\s\S]*?'
    r'  \}'
)
content = excel_pattern.sub(excel_new, content, count=1)

SERVICE.write_text(content, encoding='utf-8')
print('Replacement complete.')
