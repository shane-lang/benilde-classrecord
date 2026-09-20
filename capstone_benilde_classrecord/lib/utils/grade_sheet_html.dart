import '../models/class_model.dart';
import '../models/class_standing.dart';

String buildGradeSheetHtml({
  required ClassModel classModel,
  required ClassStanding standing,
  required String teacherName,
  String schoolName = 'St. Benilde',
  String officeName = 'Center for Global Competence, Inc.',
}) {
  final now = DateTime.now();
  final students = [...standing.students]
    ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

  final rows = StringBuffer();
  for (var i = 0; i < students.length; i++) {
    final s = students[i];
    final failing = s.finalGrade != null && s.finalGrade! < standing.passingGrade;
    rows.writeln('''
      <tr>
        <td class="num">${i + 1}</td>
        <td class="mono">${_esc(s.studentNumber)}</td>
        <td class="name">${_esc(s.fullName)}</td>
        <td class="num">${_grade(s.prelim)}</td>
        <td class="num">${_grade(s.midterm)}</td>
        <td class="num">${_grade(s.finals)}</td>
        <td class="num final${failing ? ' fail' : ''}">${_grade(s.finalGrade)}</td>
        <td class="remark">${_esc(_remarkFor(s, standing.passingGrade))}</td>
      </tr>''');
  }

  final title = classModel.subjectCode.isNotEmpty
      ? '${classModel.subjectCode} — ${classModel.subjectName}'
      : classModel.subjectName;

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Grade sheet — ${_esc(title)}</title>
<style>
  /* A4 with the margins a registrar's binder expects. */
  @page { size: A4 portrait; margin: 14mm 12mm 16mm 12mm; }

  * { box-sizing: border-box; }

  body {
    font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 10.5pt;
    color: #14201a;
    margin: 0;
    padding: 18px;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  .sheet { max-width: 900px; margin: 0 auto; }

  header { text-align: center; border-bottom: 2px solid #0E6B3A; padding-bottom: 10px; }
  header .school { font-size: 13pt; font-weight: 700; letter-spacing: .2px; }
  header .office { font-size: 9.5pt; color: #54615a; margin-top: 2px; }
  header .doc    { font-size: 12pt; font-weight: 700; margin-top: 10px;
                   letter-spacing: 2px; color: #0E6B3A; }

  .meta { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 28px;
          margin: 14px 0 16px; font-size: 10pt; }
  .meta div { display: flex; gap: 8px; }
  .meta .k { color: #54615a; min-width: 96px; }
  .meta .v { font-weight: 600; }

  table { width: 100%; border-collapse: collapse; font-size: 10pt; }

  /* Repeats the headings at the top of every printed page. */
  thead { display: table-header-group; }
  tr { page-break-inside: avoid; }

  th, td { border: 1px solid #c9d3cc; padding: 5px 7px; }
  th { background: #eef4f0; font-weight: 700; font-size: 9.5pt;
       text-align: center; }
  td.num { text-align: center; }
  td.mono { font-family: "Consolas", "Courier New", monospace; font-size: 9.5pt; }
  td.name { text-align: left; }
  td.final { font-weight: 700; }
  td.fail { color: #b91c1c; }
  td.remark { text-align: center; font-size: 9pt; }
  tbody tr:nth-child(even) td { background: #fbfcfb; }

  .signatures { margin-top: 38px; max-width: 320px;
                page-break-inside: avoid; }
  .sig { font-size: 9.5pt; }
  .sig .line { border-top: 1px solid #14201a; margin-top: 34px; padding-top: 4px;
               font-weight: 700; }
  .sig .role { color: #54615a; }

  footer { margin-top: 26px; font-size: 8.5pt; color: #8a968f;
           border-top: 1px solid #e1e6e2; padding-top: 7px;
           display: flex; justify-content: space-between; }

  .noprint { margin: 0 auto 16px; max-width: 900px; text-align: center; }
  .noprint button {
    font: inherit; font-weight: 600; cursor: pointer;
    background: #0E6B3A; color: #fff; border: 0;
    padding: 10px 20px; border-radius: 8px;
  }
  .noprint .hint { font-size: 9pt; color: #54615a; margin-top: 7px; }

  @media print { .noprint { display: none !important; } body { padding: 0; } }
</style>
</head>
<body>

<div class="noprint">
  <button onclick="window.print()">Print this grade sheet</button>
  <div class="hint">Choose “Save as PDF” in the print dialog to keep a copy.</div>
</div>

<div class="sheet">
  <header>
    <div class="school">${_esc(schoolName)}</div>
    <div class="office">${_esc(officeName)}</div>
    <div class="doc">REPORT OF GRADES</div>
  </header>

  <div class="meta">
    <div><span class="k">Subject</span><span class="v">${_esc(title)}</span></div>
    <div><span class="k">School year</span><span class="v">${_esc(_orDash(classModel.schoolYear))}</span></div>
    <div><span class="k">Course</span><span class="v">${_esc(_orDash(classModel.course))}</span></div>
    <div><span class="k">Year &amp; section</span><span class="v">${_esc(_orDash(classModel.yearSection))}</span></div>
    <div><span class="k">Instructor</span><span class="v">${_esc(_orDash(teacherName))}</span></div>
    <div><span class="k">Students</span><span class="v">${students.length}</span></div>
  </div>

  <table>
    <thead>
      <tr>
        <th style="width:34px">#</th>
        <th style="width:110px">Student no.</th>
        <th>Name</th>
        <th style="width:62px">Prelim</th>
        <th style="width:66px">Midterm</th>
        <th style="width:62px">Finals</th>
        <th style="width:70px">Final</th>
        <th style="width:84px">Remarks</th>
      </tr>
    </thead>
    <tbody>
${rows.toString()}
    </tbody>
  </table>

  <div class="signatures">
    <div class="sig">
      <div class="role">Prepared by</div>
      <div class="line">${_esc(_orDash(teacherName))}</div>
      <div class="role">Instructor</div>
    </div>
  </div>

  <footer>
    <span>Benilde ClassRecord</span>
    <span>Printed ${_esc(_longDateTime(now))}</span>
  </footer>
</div>

</body>
</html>''';
}

String _grade(double? v) => v == null ? '—' : v.toStringAsFixed(2);

String _orDash(String v) => v.trim().isEmpty ? '—' : v.trim();

String _remarkFor(StudentGrade s, double passing) {
  if (s.remark.isNotEmpty) return s.remark;
  if (s.finalGrade == null) return 'No grades';
  return s.finalGrade! >= passing ? 'Passing' : 'At risk';
}

String _esc(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _longDateTime(DateTime d) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final suffix = d.hour >= 12 ? 'PM' : 'AM';
  final minute = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, ${d.year} at $hour12:$minute $suffix';
}