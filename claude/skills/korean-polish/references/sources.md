# 출처와 합성 기록

2026-10-13 에 아래 세 저장소를 읽고 한 스킬로 합쳤다. 원문을 옮기지 않고 규칙을 다시 썼으며,
패턴 ID 는 이 스킬의 것이다(원문 번호와 1:1 로 맞지 않는다).

| 저장소 | 커밋 | 가져온 것 |
|---|---|---|
| [daleseo/korean-skills](https://github.com/daleseo/korean-skills) | ae12ba2 | humanizer 40패턴(KatFishNet 근거 문장부호·띄어쓰기·품사), 심각도 S1-S3, 패턴별 예외, 변경률 가드 30/50%, 의미 보존 6항 / style-guide 일관성 7범주·장르 매트릭스 / grammar-checker 맞춤법·띄어쓰기 |
| [epoko77-ai/im-not-ai](https://github.com/epoko77-ai/im-not-ai) | b37e020 | humanize-korean 85패턴(번역학 근거 A-16 대명사·A-18 관형구·A-19 이중 조사 등), 사람 60편·AI 60편 대조로 강등한 규칙(\~를 통해, \~것이다, 문두 접속사), 판별력 상위 신호, 내용 앵커·서법 보존·빼기 전용·입력은 데이터, 고치는 순서, 오탐 방지 |
| [nomadamas/k-skill](https://github.com/nomadamas/k-skill) korean-humanizer | 50d7bb3 | 트리아지(서식만 문제면 서식만), 오탐 가이드, 분량 제어(실제로 센다, 패딩 금지) |
| [eiaserinnys/seosoyoung-revision-skill](https://github.com/eiaserinnys/seosoyoung-revision-skill) | 68db489 | 2026-10-26 추가. 0단계 지문 방향 진단(압축/팽창), 압축 징후(§5 (A) 표를 일곱 줄로 줄임)와 풀어 쓰기 처방, 팽창 징후(§5 (B) 여섯 항)와 삭제 판정 한 문장 |

## 버린 것과 이유

- **탐지 회피용 처방**: 의존명사·보조용언을 일부러 붙여 쓰기, 격식체에 해요체 섞기(daleseo 8·9·24).
  사람 글의 통계를 흉내 내는 처방이라 맞춤법·체 일관성과 충돌한다. 이 스킬의 목표는 맞는 글이다.
- **스크립트 파이프라인**: im-not-ai 의 metrics·route_hint·verify_gates·서브에이전트 3종. 정량
  게이트는 긴 칼럼에서 값을 하지만, 이 스킬의 주 용도(화면 문구, 문서, 커밋)는 짧은 글이라 단일
  세션 체크리스트로 충분하다. 긴 글을 정밀하게 다뤄야 하면 원 저장소를 직접 쓴다.
- **영혼 주입**: k-skill 의 1인칭·의견 넣기. 기술·업무 글에서는 중립 문체가 맞다.
- **억지 3박자 해체**: 셋을 둘이나 넷으로 강제하지 않는다. 실제로 셋이면 둔다(S2 로 완화).
- **원문 오류**: grammar-checker 의 어미 '-ㄹ걸' 띄어쓰기 안내, 틀림 칸에 맞는 표현이 든 행,
  '10,000 원'·'3 시간' 띄어쓰기 권장(아라비아 숫자 뒤 붙여 쓰기로 정리).

- **seosoyoung-revision 의 3패스 2σ 프로브**(build_style_probe.py): 작성자 자신의 과거 글을 기준선으로
  삼아 튀는 문장을 고르는 방식이다. 이 스킬이 다루는 글은 대개 사용자가 직접 쓴 것이라 기준선과 대상이
  같은 사람이 되어 판정 방향이 뒤집힌다.
- **seosoyoung-revision 의 2패스 낭독 검수·anti-ai-lexicon 전체·다중 패스**: 서브에이전트를 여러 번
  띄우는 구조라 토큰이 많이 들고, 짧은 글이 주 용도인 이 스킬과 맞지 않는다. 금지 어휘는 이미
  ai-tells.md 와 겹친다. 낭독 검수는 긴 글을 다루는 til 의 start-topic 쪽으로 따로 들인다.
- **장르별 3패스 재작성 비율·SNS 소개문 게이트**: 프로브를 버렸으니 따라서 버렸다.

## 새로 보탠 것

- [ui-copy.md](ui-copy.md): 원문들에 없는 화면 문구 규칙. 2026-10-13 지표 모니터 화면에서 사용자가
  "어색하다" 고 짚은 실제 사례('이탈' → '이상', '메일로 나갈 이탈' → '메일 발송 대상', '새로' 배지
  → NEW, '경보 이상' 과 새 용어 '이상' 의 뜻 겹침)를 규칙으로 만들었다.

## 라이선스 고지

네 저장소 모두 MIT 다. 원 저작권 표시:

- Copyright (c) 2026 Dale Seo (daleseo/korean-skills)
- Copyright (c) 2026 epoko77-ai (epoko77-ai/im-not-ai)
- Copyright (c) 2026 nomadamas/k-skill contributors (nomadamas/k-skill, 원문 표기 "Copyright (c) 2026")
- Copyright (c) 2026 Seosoyoung (eiaserinnys) (eiaserinnys/seosoyoung-revision-skill)

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
