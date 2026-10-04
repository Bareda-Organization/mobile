/// 이름 뒤에 붙는 `(으)로` — 받침이 있으면(ㄹ 받침 제외) `으로`, 없거나 ㄹ 이면 `로`.
///
/// 한글이 아닌 글자로 끝나는 이름은 받침을 알 수 없어 `(으)로` 로 둔다.
String euroOf(String name) {
  if (name.isEmpty) return '(으)로';
  final last = name.runes.last;
  const hangulStart = 0xAC00;
  const hangulEnd = 0xD7A3;
  if (last < hangulStart || last > hangulEnd) return '(으)로';
  final finalConsonant = (last - hangulStart) % 28;
  const noFinal = 0;
  const rieul = 8;
  return finalConsonant == noFinal || finalConsonant == rieul ? '로' : '으로';
}
